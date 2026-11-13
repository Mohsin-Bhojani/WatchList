//
//  YouTubeTests.swift
//  WatchListTests
//
//  YouTube playlists as episodes: links read, titles numbered, teasers left
//  out, lengths read, and matches put on a season.
//

import Foundation
import Testing
@testable import WatchList
@testable import WatchListCore
@testable import WatchListLibrary

@MainActor
struct YouTubeTests {

	private let id = "PLs1hBl4H3BgUjVAP4bD4lN7YpjXBtZ2xs"

	private func video(_ title: String, day: Int, minutes: Int? = 38) -> YouTubeVideo {
		YouTubeVideo(id: "v\(day)", title: title, position: day,
		             publishedAt: Date(timeIntervalSince1970: 1_780_000_000 + Double(day) * 86_400),
		             thumbnailURL: "https://i.ytimg.com/vi/v\(day)/mqdefault.jpg", durationMinutes: minutes)
	}

	@Test func playlistLinksAreRead() {
		#expect(YouTubePlaylistLink.id(from: "https://www.youtube.com/playlist?list=\(id)") == id)
		#expect(YouTubePlaylistLink.id(from: "https://m.youtube.com/watch?v=abc123&list=\(id)&index=4") == id)
		#expect(YouTubePlaylistLink.id(from: "youtu.be/abc123?list=\(id)") == id)
		#expect(YouTubePlaylistLink.id(from: "  \(id)  ") == id)
		#expect(YouTubePlaylistLink.id(from: "https://www.youtube.com/watch?v=abc123") == nil)
		#expect(YouTubePlaylistLink.id(from: "https://example.com/playlist?list=\(id)") == nil)
		#expect(YouTubePlaylistLink.id(from: "hello") == nil)
	}

	@Test func episodeNumbersAreReadFromTitles() {
		#expect(YouTubeEpisodes.number(in: "Kabhi Main Kabhi Tum Episode 12 - [Eng Sub] - 24th July 2024") == 12)
		#expect(YouTubeEpisodes.number(in: "Mann Mast Malang Ep 07 | HUM TV") == 7)
		#expect(YouTubeEpisodes.number(in: "Jaan Nisar EP.45") == 45)
		#expect(YouTubeEpisodes.number(in: "Episode #3 - Tere Bin") == 3)
		#expect(YouTubeEpisodes.number(in: "جان نثار قسط ۱۲") == 12)
		#expect(YouTubeEpisodes.number(in: "Tere Bin - Last Episode") == nil)
	}

	@Test func teasersPromosAndClipsAreLeftOut() {
		#expect(YouTubeEpisodes.isExtra("Episode 13 Teaser | Kabhi Main Kabhi Tum"))
		#expect(YouTubeEpisodes.isExtra("Kabhi Main Kabhi Tum OST | Shafqat Amanat Ali"))
		#expect(YouTubeEpisodes.isExtra("Best Scene 02 | Episode 12"))
		#expect(YouTubeEpisodes.isExtra("Episode 12 Promo"))
		#expect(!YouTubeEpisodes.isExtra("Kabhi Main Kabhi Tum Episode 12 - Hania Aamir - ARY Digital"))
		#expect(!YouTubeEpisodes.isExtra("Ghost Story Episode 2"))
		#expect(!YouTubeEpisodes.isExtra("No Doubts Episode 4"))
	}

	@Test func numberedTitlesDecideWhichVideoIsWhichEpisode() {
		let matches = YouTubeEpisodes.match([
			video("Drama Episode 2", day: 2),
			video("Drama Episode 1", day: 1),
			video("Drama Episode 2 Teaser", day: 0),
			video("Drama Episode 3 Part 1", day: 3),
			video("Drama Episode 3 Part 2", day: 4),
			video("Drama Last Episode", day: 5),
		])
		#expect(matches.keys.sorted() == [1, 2, 3, 4])
		#expect(matches[1]?.id == "v1")
		#expect(matches[3]?.id == "v3")   // the earlier upload keeps the number
		#expect(matches[4]?.id == "v5")   // the unnumbered finale follows the highest
	}

	@Test func unnumberedPlaylistsGoByUploadOrder() {
		let matches = YouTubeEpisodes.match([
			video("The wedding", day: 9),
			video("The beginning", day: 3),
			video("The return", day: 6),
		])
		#expect(matches.mapValues(\.id) == [1: "v3", 2: "v6", 3: "v9"])
	}

	@Test func lengthsAreReadInMinutes() {
		#expect(YouTubeService.minutes("PT42M10S") == 42)
		#expect(YouTubeService.minutes("PT1H5M40S") == 66)
		#expect(YouTubeService.minutes("PT30S") == 1)
		#expect(YouTubeService.minutes("P0D") == nil)
	}

	@Test func showNamesComeFromPlaylistNames() {
		#expect(YouTubeEpisodes.showName(fromPlaylist: "Kabhi Main Kabhi Tum - All Episodes | ARY Digital") == "Kabhi Main Kabhi Tum")
		#expect(YouTubeEpisodes.showName(fromPlaylist: "Tere Bin Drama Serial") == "Tere Bin")
		#expect(YouTubeEpisodes.showName(fromPlaylist: "Humsafar") == "Humsafar")
	}

	@Test func matchesLinkEpisodesAndAddTheMissingOnes() {
		let season = Season(seasonNumber: 1)
		let first = Episode(episodeNumber: 1, seasonNumber: 1, title: "Pilot", stillURL: "tmdb.jpg", runtimeMinutes: 40)
		first.season = season
		season.episodes.append(first)
		season.status = .watched

		let report = YouTubeLibrary.apply([1: video("Episode 1", day: 1), 2: video("Episode 2", day: 2)],
		                                  playlistID: id, to: season)
		#expect(report == YouTubeLibrary.Report(linked: 1, added: 1))
		#expect(season.youtubePlaylistID == id)
		#expect(first.youtubeVideoID == "v1")
		#expect(first.title == "Pilot")              // its own title and still are kept
		#expect(first.stillURL == "tmdb.jpg")
		let second = season.sortedEpisodes[1]
		#expect(second.youtubeVideoID == "v2")
		#expect(second.displayTitle == "Episode 2")
		#expect(second.runtimeMinutes == 38)
		#expect(!second.airDate.isEmpty)
		#expect(season.status == .watching)          // a new episode reopens it
		#expect(report.summary == "2 episodes play from YouTube · 1 new")

		YouTubeLibrary.unlink(season)
		#expect(season.youtubePlaylistID == nil)
		#expect(season.episodes.allSatisfy { $0.youtubeVideoID == nil })
	}

	@Test func aShowCanBeMadeFromAPlaylist() {
		let playlist = YouTubePlaylist(id: id, title: "Tere Bin - All Episodes", channel: "Har Pal Geo",
		                               thumbnailURL: "thumb.jpg", videos: [video("Episode 1", day: 1)])
		let show = YouTubeLibrary.makeShow(named: "Tere Bin", from: playlist)
		#expect(show.title == "Tere Bin")
		#expect(show.posterURL == "thumb.jpg")
		#expect(show.seasons.count == 1)
		#expect(show.overview.contains("Har Pal Geo"))
		#expect(!show.firstAirYear.isEmpty)
	}
}
