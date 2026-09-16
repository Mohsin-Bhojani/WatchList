//
//  BrowseFilter.swift
//  WatchList
//
//  The Shows tab's Filter & Sort — what it lists, which status and genres, and
//  in what order — and how titles are tested and ordered against them. The
//  sort-either-way pieces, ListSort and ListOrder, are shared with the
//  Collections tab.
//

import Foundation

/// What the Shows tab lists: TV shows and films together, or one kind.
enum BrowseKind: CaseIterable, Identifiable {
	case all, shows, films

	var id: Self { self }

	/// The tab header's name while it's chosen.
	var title: String {
		switch self {
		case .all:   return "Shows"
		case .shows: return "TV Shows"
		case .films: return "Films"
		}
	}

	/// Its segment in Filter & Sort.
	var label: String { self == .all ? "All" : title }

	var systemImage: String {
		switch self {
		case .all:   return "popcorn"
		case .shows: return "tv"
		case .films: return "film"
		}
	}

	var includesShows: Bool { self != .films }
	var includesFilms: Bool { self != .shows }

	func includes(_ kind: MediaKind) -> Bool { kind == .show ? includesShows : includesFilms }
}

/// The status segments, in the order they're shown.
enum StatusFilter: CaseIterable, Identifiable {
	case all, watching, toWatch, watched

	var id: Self { self }

	/// The status the segment keeps, or nil for All.
	var status: WatchStatus? {
		switch self {
		case .all:      return nil
		case .watching: return .watching
		case .toWatch:  return .toWatch
		case .watched:  return .watched
		}
	}

	var title: String { status?.rawValue ?? "All" }
	var systemImage: String? { status?.systemImage }
}

/// A list's sorts, for ListOrder and the sort segments.
protocol ListSort: CaseIterable, Hashable, Identifiable where AllCases == [Self] {
	/// The sort a list starts with.
	static var standard: Self { get }
	var title: String { get }
	/// The chosen segment's name reversed, for a sort whose name says which way
	/// it runs: A–Z becomes Z–A. The others show an arrow instead.
	var reversedTitle: String? { get }
	/// Whether it usually runs from the most to the least: newest, latest,
	/// highest or biggest first.
	var runsHighToLow: Bool { get }
	/// Which way it runs, in words.
	func summary(reversed: Bool) -> String
}

/// A sort and which way it runs. Each sort starts the way it usually runs, and
/// reversed runs the other way.
struct ListOrder<Sort: ListSort>: Equatable {
	var sort: Sort = .standard
	var reversed = false

	/// Picking a sort: a different one starts its usual way; picking the one
	/// already chosen reverses it.
	mutating func choose(_ picked: Sort) {
		if picked == sort {
			reversed.toggle()
		} else {
			sort = picked
			reversed = false
		}
	}

	/// A sort's segment name, reversed while it's chosen where its name says
	/// the direction.
	func segmentTitle(for option: Sort) -> String {
		if option == sort, reversed, let flipped = option.reversedTitle { return flipped }
		return option.title
	}

	/// The arrow on the chosen segment: down while it runs from the most to the
	/// least, up the other way. None for a sort whose name already says.
	var arrowSymbol: String? {
		guard sort.reversedTitle == nil else { return nil }
		return sort.runsHighToLow != reversed ? "arrow.down" : "arrow.up"
	}

	/// Which way the list runs, in words.
	var summary: String { sort.summary(reversed: reversed) }
}

/// The orders the Shows tab can list in.
enum BrowseSort: ListSort {
	case added, title, year, rating

	static let standard = BrowseSort.added

	var id: Self { self }

	var title: String {
		switch self {
		case .added:  return "Added"
		case .title:  return "A–Z"
		case .year:   return "Year"
		case .rating: return "Rating"
		}
	}

	var reversedTitle: String? { self == .title ? "Z–A" : nil }

	/// Newest added, latest year and highest rated first; A–Z from the start.
	var runsHighToLow: Bool { self != .title }

	func summary(reversed: Bool) -> String {
		switch self {
		case .added:  return reversed ? "Oldest added first" : "Newest added first"
		case .title:  return reversed ? "Z–A" : "A–Z"
		case .year:   return reversed ? "Oldest year first" : "Latest year first"
		case .rating: return reversed ? "Lowest rated first" : "Highest rated first"
		}
	}
}

/// The Shows tab's order.
typealias BrowseOrder = ListOrder<BrowseSort>

enum BrowseFilter {
	/// Every genre across these titles' comma-separated genre lists, once each
	/// and A–Z. "Action, Drama" counts as both.
	static func genres(in genreLists: [String]) -> [String] {
		var seen = Set<String>()
		var result: [String] = []
		// Case-insensitive, keeping the first spelling met.
		for genre in genreLists.flatMap(tokens(of:)) where seen.insert(genre.lowercased()).inserted {
			result.append(genre)
		}
		return result.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
	}

	/// Whether a title passes the status and the genres. With genres picked it
	/// needs at least one of them, as one of its own genres rather than a word
	/// inside one: "Action" doesn't pick up "Action & Adventure".
	static func matches(status: WatchStatus, genres genreList: String,
	                    statusFilter: StatusFilter, picked: Set<String>) -> Bool {
		if let wanted = statusFilter.status, wanted != status { return false }
		guard !picked.isEmpty else { return true }
		return tokens(of: genreList).contains { genre in
			picked.contains { $0.caseInsensitiveCompare(genre) == .orderedSame }
		}
	}

	/// Titles in `order`. A title with no year or no rating goes after those
	/// with one, whichever way the list runs; ties go to the newest added, then
	/// A–Z.
	static func sorted(_ items: [WatchedTitle], by order: BrowseOrder) -> [WatchedTitle] {
		items.sorted { lhs, rhs in
			switch order.sort {
			case .added:
				if lhs.dateAdded != rhs.dateAdded { return (lhs.dateAdded > rhs.dateAdded) != order.reversed }
			case .title:
				let comparison = lhs.title.localizedStandardCompare(rhs.title)
				if comparison != .orderedSame { return (comparison == .orderedAscending) != order.reversed }
			case .year:
				if let decided = highestFirst(lhs.year, rhs.year, reversed: order.reversed) { return decided }
			case .rating:
				if let decided = highestFirst(lhs.stars, rhs.stars, reversed: order.reversed) { return decided }
			}
			if lhs.dateAdded != rhs.dateAdded { return lhs.dateAdded > rhs.dateAdded }
			return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
		}
	}

	/// Two values highest first — lowest first reversed — with a missing one
	/// last either way; nil when they tie.
	private static func highestFirst<Value: Comparable>(_ lhs: Value?, _ rhs: Value?, reversed: Bool) -> Bool? {
		switch (lhs, rhs) {
		case let (left?, right?): return left == right ? nil : (left > right) != reversed
		case (.some, nil):        return true
		case (nil, .some):        return false
		case (nil, nil):          return nil
		}
	}

	private static func tokens(of genreList: String) -> [String] {
		genreList
			.split(separator: ",")
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
	}
}
