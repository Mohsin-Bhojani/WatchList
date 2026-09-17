//
//  WatchSync.swift
//  WatchList
//
//  The iPhone's end of the link with the watch app (Shared/WatchLink.swift) —
//  the one place the iPhone app talks to WatchConnectivity:
//    - sends a PhoneSnapshot as the application context shortly after the
//      library is saved and whenever the app comes to the front, while a paired
//      watch has the watch app installed
//    - applies the watch's actions through the same code the iPhone's own
//      screens use: HomeFeed.markWatched for a rating, ImportCoordinator for Add,
//      a SuggestionDecision for Not interested and Later. Each comes queued with
//      transferUserInfo, and as a message too while the watch can reach the
//      iPhone; it's applied once, whichever copy is first, and named in the
//      snapshots after it so the watch can stop laying it over what it shows.
//    - answers the watch's refresh message with a snapshot there and then
//  An action that arrives before the library does — the app woken in the
//  background, before its window — waits in UserDefaults until it's here.
//
//  Nothing here changes the models or the store.
//

import Foundation
import OSLog
import SwiftData
import SwiftUI
import WatchConnectivity

final class WatchSync: NSObject {
	static let shared = WatchSync()

	/// Episodes to come sent for each show, so the watch can move on without the iPhone.
	static let upcomingCount = 6

	fileprivate let log = Logger(subsystem: "com.mohsin.WatchList", category: "WatchSync")
	private var context: ModelContext?
	private var saveObserver: NSObjectProtocol?
	private var debounce: Task<Void, Never>?
	/// Titles added from the watch still being imported, so none is added twice.
	private var adding: Set<String> = []

	private enum Keys {
		/// Actions waiting for the library.
		static let waiting = "watchWaitingActions"
		/// Actions applied, and when each was made on the watch.
		static let applied = "watchAppliedActions"
	}

	/// Starts the session. Called as the app launches, before any window, so the
	/// watch's actions can arrive with the app in the background.
	func activate() {
		// False on an iPad, which has no watch.
		guard WCSession.isSupported() else { return }
		WCSession.default.delegate = self
		WCSession.default.activate()
	}

