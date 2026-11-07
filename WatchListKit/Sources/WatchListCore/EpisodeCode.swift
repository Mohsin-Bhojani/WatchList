//
//  EpisodeCode.swift
//  WatchListCore
//
//  How an episode is named by its numbers, the same on the iPhone, the watch
//  and the widget. Season 0 is specials.
//

import Foundation

public enum EpisodeCode {
	/// "S2 E3", or "Special 2" for season 0.
	public static func short(season: Int, episode: Int) -> String {
		season == 0 ? "Special \(episode)" : "S\(season) E\(episode)"
	}

	/// "Season 2 · Episode 8", or "Specials · Episode 1" for season 0.
	public static func long(season: Int, episode: Int) -> String {
		"\(season == 0 ? "Specials" : "Season \(season)") · Episode \(episode)"
	}
}
