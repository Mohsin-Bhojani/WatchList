//
//  ShowFactsTests.swift
//  WatchListTests
//
//  The lines the iPhone show pages are built from.
//

import Foundation
import Testing
@testable import WatchList

@MainActor
struct ShowFactsTests {

	@Test func episodeCodesAreShortAndSpecialsSaySo() {
		#expect(ShowFacts.code(season: 2, episode: 3) == "S2 E3")
		#expect(ShowFacts.code(season: 0, episode: 2) == "Special 2")
	}

	@Test func countsReadInTheSingularToo() {
		#expect(ShowFacts.seasons(1) == "1 season")
		#expect(ShowFacts.seasons(4) == "4 seasons")
		#expect(ShowFacts.episodes(1) == "1 episode")
		#expect(ShowFacts.progressLine(watched: 6, total: 13) == "6 of 13 episodes watched")
	}

	@Test func progressStaysBetweenNothingAndAll() {
		#expect(ShowFacts.fraction(watched: 0, total: 0) == 0)
		#expect(ShowFacts.fraction(watched: 3, total: 12) == 0.25)
		#expect(ShowFacts.fraction(watched: 14, total: 13) == 1)
	}

	private func episodes(_ count: Int) -> [Episode] {
		(1...count).map { Episode(episodeNumber: $0, seasonNumber: 1, title: "E\($0)") }
	}

	@Test func nextIsAfterTheMostRecentlyMarkedEpisode() {
		let run = episodes(5)
		let now = Date(timeIntervalSince1970: 1_800_000_000)
		for index in [0, 1, 3] { run[index].status = .watched }

		// Without dates, the last Watched in running order: E4, so E5.
		#expect(ShowFacts.nextAfterLastWatched(run)?.episodeNumber == 5)
		// With dates, the one marked last: E2, so E3 — even though E4 is Watched.
		run[0].watchedAt = now
		run[3].watchedAt = now.addingTimeInterval(60)
		run[1].watchedAt = now.addingTimeInterval(120)
		#expect(ShowFacts.nextAfterLastWatched(run)?.episodeNumber == 3)
	}

	@Test func nextStartsAtTheBeginningAndEndsAfterTheLast() {
		let run = episodes(2)
		#expect(ShowFacts.nextAfterLastWatched(run)?.episodeNumber == 1)
		run[1].status = .watched
		#expect(ShowFacts.nextAfterLastWatched(run) == nil)
		#expect(ShowFacts.nextAfterLastWatched([]) == nil)
	}

	/// A show with the seasons given, numbered, each with that many episodes.
	private func show(_ seasons: [(number: Int, episodes: Int)]) -> Show {
		let show = Show(title: "Show")
		for (number, count) in seasons {
			let season = Season(seasonNumber: number)
			season.show = show
			show.seasons.append(season)
			for episodeNumber in 1...count {
				let episode = Episode(episodeNumber: episodeNumber, seasonNumber: number, title: "E\(episodeNumber)")
				episode.season = season
				season.episodes.append(episode)
			}
		}
		return show
	}

	@Test func aSwipeRunsThroughTheShowSeasonBySeason() {
		// Added out of order, as TMDb's seasons can arrive.
		let s = show([(2, 2), (0, 2), (1, 3)])
		let opened = s.sortedSeasons[2].sortedEpisodes[0]
		let run = ShowFacts.swipeRun(around: opened)
		#expect(run.map(ShowFacts.code) == ["S1 E1", "S1 E2", "S1 E3", "S2 E1", "S2 E2"])
		#expect(run.contains { $0.id == opened.id })
	}

	@Test func aSpecialSwipesAmongTheSpecials() {
		let s = show([(0, 2), (1, 3)])
		let special = s.sortedSeasons[0].sortedEpisodes[1]
		#expect(ShowFacts.swipeRun(around: special).map(ShowFacts.code) == ["Special 1", "Special 2"])
	}

	@Test func anEpisodeOutsideAShowSwipesNowhere() {
		let loose = Episode(episodeNumber: 4, seasonNumber: 1, title: "E4")
		#expect(ShowFacts.swipeRun(around: loose).map(\.id) == [loose.id])
	}

	@Test func theListLineFollowsTheStatus() {
		#expect(ShowFacts.listLine(status: .toWatch, watched: 0, total: 13, nextCode: "S1 E1")
			== "In your list · not started")
		#expect(ShowFacts.listLine(status: .toWatch, watched: 2, total: 13, nextCode: "S1 E3")
			== "In your list · 2 of 13 watched")
		#expect(ShowFacts.listLine(status: .watching, watched: 6, total: 13, nextCode: "S2 E3")
			== "Watching · S2 E3")
		#expect(ShowFacts.listLine(status: .watching, watched: 13, total: 13, nextCode: nil) == "Watching")
		#expect(ShowFacts.listLine(status: .watched, watched: 13, total: 13, nextCode: nil) == "Finished")
	}
}
