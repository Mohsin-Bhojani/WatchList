//
//  LibraryRefresherTests.swift
//  WatchListTests
//
//  The refresh has one property that matters more than the rest: it adds and
//  never takes away. A show you're halfway through, with watched marks and a
//  rewatch tier on individual episodes, has to come out the far side of a
//  refresh exactly as it went in — plus whatever aired since.
//

import Foundation
import Testing
@testable import WatchList

@MainActor
struct SeasonFetchPlanTests {

	private func season(_ number: Int, episodes: Int) -> Season {
		let s = Season(seasonNumber: number)
		for n in 1...max(episodes, 1) where episodes > 0 {
			let e = Episode(episodeNumber: n, seasonNumber: number, title: "E\(n)")
			e.season = s
			s.episodes.append(e)
		}
		return s
	}

	private func summary(_ number: Int, count: Int?) -> TMDbSeasonSummary {
		TMDbSeasonSummary(season_number: number, episode_count: count, name: "Season \(number)")
	}

	@Test func aBrandNewSeasonIsFetched() {
		// The reported bug: added a show, it later got a season 2.
		let plan = LibraryRefresher.seasonsNeedingFetch(
			summaries: [summary(1, count: 10), summary(2, count: 8)],
			existing: [season(1, episodes: 10)]
		)
		#expect(plan == [2])
	}

	@Test func anUnchangedSeasonCostsNoRequest() {
		let plan = LibraryRefresher.seasonsNeedingFetch(
			summaries: [summary(1, count: 10), summary(2, count: 8)],
			existing: [season(1, episodes: 10), season(2, episodes: 8)]
		)
		#expect(plan.isEmpty)
	}

	@Test func aSeasonGainingWeeklyEpisodesIsFetched() {
		let plan = LibraryRefresher.seasonsNeedingFetch(
			summaries: [summary(1, count: 6)],
			existing: [season(1, episodes: 3)]
		)
		#expect(plan == [1])
	}

	@Test func specialsAreSkipped() {
		// Import filters season 0; refresh has to agree or it'd add specials
		// nobody asked for.
		let plan = LibraryRefresher.seasonsNeedingFetch(
			summaries: [summary(0, count: 5), summary(1, count: 10)],
			existing: []
		)
		#expect(plan == [1])
	}

	@Test func missingEpisodeCountForcesAFetch() {
		// TMDb omitting the count means we can't rule the season out.
		let plan = LibraryRefresher.seasonsNeedingFetch(
			summaries: [summary(1, count: nil)],
			existing: [season(1, episodes: 10)]
		)
		#expect(plan == [1])
	}

	@Test func aShrunkSeasonIsStillFetchedButNothingIsDeleted() {
		// TMDb correcting a count downwards shouldn't strand us; the fetch
		// happens, and missingEpisodes below is what guarantees no deletion.
		let plan = LibraryRefresher.seasonsNeedingFetch(
			summaries: [summary(1, count: 8)],
			existing: [season(1, episodes: 10)]
		)
		#expect(plan == [1])
	}

	@Test func planIsSorted() {
		let plan = LibraryRefresher.seasonsNeedingFetch(
			summaries: [summary(3, count: 1), summary(1, count: 1), summary(2, count: 1)],
			existing: []
		)
		#expect(plan == [1, 2, 3])
	}
}

// MARK: - Episode merge

struct EpisodeMergeTests {

	private func detail(episodeNumbers: [Int]) throws -> TMDbSeasonDetail {
		let episodes = episodeNumbers
			.map { #"{"episode_number":\#($0),"name":"E\#($0)"}"# }
			.joined(separator: ",")
		let json = #"{"name":"Season 1","episodes":[\#(episodes)]}"#
		return try JSONDecoder().decode(TMDbSeasonDetail.self, from: Data(json.utf8))
	}

	@Test func returnsOnlyWhatIsNew() throws {
		let missing = LibraryRefresher.missingEpisodes(
			from: try detail(episodeNumbers: [1, 2, 3, 4, 5]),
			have: [1, 2, 3]
		)
		#expect(missing.map(\.episode_number) == [4, 5])
	}

	@Test func returnsNothingWhenAlreadyComplete() throws {
		let missing = LibraryRefresher.missingEpisodes(
			from: try detail(episodeNumbers: [1, 2, 3]),
			have: [1, 2, 3]
		)
		#expect(missing.isEmpty)
	}

	@Test func returnsEverythingForAnEmptySeason() throws {
		let missing = LibraryRefresher.missingEpisodes(
			from: try detail(episodeNumbers: [1, 2]),
			have: []
		)
		#expect(missing.count == 2)
	}

	@Test func neverProposesRemovingAnEpisodeTMDbDropped() throws {
		// Local has 5, TMDb now lists 3. The two extras are ours to keep -
		// they may be watched, rated, or tiered.
		let missing = LibraryRefresher.missingEpisodes(
			from: try detail(episodeNumbers: [1, 2, 3]),
			have: [1, 2, 3, 4, 5]
		)
		#expect(missing.isEmpty)
	}

	@Test func handlesNonContiguousNumbering() throws {
		let missing = LibraryRefresher.missingEpisodes(
			from: try detail(episodeNumbers: [1, 2, 3, 4]),
			have: [1, 3]
		)
		#expect(missing.map(\.episode_number) == [2, 4])
	}
}

// MARK: - Report wording

struct RefreshReportTests {

	@Test func reportsNothingFoundPlainly() {
		var r = LibraryRefresher.Report()
		r.showsChecked = 5
		#expect(r.summary == "Everything's up to date.")
		#expect(!r.foundSomething)
	}

	@Test func namesWhatWasAdded() {
		var r = LibraryRefresher.Report()
		r.showsChecked = 3
		r.seasonsAdded = 1
		r.episodesAdded = 8
		#expect(r.summary == "Added 1 new season and 8 new episodes.")
	}

	@Test func singularReadsCorrectly() {
		var r = LibraryRefresher.Report()
		r.showsChecked = 1
		r.episodesAdded = 1
		#expect(r.summary == "Added 1 new episode.")
	}

	@Test func surfacesFailuresWhenNothingWasAdded() {
		var r = LibraryRefresher.Report()
		r.showsChecked = 4
		r.showsFailed = 2
		#expect(r.summary == "Up to date. 2 shows couldn't be checked.")
	}

	@Test func emptyLibraryDoesNotClaimToBeUpToDate() {
		#expect(LibraryRefresher.Report().summary == "Nothing to check yet.")
	}

	@Test func reportsCombine() {
		var a = LibraryRefresher.Report(); a.showsChecked = 1; a.episodesAdded = 2
		var b = LibraryRefresher.Report(); b.showsChecked = 1; b.seasonsAdded = 1
		let total = a + b
		#expect(total.showsChecked == 2)
		#expect(total.episodesAdded == 2)
		#expect(total.seasonsAdded == 1)
	}
}
