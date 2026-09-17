//
//  BrowseKind.swift
//  WatchList
//
//  TV shows, films or both — what a list or Discover's filter narrows to — and
//  the genre names a set of titles offers. Compiled into both the iPhone app and
//  the watch app; the Shows tab's status, sorts and matching stay with the
//  iPhone, in WatchList/iPhone/BrowseFilter.swift.
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

	/// A comma-separated genre list's names, trimmed.
	nonisolated static func tokens(of genreList: String) -> [String] {
		genreList
			.split(separator: ",")
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
	}
}
