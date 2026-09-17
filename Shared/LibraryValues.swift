//
//  LibraryValues.swift
//  WatchList
//
//  The library's plain values, compiled into both the iPhone app and the watch
//  app: a title's kind, a watch status, a verdict, and an episode's rating. The SwiftData
//  models that store them stay on the iPhone, in WatchList/Models.swift.
//
//  The store's schema is built from their names and raw values, so neither may
//  change.
//

import Foundation

enum MediaKind: String, Codable, CaseIterable, Identifiable {
	case show = "Show"
	case film = "Film"
	var id: String { rawValue }
	var systemImage: String { self == .show ? "tv" : "film" }
}

enum WatchStatus: String, Codable, CaseIterable, Identifiable {
	case toWatch = "To Watch"
	case watching = "Watching"
	case watched = "Watched"

	var id: String { rawValue }

	var systemImage: String {
		switch self {
		case .toWatch:  return "bookmark"
		case .watching: return "play.circle.fill"
		case .watched:  return "checkmark.circle.fill"
		}
	}

	/// Cycle helper used by quick-tap status toggles.
	var next: WatchStatus {
		switch self {
		case .toWatch:  return .watching
		case .watching: return .watched
		case .watched:  return .toWatch
		}
	}

	/// Natural workflow order (to watch -> watching -> watched), for sorting.
	var sortRank: Int {
		switch self {
		case .toWatch:  return 0
		case .watching: return 1
		case .watched:  return 2
		}
	}
}

/// A personal verdict, set independently on shows, seasons, episodes and films.
/// Optional on every model: `nil` means "not rated yet".
enum Rating: String, Codable, CaseIterable, Identifiable {
	case perfection = "Perfection"
	case goForIt = "Go For It"
	case timepass = "Timepass"
	case skip = "Skip"

	var id: String { rawValue }

	var systemImage: String {
		switch self {
		case .perfection: return "crown.fill"
		case .goForIt:    return "hand.thumbsup.fill"
		case .timepass:   return "clock.fill"
		case .skip:       return "hand.thumbsdown.fill"
		}
	}

	/// Best -> worst, for sorting.
	var sortRank: Int {
		switch self {
		case .perfection: return 0
		case .goForIt:    return 1
		case .timepass:   return 2
		case .skip:       return 3
		}
	}
}

/// A rewatch-value rating for individual episodes (distinct from the show/film
/// verdict). The label says what to do with the episode on a rewatch: skip the
/// filler, watch it normally, or rewatch a standout on its own.
enum EpisodeTier: String, Codable, CaseIterable, Identifiable {
	case skip = "Skip"
	case watch = "Watch"
	case rewatch = "Rewatch"

	var id: String { rawValue }

	var systemImage: String {
		switch self {
		case .skip:    return "forward.fill"
		case .watch:   return "play.fill"
		case .rewatch: return "arrow.2.squarepath"
		}
	}

	/// Best -> worst, for sorting.
	var sortRank: Int {
		switch self {
		case .rewatch: return 0
		case .watch:   return 1
		case .skip:    return 2
		}
	}
}

extension MediaKind {
	/// "Show-1399": the kind and TMDb id together, which is how a title is keyed
	/// wherever TMDb titles are — TMDb numbers films and shows separately, so the
	/// same id can be both.
	func key(tmdbID: Int) -> String { "\(rawValue)-\(tmdbID)" }
}
