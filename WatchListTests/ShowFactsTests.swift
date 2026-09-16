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
