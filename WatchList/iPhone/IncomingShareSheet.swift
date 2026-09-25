//
//  IncomingShareSheet.swift
//  WatchList
//
//  What opens when someone's share arrives (FriendShare): a watchlist:// link
//  for one title, or a .watchlist file for a collection. It shows what they
//  sent and what they thought of it — their verdict, stars and note, as
//  theirs — and offers to add it:
//    - a title goes into your library as To Watch, or is marked as already
//      there
//    - a collection becomes one of your own collections, adding any titles
//      you don't have yet, in the sender's order
//  Only ever adds; nothing already in your library changes.
//

import SwiftUI
import SwiftData

struct IncomingShareSheet: View {
	let share: IncomingShare

	@Environment(\.dismiss) private var dismiss
	@Environment(\.modelContext) private var ctx
	@Query private var shows: [Show]
	@Query private var films: [Film]
	@Query(sort: \TitleCollection.created) private var collections: [TitleCollection]
	@StateObject private var importer = ImportCoordinator()

	@State private var working = false
	@State private var result: String?

	private var ground: PageGround { .accent }

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 16) {
					switch share {
					case .title(let title, let from):
						senderLine(from, sent: "a \(title.kind == .film ? "film" : "show")")
						titleCard(title, from: from)
					case .collection(let collection):
						senderLine(collection.from, sent: "the collection \u{201C}\(collection.name)\u{201D}")
						ForEach(collection.titles) { titleCard($0, from: collection.from) }
					}
					if let result {
						Text(result)
							.font(.system(size: 14, weight: .medium))
							.foregroundStyle(.white.opacity(0.85))
							.fixedSize(horizontal: false, vertical: true)
					}
				}
				.foregroundStyle(.white)
				.padding(16)
				.padding(.bottom, 90)
				.readableColumn()
			}
			.background(ground.gradient.ignoresSafeArea())
			.safeAreaInset(edge: .bottom) { addButton.padding(16) }
			.navigationTitle("Shared with you")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .principal) {
					Text("Shared with you")
						.font(.system(size: 17, weight: .semibold))
						.foregroundStyle(.white)
				}
				.sharedBackgroundVisibility(.hidden)
				ToolbarItem(placement: .cancellationAction) {
					Button("Close", systemImage: "xmark") { dismiss() }
				}
			}
		}
		.tint(.white)
		.preferredColorScheme(.dark)
		.presentationBackground(ground.gradient)
	}

	// MARK: Pieces

	private func senderLine(_ from: String?, sent what: String) -> some View {
		Text("\(from ?? "Someone") sent you \(what).")
			.font(.system(size: 15, weight: .semibold))
			.foregroundStyle(.white.opacity(0.85))
	}

	private func titleCard(_ title: SharedTitle, from: String?) -> some View {
		let owned = libraryID(for: title) != nil
		return VStack(alignment: .leading, spacing: 8) {
			HStack(alignment: .firstTextBaseline) {
				VStack(alignment: .leading, spacing: 2) {
					Text(title.title)
						.font(.system(size: 18, weight: .bold))
					Text([title.kind == .film ? "Film" : "Show", title.year].filter { !$0.isEmpty }
						.joined(separator: " · "))
						.font(.system(size: 12, weight: .medium))
						.foregroundStyle(.white.opacity(0.6))
				}
				Spacer()
				if owned {
					Label("In your library", systemImage: "checkmark")
						.font(.system(size: 12, weight: .semibold))
						.foregroundStyle(.white.opacity(0.75))
				}
			}
			if title.verdict != nil || title.stars != nil {
				HStack(spacing: 8) {
					Text("\(from ?? "They") said")
						.font(.system(size: 12, weight: .medium))
						.foregroundStyle(.white.opacity(0.6))
					VerdictChip(rating: title.verdict.flatMap(Rating.init(rawValue:)))
					if let stars = title.stars { StarsLabel(value: stars) }
				}
			}
			if let note = title.note {
				Text("\u{201C}\(note)\u{201D}")
					.font(.system(size: 14))
					.foregroundStyle(.white.opacity(0.9))
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(14)
		.liquidCard(cornerRadius: 20)
		.accessibilityElement(children: .combine)
	}

	@ViewBuilder private var addButton: some View {
		let (label, enabled) = addLabel
		Button {
			Task { await add() }
		} label: {
			HStack(spacing: 8) {
				if working { ProgressView().tint(Color(uiColor: ArtworkBand.deeper(ground.base))) }
				Text(label)
			}
			.font(.system(size: 16, weight: .semibold))
			// The page's deep shade on the white button, which the sheet's white tint
			// makes it; plain white once it's greyed out.
			.foregroundStyle(enabled && !working ? Color(uiColor: ArtworkBand.deeper(ground.base))
			                                     : .white.opacity(0.75))
			.frame(maxWidth: .infinity)
			.frame(height: 50)
		}
		.buttonStyle(.glassProminent)
		.disabled(!enabled || working)
	}

	private var addLabel: (String, Bool) {
		switch share {
		case .title(let title, _):
			if libraryID(for: title) != nil { return ("Already in your library", false) }
			return title.canBeAdded ? ("Add to library", true) : ("Can't be added: not on TMDb", false)
		case .collection:
			return result == nil ? ("Add as a collection", true) : ("Added", false)
		}
	}

	// MARK: Adding

	/// The title's id in your library, matched by TMDb id, else IMDb id.
	private func libraryID(for title: SharedTitle) -> UUID? {
		switch title.kind {
		case .film:
			return films.first { f in
				(title.tmdbID != nil && f.tmdbID == title.tmdbID) || (title.imdbID != nil && f.imdbID == title.imdbID)
			}?.id
		case .show:
			return shows.first { s in
				(title.tmdbID != nil && s.tmdbID == title.tmdbID) || (title.imdbID != nil && s.imdbID == title.imdbID)
			}?.id
		}
	}

	/// Adds it from TMDb, the way Search does, and gives back its library id.
	private func importTitle(_ title: SharedTitle) async -> UUID? {
		if let existing = libraryID(for: title) { return existing }
		let added: Any?
		if let tmdbID = title.tmdbID {
			added = await importer.importFromTMDb(id: tmdbID, kind: title.kind, into: ctx)
		} else if let imdbID = title.imdbID {
			added = await importer.importFromIMDb(imdbID, into: ctx)
		} else {
			return nil
		}
		return (added as? Film)?.id ?? (added as? Show)?.id
	}

	private func add() async {
		working = true
		defer { working = false }
		switch share {
		case .title(let title, _):
			if await importTitle(title) != nil {
				Haptics.success()
				dismiss()
			} else {
				result = "Couldn't add \u{201C}\(title.title)\u{201D}. Check your connection and try again."
			}
		case .collection(let shared):
			var ids: [UUID] = []
			var missed = 0
			for title in shared.titles {
				if let id = await importTitle(title) { ids.append(id) } else { missed += 1 }
			}
			guard let collection = ctx.makeCollection(named: uniqueName(for: shared)) else { return }
			collection.titleIDs = ids
			Haptics.success()
			result = "Added \u{201C}\(collection.name)\u{201D} to your collections with \(ids.count) "
				+ "title\(ids.count == 1 ? "" : "s")."
				+ (missed > 0 ? " \(missed) couldn't be added." : "")
		}
	}

	/// The sender's name for it, or "… from Sam" when you already have one called that.
	private func uniqueName(for shared: SharedCollection) -> String {
		let names = Set(collections.map { $0.name.lowercased() })
		var name = shared.name
		if names.contains(name.lowercased()) { name += " from \(shared.from ?? "a friend")" }
		var candidate = name
		var number = 2
		while names.contains(candidate.lowercased()) {
			candidate = "\(name) \(number)"
			number += 1
		}
		return candidate
	}
}