	/// Hands over the library, applies what the watch sent before it was here,
	/// and keeps the watch up to date from here on.
	func attach(_ context: ModelContext) {
		guard self.context == nil else { return }
		self.context = context
		saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil,
		                                                      queue: .main) { _ in
			Task { @MainActor in WatchSync.shared.scheduleSend() }
		}
		applyWaiting()
		scheduleSend()
	}

	// MARK: Sending

	/// A paired watch with the watch app on it, and the session ready. Otherwise
	/// there's no one to send to: the watch shows what it last had.
	private var watchIsThere: Bool {
		guard WCSession.isSupported() else { return false }
		let session = WCSession.default
		return session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
	}

	/// Sends a snapshot shortly, once a run of saves has settled.
	func scheduleSend() {
		guard watchIsThere, context != nil else { return }
		debounce?.cancel()
		debounce = Task {
			try? await Task.sleep(for: .milliseconds(700))
			guard !Task.isCancelled else { return }
			send()
		}
	}

	private func send() {
		guard watchIsThere, let data = packedSnapshot() else { return }
		do {
			try WCSession.default.updateApplicationContext([WatchLink.snapshotKey: data])
		} catch {
			log.error("The watch's application context wasn't updated: \(error.localizedDescription, privacy: .public)")
		}
	}

	/// The snapshot as it travels, trimmed until it fits WatchConnectivity's
	/// limit: fewer episodes to come and fewer seeds before anything's dropped.
	fileprivate func packedSnapshot() -> Data? {
		guard let context else { return nil }
		let shows = (try? context.fetch(FetchDescriptor<Show>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]))) ?? []
		let films = (try? context.fetch(FetchDescriptor<Film>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]))) ?? []
		let decisions = (try? context.fetch(FetchDescriptor<SuggestionDecision>())) ?? []
		let applied = Set(appliedActions().map(\.id))
		var packed: Data?
		for (upcoming, seeds) in [(Self.upcomingCount, 200), (3, 80), (1, 30)] {
			let snapshot = WatchSnapshotBuilder.snapshot(shows: shows, films: films, decisions: decisions,
			                                             applied: applied, upcoming: upcoming, seeds: seeds)
			packed = WatchLink.pack(snapshot)
			if let packed, packed.count <= WatchLink.payloadBudget { return packed }
		}
		log.error("The watch snapshot is over budget at \(packed?.count ?? 0) bytes")
		return packed
	}

	// MARK: The watch's actions

	fileprivate func receive(_ data: Data) {
		guard let action = WatchLink.unpack(WatchAction.self, from: data) else {
			log.error("An action from the watch couldn't be read")
			return
		}
		guard let context else {
			var waiting = UserDefaults.standard.array(forKey: Keys.waiting) as? [Data] ?? []
			waiting.append(data)
			UserDefaults.standard.set(waiting, forKey: Keys.waiting)
			return
		}
		apply(action, in: context)
	}

	private func applyWaiting() {
		guard let context, let waiting = UserDefaults.standard.array(forKey: Keys.waiting) as? [Data] else { return }
		UserDefaults.standard.removeObject(forKey: Keys.waiting)
		for data in waiting {
			if let action = WatchLink.unpack(WatchAction.self, from: data) { apply(action, in: context) }
		}
	}

	private func apply(_ action: WatchAction, in context: ModelContext) {
		// transferUserInfo delivers once, but a reinstall or a restore can replay.
		guard !appliedActions().contains(where: { $0.id == action.id }) else { return }
		if case .add(let kind, let tmdbID) = action.change {
			add(kind, tmdbID, for: action, in: context)
			return
		}
		WatchActionApplier.apply(action, in: context)
		finish(action, in: context)
	}

	/// As Discover adds: imported in the background, a show with every episode.
	/// Applied once the import ends either way — one that failed comes back to
	/// Discover on the watch, as it does on the iPhone.
	private func add(_ kind: MediaKind, _ tmdbID: Int, for action: WatchAction, in context: ModelContext) {
		let key = kind.key(tmdbID: tmdbID)
		guard !WatchActionApplier.isInLibrary(kind, tmdbID, in: context) else { return finish(action, in: context) }
		guard adding.insert(key).inserted else { return }
		Task {
			let added = await ImportCoordinator().importFromTMDb(id: tmdbID, kind: kind, into: context)
			if added == nil { log.error("Adding \(key, privacy: .public) from the watch failed") }
			adding.remove(key)
			finish(action, in: context)
		}
	}

	private func finish(_ action: WatchAction, in context: ModelContext) {
		remember(action)
		do {
			try context.save()
		} catch {
			log.error("Saving the watch's action failed: \(error.localizedDescription, privacy: .public)")
		}
		// A save sends too; an action that changed nothing still has to be named.
		scheduleSend()
	}

	/// An action applied, kept for as long as the watch waits to hear of it.
	private struct Applied: Codable {
		let id: UUID
		let madeAt: Date
	}

	private func appliedActions() -> [Applied] {
		UserDefaults.standard.data(forKey: Keys.applied)
			.flatMap { try? JSONDecoder().decode([Applied].self, from: $0) } ?? []
	}

	private func remember(_ action: WatchAction) {
		let cutoff = Date.now.addingTimeInterval(-WatchOutbox.patience)
		var applied = appliedActions().filter { $0.madeAt > cutoff }
		applied.append(Applied(id: action.id, madeAt: action.madeAt))
		UserDefaults.standard.set(try? JSONEncoder().encode(applied.suffix(400)), forKey: Keys.applied)
	}
}

// MARK: - Session

extension WatchSync: WCSessionDelegate {
	nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
	                         error: Error?) {
		let message = error?.localizedDescription
		Task { @MainActor in
			if let message { WatchSync.shared.log.error("Session activation failed: \(message, privacy: .public)") }
			WatchSync.shared.scheduleSend()
		}
	}

	nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

	/// Switched to another watch: start again with it.
	nonisolated func sessionDidDeactivate(_ session: WCSession) {
		WCSession.default.activate()
	}

	/// The watch app was installed or removed, or a watch paired.
	nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
		Task { @MainActor in WatchSync.shared.scheduleSend() }
	}

	nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
		guard let data = userInfo[WatchLink.actionKey] as? Data else { return }
		Task { @MainActor in WatchSync.shared.receive(data) }
	}

	/// An action sent live, ahead of its queued copy.
	nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
		guard let data = message[WatchLink.actionKey] as? Data else { return }
		Task { @MainActor in WatchSync.shared.receive(data) }
	}

	/// The watch asking for a snapshot while both apps are open. Answered with
	/// nothing when the library isn't here yet; the application context follows.
	nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
	                         replyHandler: @escaping ([String: Any]) -> Void) {
		guard message[WatchLink.refreshKey] != nil else { return replyHandler([:]) }
		let reply = UncheckedReply(send: replyHandler)
		Task { @MainActor in
			let data = WatchSync.shared.packedSnapshot()
			reply.send(data.map { [WatchLink.snapshotKey: $0] } ?? [:])
		}
	}
}

/// WatchConnectivity's reply handler, carried to the main actor. It may be
/// called from any thread.
private struct UncheckedReply: @unchecked Sendable {
	let send: ([String: Any]) -> Void
}

// MARK: - Applying an action

