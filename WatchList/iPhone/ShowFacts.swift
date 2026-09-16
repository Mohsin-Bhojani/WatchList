//
//  ShowFacts.swift
//  WatchList
//
//  The short lines the iPhone show, season and episode pages are made of —
//  "S2 E3", "6 of 13 episodes watched", "In your list · not started" — kept
//  apart from the views so they can be tested.
//

import Foundation

enum ShowFacts {
	/// "S2 E3", or "Special 2" for season 0.
	static func code(season: Int, episode: Int) -> String {
		season == 0 ? "Special \(episode)" : "S\(season) E\(episode)"
	}

	static func code(_ episode: Episode) -> String {
		code(season: episode.seasonNumber, episode: episode.episodeNumber)
	}

	/// "1 season", "4 seasons".
	static func seasons(_ count: Int) -> String {
		"\(count) \(count == 1 ? "season" : "seasons")"
	}

	/// "1 episode", "13 episodes".
	static func episodes(_ count: Int) -> String {
		"\(count) \(count == 1 ? "episode" : "episodes")"
	}

	/// "6 of 13 episodes watched".
	static func progressLine(watched: Int, total: Int) -> String {
		"\(watched) of \(episodes(total)) watched"
	}

	/// How far through `total` episodes, 0 to 1.
	static func fraction(watched: Int, total: Int) -> Double {
		total > 0 ? min(Double(watched) / Double(total), 1) : 0
	}

	/// The episode after the one most recently marked Watched — by the date it
	/// was marked, or, without dates, the last Watched in running order. The
	/// first episode when none is Watched yet; nil once the last one is.
	/// `ordered` is the show's episodes in running order.
	static func nextAfterLastWatched(_ ordered: [Episode]) -> Episode? {
		let watched = ordered.indices.filter { ordered[$0].status == .watched }
		guard let last = watched.max(by: { lhs, rhs in
			switch (ordered[lhs].watchedAt, ordered[rhs].watchedAt) {
			case let (left?, right?) where left != right: return left < right
			case (nil, .some): return true
			case (.some, nil): return false
			default: return lhs < rhs
			}
		}) else { return ordered.first }
		return last + 1 < ordered.count ? ordered[last + 1] : nil
	}

	/// The line under the title in the compact bar: where the show stands.
	static func listLine(status: WatchStatus, watched: Int, total: Int, nextCode: String?) -> String {
		switch status {
		case .toWatch:
			return watched == 0 ? "In your list · not started" : "In your list · \(watched) of \(total) watched"
		case .watching:
			return nextCode.map { "Watching · \($0)" } ?? "Watching"
		case .watched:
			return "Finished"
		}
	}
}
