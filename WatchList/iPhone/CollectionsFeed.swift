//
//  CollectionsFeed.swift
//  WatchList
//
//  What the iPhone Collections tab shows, worked out from the library: one
//  collection per verdict, the titles in each of your own collections
//  (TitleCollection), and the short lines their cards and rows use.
//

import Foundation

/// A by-verdict collection: every show and film given that verdict.
struct VerdictCollection: Identifiable {
	let rating: Rating
	let items: [WatchedTitle]

	var id: Rating { rating }
}

enum CollectionsFeed {
	/// Perfection, Go For It, Timepass and Skip, each holding every show and film
	/// with that verdict whatever its status — the most stars first, then the
	/// newest added.
	static func byVerdict(shows: [Show], films: [Film]) -> [VerdictCollection] {
		let titles = shows.map(WatchedTitle.show) + films.map(WatchedTitle.film)
		return Rating.allCases.map { rating in
			let items = titles
				.filter { $0.rating == rating }
				.sorted { lhs, rhs in
					let left = lhs.stars ?? 0
					let right = rhs.stars ?? 0
					return left != right ? left > right : lhs.dateAdded > rhs.dateAdded
				}
			return VerdictCollection(rating: rating, items: items)
		}
	}

	/// The orders the Collections tab can put your own collections in, each
	/// either way round.
	enum Sort: ListSort {
		case created, name, size

		/// Oldest first, so a new collection lands at the end.
		static let standard = Sort.created

		var id: Self { self }

		var title: String {
			switch self {
			case .created: return "Created"
			case .name:    return "A–Z"
			case .size:    return "Size"
			}
		}

		var reversedTitle: String? { self == .name ? "Z–A" : nil }

		/// Size runs biggest first; created runs from the oldest.
		var runsHighToLow: Bool { self == .size }

		func summary(reversed: Bool) -> String {
			switch self {
			case .created: return reversed ? "Newest first" : "Oldest first"
			case .name:    return reversed ? "Z–A" : "A–Z"
			case .size:    return reversed ? "Smallest first" : "Biggest first"
			}
		}
	}

	/// Your collections in `order`, where `count` is how many titles one holds.
	/// In a tie the one made first leads.
	static func sorted(_ collections: [TitleCollection], by order: ListOrder<Sort>,
	                   count: (TitleCollection) -> Int) -> [TitleCollection] {
		collections.sorted { lhs, rhs in
			switch order.sort {
			case .created:
				if lhs.created != rhs.created { return (lhs.created < rhs.created) != order.reversed }
			case .name:
				let comparison = lhs.name.localizedStandardCompare(rhs.name)
				if comparison != .orderedSame { return (comparison == .orderedAscending) != order.reversed }
			case .size:
				let left = count(lhs), right = count(rhs)
				if left != right { return (left > right) != order.reversed }
			}
			if lhs.created != rhs.created { return lhs.created < rhs.created }
			return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
		}
	}

	/// One of your collections' titles in the order they were added, skipping
	/// any no longer in the library.
	static func items(in collection: TitleCollection?, shows: [Show], films: [Film]) -> [WatchedTitle] {
		guard let collection else { return [] }
		var byID: [UUID: WatchedTitle] = [:]
		for show in shows { byID[show.id] = .show(show) }
		for film in films { byID[film.id] = .film(film) }
		return collection.titleIDs.compactMap { byID[$0] }
	}

	/// All Time Best, once the library has it.
	static func pinned(_ collections: [TitleCollection]) -> TitleCollection? {
		collections.first { $0.isPinned }
	}

	/// The collections you made yourself: all but the pinned one.
	static func yours(_ collections: [TitleCollection]) -> [TitleCollection] {
		collections.filter { !$0.isPinned }
	}

	/// "31 titles", "1 title", or "Nothing yet".
	static func countLabel(_ count: Int) -> String {
		switch count {
		case 0:  return "Nothing yet"
		case 1:  return "1 title"
		default: return "\(count) titles"
		}
	}

	/// A row's kind line: "TV Show · 64 episodes", "TV Show · 2 seasons" before
	/// any episodes are tracked, or "Film".
	static func kindLine(isShow: Bool, episodes: Int, seasons: Int) -> String {
		guard isShow else { return "Film" }
		if episodes > 0 { return "TV Show · \(ShowFacts.episodes(episodes))" }
		if seasons > 0 { return "TV Show · \(ShowFacts.seasons(seasons))" }
		return "TV Show"
	}

	static func kindLine(_ item: WatchedTitle) -> String {
		switch item {
		case .show(let show):
			return kindLine(isShow: true, episodes: show.episodeCount, seasons: show.seasons.count)
		case .film:
			return kindLine(isShow: false, episodes: 0, seasons: 0)
		}
	}
}