/// What each of the watch's actions does to the library, kept apart from the
/// session so it can be tested.
enum WatchActionApplier {
	static func apply(_ action: WatchAction, in context: ModelContext) {
		switch action.change {
		case .markWatched(let id, let tier):
			guard let episode = episode(id, in: context) else { return }
			HomeFeed.markWatched(episode, tier: tier)
		case .putBack(let id, let status, let tier):
			guard let episode = episode(id, in: context) else { return }
			episode.episodeTier = tier
			episode.mark(status)
		case .notInterested(let key):
			decide(key, .notInterested, at: action.madeAt, in: context)
		case .later(let key):
			decide(key, .later, at: action.madeAt, in: context)
		case .add:
			// Imported by WatchSync, which has to wait on TMDb.
			break
		}
	}

	static func isInLibrary(_ kind: MediaKind, _ tmdbID: Int, in context: ModelContext) -> Bool {
		let target: Int? = tmdbID
		switch kind {
		case .show:
			return ((try? context.fetchCount(FetchDescriptor<Show>(predicate: #Predicate { $0.tmdbID == target }))) ?? 0) > 0
		case .film:
			return ((try? context.fetchCount(FetchDescriptor<Film>(predicate: #Predicate { $0.tmdbID == target }))) ?? 0) > 0
		}
	}

	private static func episode(_ id: UUID, in context: ModelContext) -> Episode? {
		var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.id == id })
		descriptor.fetchLimit = 1
		return try? context.fetch(descriptor).first
	}

	/// As Discover records Not interested and Later: one decision per title, the
	/// latest kept.
	private static func decide(_ key: String, _ choice: SuggestionChoice, at date: Date, in context: ModelContext) {
		let descriptor = FetchDescriptor<SuggestionDecision>(predicate: #Predicate { $0.key == key })
		if let saved = try? context.fetch(descriptor).first {
			guard saved.decidedAt <= date else { return }
			saved.choice = choice
			saved.decidedAt = date
		} else {
			context.insert(SuggestionDecision(key: key, choice: choice, decidedAt: date))
		}
	}
}

// MARK: - Building the snapshot

/// The snapshot's pieces, worked out from the library.
enum WatchSnapshotBuilder {
	static func snapshot(shows: [Show], films: [Film], decisions: [SuggestionDecision], applied: Set<UUID>,
	                     upcoming: Int = WatchSync.upcomingCount, seeds seedLimit: Int = 200,
	                     now: Date = .now) -> PhoneSnapshot {
		var library = Set<String>()
		for show in shows { if let tmdbID = show.tmdbID { library.insert(MediaKind.show.key(tmdbID: tmdbID)) } }
		for film in films { if let tmdbID = film.tmdbID { library.insert(MediaKind.film.key(tmdbID: tmdbID)) } }
		var notInterested = Set<String>()
		var putOff: [String: Date] = [:]
		for decision in decisions {
			switch decision.choice {
			case .notInterested: notInterested.insert(decision.key)
			case .later:         putOff[decision.key] = decision.decidedAt
			}
		}
		let seeds = DiscoverFeed.seeds(shows: shows, films: films).prefix(seedLimit).map {
			DiscoverSeed(id: $0.id, kind: $0.kind, tmdbID: $0.tmdbID, title: $0.title)
		}
		return PhoneSnapshot(upNext: upNext(shows, upcoming: upcoming), seeds: Array(seeds), library: library,
		                     notInterested: notInterested, putOff: putOff, applied: applied, sentAt: now)
	}

	/// The shows Home's hero pages through, in the order given, each with its
	/// first `upcoming` episodes not yet watched.
	static func upNext(_ shows: [Show], upcoming limit: Int = WatchSync.upcomingCount) -> [UpNextShow] {
		HomeFeed.watching(shows).map { show in
			let unwatched = HomeFeed.runningOrder(of: show).filter { $0.status != .watched }
			return UpNextShow(id: show.id,
			                  title: show.title,
			                  artworkURL: show.backdropURL.isEmpty ? show.posterURL : show.backdropURL,
			                  upcoming: unwatched.prefix(limit).map { episode($0) },
			                  remaining: unwatched.count,
			                  episodeCount: show.episodeCount)
		}
	}

	static func episode(_ episode: Episode) -> UpNextEpisode {
		UpNextEpisode(id: episode.id,
		              seasonNumber: episode.seasonNumber,
		              episodeNumber: episode.episodeNumber,
		              title: episode.title,
		              runtimeMinutes: episode.runtimeMinutes ?? episode.specs?.runtimeMinutes,
		              status: episode.status,
		              tier: episode.episodeTier)
	}
}

// MARK: - Hooking it up

extension View {
	/// Hands WatchSync the library, and sends the watch a fresh snapshot each
	/// time the app comes to the front.
	func syncsWithWatch() -> some View {
		modifier(WatchSyncModifier())
	}
}

private struct WatchSyncModifier: ViewModifier {
	@Environment(\.modelContext) private var context
	@Environment(\.scenePhase) private var scenePhase

	func body(content: Content) -> some View {
		content
			.task { WatchSync.shared.attach(context) }
			.onChange(of: scenePhase) { _, phase in
				if phase == .active { WatchSync.shared.scheduleSend() }
			}
	}
}
