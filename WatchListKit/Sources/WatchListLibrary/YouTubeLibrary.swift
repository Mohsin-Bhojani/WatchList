//
//  YouTubeLibrary.swift
//  WatchList
//
//  A YouTube playlist's episodes put into the library (YouTube.swift reads
//  and matches them): each episode keeps the video it plays from, and gets
//  the video's thumbnail, upload day and length where it has none of its own.
//  Episodes the playlist has and the season doesn't — a drama still airing,
//  or one TMDb doesn't list — are added. Nothing else about an episode, its
//  title and whether it's watched included, is changed.
//

import Foundation
import SwiftData
import WatchListCore

public enum YouTubeLibrary {
	public struct Report: Equatable {
		public var linked = 0
		public var added = 0

		public init(linked: Int = 0, added: Int = 0) {
			self.linked = linked
			self.added = added
		}

		/// "24 episodes play from YouTube · 3 new".
		public var summary: String {
			let total = linked + added
			guard total > 0 else { return "No episodes found in that playlist." }
			let line = "\(total) episode\(total == 1 ? "" : "s") play\(total == 1 ? "s" : "") from YouTube"
			return added > 0 ? line + " · \(added) new" : line
		}
	}

	/// Puts matched videos — episode number to video — on `season`, adding the
	/// episodes it doesn't have. New episodes go into `context` when one is given.
	@discardableResult
	public static func apply(_ matches: [Int: YouTubeVideo], playlistID: String, to season: Season,
	                         context: ModelContext? = nil) -> Report {
		season.youtubePlaylistID = playlistID
		var report = Report()
		let existing = Dictionary(season.episodes.map { ($0.episodeNumber, $0) }, uniquingKeysWith: { first, _ in first })
		for (number, video) in matches.sorted(by: { $0.key < $1.key }) {
			let day = video.publishedAt.map { AirDate.day($0) } ?? ""
			if let episode = existing[number] {
				episode.youtubeVideoID = video.id
				if episode.stillURL.isEmpty { episode.stillURL = video.thumbnailURL }
				if episode.runtimeMinutes == nil { episode.runtimeMinutes = video.durationMinutes }
				if episode.airDate.isEmpty { episode.airDate = day }
				report.linked += 1
			} else {
				let episode = Episode(episodeNumber: number, seasonNumber: season.seasonNumber, title: "",
				                      stillURL: video.thumbnailURL, airDate: day,
				                      runtimeMinutes: video.durationMinutes, tmdbShowID: season.show?.tmdbID)
				episode.youtubeVideoID = video.id
				context?.insert(episode)
				season.episodes.append(episode)
				report.added += 1
			}
		}
		// New episodes reopen a season that was finished.
		if report.added > 0, season.status == .watched { season.status = .watching }
		return report
	}

	/// Takes the playlist off `season`; its episodes stay, without their videos.
	public static func unlink(_ season: Season) {
		season.youtubePlaylistID = nil
		for episode in season.episodes { episode.youtubeVideoID = nil }
	}

	/// A show made from a playlist, for a drama TMDb doesn't have: one season,
	/// named `name`, with the playlist's thumbnail as its artwork. Insert it,
	/// then `apply` the matches to its season.
	public static func makeShow(named name: String, from playlist: YouTubePlaylist) -> Show {
		let earliest = playlist.videos.compactMap(\.publishedAt).min()
		let show = Show(title: name,
		                overview: playlist.channel.isEmpty ? "" : "On YouTube, from \(playlist.channel).",
		                firstAirYear: earliest.map { String(Calendar.current.component(.year, from: $0)) } ?? "",
		                posterURL: playlist.thumbnailURL, backdropURL: playlist.thumbnailURL)
		let season = Season(seasonNumber: 1)
		season.show = show
		show.seasons.append(season)
		return show
	}

	/// Every season of `show` that plays from a playlist.
	public static func linkedSeasons(of show: Show) -> [Season] {
		show.sortedSeasons.filter { $0.youtubePlaylistID != nil }
	}
}
