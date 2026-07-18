//
//  LibrarySync.swift
//  WatchList
//
//  Keeps the local library and the iCloud-mirrored SyncedEntry store in step.
//
//  Only the user's personal state (watch status, rating, notes) plus a seed id
//  (IMDb / TMDb) live in iCloud. Each device rebuilds the full title from TMDb
//  using the seed (via ImportCoordinator). Conflicts resolve last-writer-wins on
//  a per-title timestamp. See the plan for the confirmed scope (top-level only;
//  manual entries carry their basics + poster).
//

import Foundation
import SwiftData
import CoreData

// MARK: - Shared shape over Show & Film

/// The bits LibrarySync needs from a top-level title, so Shows and Films can be
/// reconciled with one code path.
protocol SyncableTitle: AnyObject {
	var kind: MediaKind { get }
	var stableID: UUID { get }
	var imdbID: String? { get }
	var tmdbID: Int? { get }
	var status: WatchStatus { get set }
	var rating: Rating? { get set }
	var notes: String { get set }
	var dateAdded: Date { get }
	var posterURL: String { get set }
	var syncKey: String? { get set }
	var personalUpdatedAt: Date? { get set }
	var displayTitle: String { get }
	var displayYear: String { get }
	var displayGenre: String { get }
}

extension Show: SyncableTitle {
	var kind: MediaKind { .show }
	var stableID: UUID { id }
	var displayTitle: String { title }
	var displayYear: String { firstAirYear }
	var displayGenre: String { genre }
}

extension Film: SyncableTitle {
	var kind: MediaKind { .film }
	var stableID: UUID { id }
	var displayTitle: String { title }
	var displayYear: String { year }
	var displayGenre: String { genre }
}

// MARK: - Coordinator

@MainActor
final class LibrarySync {
	private let container: ModelContainer
	private var started = false
	private var isReconciling = false

	/// Keys that were present locally after the last reconcile. Used to tell a
	/// local deletion (key was here, now gone, entry still exists) apart from a
	/// remote creation (entry exists, never was local).
	private let ledgerKey = "sync.lastSeenKeys"

	init(container: ModelContainer) { self.container = container }

	func start() {
		guard !started else { return }
		started = true
		NotificationCenter.default.addObserver(
			forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
		) { [weak self] _ in
			Task { await self?.reconcile() }
		}
	}

	/// Idempotent two-way reconcile. Safe to call repeatedly.
	func reconcile() async {
		guard !isReconciling else { return }
		isReconciling = true
		defer { isReconciling = false }

		let ctx = ModelContext(container)
		ctx.autosaveEnabled = false

		do {
			let shows = try ctx.fetch(FetchDescriptor<Show>())
			let films = try ctx.fetch(FetchDescriptor<Film>())
			let entries = try ctx.fetch(FetchDescriptor<SyncedEntry>())

			var entryByKey: [String: SyncedEntry] = [:]
			for e in entries where entryByKey[e.key] == nil { entryByKey[e.key] = e }

			let lastSeen = Set(UserDefaults.standard.stringArray(forKey: ledgerKey) ?? [])
			var liveKeys = Set<String>()

			// 1) Push local titles up, link to existing records, honour remote deletes.
			push(shows, ctx: ctx, entryByKey: &entryByKey, lastSeen: lastSeen, liveKeys: &liveKeys)
			push(films, ctx: ctx, entryByKey: &entryByKey, lastSeen: lastSeen, liveKeys: &liveKeys)

			// 2) Local deletions: was live last pass, gone now, record still present.
			for key in lastSeen where !liveKeys.contains(key) {
				if let e = entryByKey[key] {
					ctx.delete(e)
					entryByKey[key] = nil
				}
			}

			// 3) Pull: records with no local title get hydrated from TMDb (or built
			//    from the manual basics).
			for (key, entry) in entryByKey where !liveKeys.contains(key) {
				await hydrate(entry, ctx: ctx)
				liveKeys.insert(key)
			}

			try ctx.save()
			UserDefaults.standard.set(Array(liveKeys), forKey: ledgerKey)
		} catch {
			// Non-fatal: the next trigger retries.
		}
	}

	// MARK: Push

	private func push<T: PersistentModel & SyncableTitle>(
		_ items: [T], ctx: ModelContext,
		entryByKey: inout [String: SyncedEntry], lastSeen: Set<String>, liveKeys: inout Set<String>
	) {
		for item in items {
			let key = item.syncKey ?? Self.key(for: item)
			if let entry = entryByKey[key] {
				item.syncKey = key
				merge(item, entry)
				liveKeys.insert(key)
			} else if let sk = item.syncKey, lastSeen.contains(sk) {
				// Was synced; its record is gone → deleted on another device.
				ctx.delete(item)
			} else {
				// New locally → create the record.
				let entry = makeEntry(from: item, key: key)
				ctx.insert(entry)
				entryByKey[key] = entry
				item.syncKey = key
				liveKeys.insert(key)
			}
		}
	}

