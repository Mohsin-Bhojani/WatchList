//
//  TitlePageActions.swift
//  WatchList
//
//  What the title pages' menus share: the status and verdict sections,
//  links out, sharing and removing a record. Split out of TitlePageKit.swift.
//

import SwiftUI
import SwiftData
import WatchListCore
import WatchListLibrary

// MARK: - Menus

/// A status menu's Status section: a tick against the current status. Choosing
/// the ticked one again does nothing — a title always has a status.
struct StatusMenuSection: View {
	let current: WatchStatus
	var statuses: [WatchStatus] = WatchStatus.allCases
	let choose: (WatchStatus) -> Void

	var body: some View {
		Section("Status") {
			ForEach(statuses) { status in
				Toggle(status.rawValue, isOn: Binding(get: { current == status }, set: { if $0 { choose(status) } }))
			}
		}
	}
}

/// A status menu's Rate section: a tick against the verdict; choosing the
/// ticked one again clears it. Toggles — not an inline picker — because a menu
/// drops a section's heading when an inline picker fills it.
struct VerdictMenuSection<Item: Rated>: View {
	let item: Item

	var body: some View {
		Section("Rate") {
			ForEach(Rating.allCases) { rating in
				Toggle(rating.rawValue, isOn: Binding(get: { item.rating == rating }, set: { isOn in
					Haptics.selection()
					withAnimation(Glass.smooth) { item.setVerdict(isOn ? rating : nil) }
				}))
			}
		}
	}
}

// MARK: - Quick actions

extension View {
	/// A long press on a title anywhere in a list: its status and, once
	/// Watched, its verdict — the same sections its page's menu has.
	func titleQuickActions(_ item: WatchedTitle) -> some View {
		contextMenu {
			switch item {
			case .show(let show):
				StatusMenuSection(current: show.status) { status in
					withAnimation(Glass.smooth) { show.mark(status) }
				}
				if show.status == .watched { VerdictMenuSection(item: show) }
			case .film(let film):
				StatusMenuSection(current: film.status, statuses: [.toWatch, .watched]) { status in
					withAnimation(Glass.smooth) { film.mark(status) }
				}
				if film.status == .watched { VerdictMenuSection(item: film) }
			}
		}
	}

	/// In a List: swipe right to mark a title Watched, or back to To Watch.
	func titleSwipeActions(_ item: WatchedTitle) -> some View {
		swipeActions(edge: .leading) {
			let watched = item.status == .watched
			Button {
				withAnimation(Glass.smooth) {
					switch item {
					case .show(let show): show.mark(watched ? .toWatch : .watched)
					case .film(let film): film.mark(watched ? .toWatch : .watched)
					}
				}
			} label: {
				Label(watched ? "To Watch" : "Watched",
				      systemImage: watched ? WatchStatus.toWatch.systemImage : WatchStatus.watched.systemImage)
			}
			.tint(watched ? Glass.toWatch : Glass.watched)
		}
	}
}

// MARK: - Sharing and artwork

enum TitleLinks {
	static func tmdbMovie(_ id: Int?) -> URL? {
		id.flatMap { URL(string: "https://www.themoviedb.org/movie/\($0)") }
	}

	static func tmdbTV(_ id: Int?, season: Int? = nil, episode: Int? = nil) -> URL? {
		guard let id else { return nil }
		var path = "https://www.themoviedb.org/tv/\(id)"
		if let season { path += "/season/\(season)" }
		if let season, let episode, season >= 0 { path += "/episode/\(episode)" }
		return URL(string: path)
	}
}

/// Shares the first link there is — IMDb's before TMDb's — or just the name.
struct TitleShareLink<Label: View>: View {
	let title: String
	let links: [URL?]
	@ViewBuilder let label: () -> Label

	var body: some View {
		if let url = links.lazy.compactMap({ $0 }).first {
			ShareLink(item: url, subject: Text(title), label: label)
		} else {
			ShareLink(item: title, label: label)
		}
	}
}

// MARK: - Removing

extension ModelContext {
	/// Leaves the page before deleting, so nothing still on screen reads a
	/// record that's gone.
	func delete<Model: PersistentModel>(_ model: Model, afterLeaving dismiss: DismissAction) {
		dismiss()
		Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(450))
			self.delete(model)
		}
	}
}
