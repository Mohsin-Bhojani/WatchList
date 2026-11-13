//
//  YouTubeLinker.swift
//  WatchList
//
//  Playlists put to work (YouTube.swift, YouTubeLibrary.swift): linking one
//  to a season, making a show from one, and looking a linked playlist over
//  again for episodes uploaded since — at most every few hours, when the
//  show's page opens.
//

import Foundation
import SwiftData
import WatchListCore
import WatchListLibrary

@MainActor
enum YouTubeLinker {
	/// How long a playlist goes between checks for new uploads.
	static let recheckAfter: TimeInterval = 6 * 3600

	@discardableResult
	static func link(_ playlist: YouTubePlaylist, to season: Season, context: ModelContext) -> YouTubeLibrary.Report {
		let report = YouTubeLibrary.apply(YouTubeEpisodes.match(playlist.videos), playlistID: playlist.id,
		                                  to: season, context: context)
		markChecked(playlist.id)
		return report
	}

	/// A new show from `playlist`, named `name`, in the library.
	@discardableResult
	static func addShow(named name: String, from playlist: YouTubePlaylist, context: ModelContext) -> Show {
		let show = YouTubeLibrary.makeShow(named: name, from: playlist)
		context.insert(show)
		if let season = show.seasons.first { link(playlist, to: season, context: context) }
		return show
	}

	/// Looks the show's linked playlists over for new uploads, when it's been
	/// a while. Failures are quiet: the episodes already linked still play.
	static func refreshIfDue(_ show: Show, context: ModelContext, now: Date = .now) async {
		guard YouTubeConfig.isConfigured else { return }
		for season in YouTubeLibrary.linkedSeasons(of: show) {
			guard let id = season.youtubePlaylistID, isDue(id, now: now),
			      let playlist = try? await YouTubeService.shared.playlist(id: id) else { continue }
			link(playlist, to: season, context: context)
		}
	}

	private static func key(_ id: String) -> String { "youtube.checked.\(id)" }

	private static func isDue(_ id: String, now: Date) -> Bool {
		let last = UserDefaults.standard.double(forKey: key(id))
		return now.timeIntervalSince1970 - last > recheckAfter
	}

	private static func markChecked(_ id: String) {
		UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: key(id))
	}
}