	/// Merge personal state between a local title and its record (last-writer-wins,
	/// but only when they actually differ, so incidental local saves don't clobber).
	private func merge<T: SyncableTitle>(_ item: T, _ entry: SyncedEntry) {
		let same = item.status == entry.watchStatus
			&& item.rating == entry.ratingValue
			&& item.notes == entry.notes
		guard !same else { return }

		let localTime = item.personalUpdatedAt ?? .distantPast
		if localTime >= entry.updatedAt {
			entry.status = item.status.rawValue
			entry.rating = item.rating?.rawValue
			entry.notes = item.notes
			entry.updatedAt = item.personalUpdatedAt ?? .now
		} else {
			item.status = entry.watchStatus
			item.rating = entry.ratingValue
			item.notes = entry.notes
			item.personalUpdatedAt = entry.updatedAt
		}
	}

	private func makeEntry<T: SyncableTitle>(from item: T, key: String) -> SyncedEntry {
		let manual = item.tmdbID == nil && (item.imdbID ?? "").isEmpty
		let entry = SyncedEntry(
			key: key,
			mediaKind: item.kind,
			imdbID: item.imdbID,
			tmdbID: item.tmdbID,
			status: item.status,
			rating: item.rating,
			notes: item.notes,
			dateAdded: item.dateAdded,
			isManual: manual,
			manualTitle: manual ? item.displayTitle : "",
			manualYear: manual ? item.displayYear : "",
			manualGenre: manual ? item.displayGenre : "",
			manualPosterData: manual ? Self.posterData(item.posterURL) : nil
		)
		entry.updatedAt = item.personalUpdatedAt ?? .now
		return entry
	}

	// MARK: Pull / hydrate

	private func hydrate(_ entry: SyncedEntry, ctx: ModelContext) async {
		if entry.isManual || (entry.tmdbID == nil && (entry.imdbID ?? "").isEmpty) {
			buildManual(entry, ctx: ctx)
			return
		}

		let importer = ImportCoordinator()
		var created: Any?
		if let tmdbID = entry.tmdbID {
			created = await importer.importFromTMDb(id: tmdbID, kind: entry.kind, into: ctx)
		} else if let imdbID = entry.imdbID {
			created = await importer.importFromIMDb(imdbID, into: ctx)
		}

		if let show = created as? Show { apply(entry, to: show) }
		else if let film = created as? Film { apply(entry, to: film) }
		// If the fetch failed, leave the record unhydrated; a later reconcile retries.
	}

	private func buildManual(_ entry: SyncedEntry, ctx: ModelContext) {
		switch entry.kind {
		case .show:
			let show = Show(title: entry.manualTitle, genre: entry.manualGenre,
			                firstAirYear: entry.manualYear, imdbID: entry.imdbID,
			                status: entry.watchStatus, rating: entry.ratingValue, notes: entry.notes)
			if let data = entry.manualPosterData, let path = ManualPosterStore.save(data) { show.posterURL = path }
			apply(entry, to: show)
			ctx.insert(show)
		case .film:
			let film = Film(title: entry.manualTitle, genre: entry.manualGenre, year: entry.manualYear,
			                imdbID: entry.imdbID, status: entry.watchStatus, rating: entry.ratingValue, notes: entry.notes)
			if let data = entry.manualPosterData, let path = ManualPosterStore.save(data) { film.posterURL = path }
			apply(entry, to: film)
			ctx.insert(film)
		}
	}

	private func apply<T: SyncableTitle>(_ entry: SyncedEntry, to item: T) {
		item.status = entry.watchStatus
		item.rating = entry.ratingValue
		item.notes = entry.notes
		item.syncKey = entry.key
		item.personalUpdatedAt = entry.updatedAt
	}

	// MARK: Helpers

	static func key<T: SyncableTitle>(for item: T) -> String {
		if let tmdbID = item.tmdbID { return "tmdb:\(item.kind.rawValue):\(tmdbID)" }
		if let imdbID = item.imdbID, !imdbID.isEmpty { return "imdb:\(item.kind.rawValue):\(imdbID)" }
		return "manual:\(item.stableID.uuidString)"
	}

	private static func posterData(_ urlString: String) -> Data? {
		guard urlString.hasPrefix("file:"), let url = URL(string: urlString) else { return nil }
		return try? Data(contentsOf: url)
	}
}
