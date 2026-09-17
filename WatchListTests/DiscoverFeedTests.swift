//
//  DiscoverFeedTests.swift
//  WatchListTests
//
//  The Discover tab: which library titles suggestions start from, the order
//  they're offered in, what TMDb's average comes to, how alike a suggestion is
//  to the titles in the library, and the filter — its type, genres and More
//  like.
//

import Foundation
import Testing
@testable import WatchList

@MainActor
struct DiscoverFeedTests {

	private let now = Date(timeIntervalSince1970: 1_800_000_000)

	private func suggestion(_ kind: MediaKind, _ tmdbID: Int, _ title: String, year: Int? = nil,
	                        genres: [String] = [], score: Double? = nil) -> Suggestion {
		Suggestion(kind: kind, tmdbID: tmdbID, title: title, year: year, posterURL: "poster-\(tmdbID).jpg",
		           averageScore: score, genres: genres)
	}

	@Test func seedsRunPerfectionGoForItTimepassThenRecentlyAdded() {
		let olderPerfection = Show(title: "Older Perfection", tmdbID: 1, rating: .perfection)
		olderPerfection.ratedAt = now.addingTimeInterval(-500)
		let newerPerfection = Film(title: "Newer Perfection", tmdbID: 2, rating: .perfection)
		newerPerfection.ratedAt = now.addingTimeInterval(-10)
		let goForIt = Show(title: "Go For It", tmdbID: 3, rating: .goForIt)
		let timepass = Film(title: "Timepass", tmdbID: 4, rating: .timepass)
		let skipped = Show(title: "Skipped", tmdbID: 5, rating: .skip)
		let addedEarlier = Film(title: "Added earlier", tmdbID: 6)
		addedEarlier.dateAdded = now.addingTimeInterval(-900)
		let addedLater = Show(title: "Added later", tmdbID: 7)
		addedLater.dateAdded = now
		let byHand = Film(title: "Added by hand")              // TMDb doesn't know it

		let seeds = DiscoverFeed.seeds(shows: [olderPerfection, goForIt, skipped, addedLater],
		                               films: [newerPerfection, timepass, addedEarlier, byHand])
		#expect(seeds.map(\.title) == ["Newer Perfection", "Older Perfection", "Go For It", "Timepass",
		                               "Added later", "Added earlier"])
	}

	@Test func theQueueFollowsTheSeedsOnceEachWithPutOffTitlesLast() {
		let first = UUID(), second = UUID()
		let a = suggestion(.show, 10, "A"), b = suggestion(.show, 11, "B"), c = suggestion(.show, 12, "C")
		let d = suggestion(.show, 13, "D")
		let owned = suggestion(.show, 14, "In the library"), declined = suggestion(.show, 15, "Turned down")

		let queue = DiscoverFeed.queue(seedOrder: [first, second],
		                               similar: [second: [c, b, d], first: [a, owned, b, declined]],
		                               excluding: [owned.id, declined.id],
		                               putOff: [a.id: now, d.id: now.addingTimeInterval(-60)])

		#expect(queue.map(\.title) == ["B", "C", "D", "A"])
		// B came from both seeds; A only from the first.
		#expect(queue.first?.seeds == [first, second])
		#expect(queue.last?.seeds == [first])
	}

	@Test func tmdbsAverageComesToStarsAndAVerdict() {
		#expect(suggestion(.film, 1, "8.4", score: 8.4).averageStars == 4)
		#expect(suggestion(.film, 1, "8.4", score: 8.4).equivalentVerdict == .goForIt)
		#expect(suggestion(.film, 1, "9.6", score: 9.6).equivalentVerdict == .perfection)
		#expect(suggestion(.film, 1, "6.2", score: 6.2).equivalentVerdict == .timepass)
		#expect(suggestion(.film, 1, "3.1", score: 3.1).equivalentVerdict == .skip)
		#expect(suggestion(.film, 1, "No votes").equivalentVerdict == nil)
	}

	@Test func aTMDbTitleNeedsAPosterAndHasNoAverageBeforeVotes() throws {
		let dark = TMDbSuggestedTitle(id: 7, name: "Dark", title: nil, first_air_date: "2017-12-01", release_date: nil,
		                              overview: "  A missing boy sets four families searching.\n", vote_average: 0,
		                              poster_path: "/dark.jpg", genre_ids: [18, 9648, 999])
		let show = try #require(Suggestion(dark, kind: .show, genreNames: [18: "Drama", 9648: "Mystery"]))
		#expect(show.id == AddCandidate.key(.show, 7))
		#expect(show.title == "Dark")
		#expect(show.year == 2017)
		#expect(show.genres == ["Drama", "Mystery"])
		#expect(show.overview == "A missing boy sets four families searching.")
		#expect(show.averageScore == nil)
		#expect(show.largePosterURL.hasSuffix("/w780/dark.jpg"))

		let posterless = TMDbSuggestedTitle(id: 8, name: "No poster", title: nil, first_air_date: nil, release_date: nil,
		                                    overview: nil, vote_average: 7, poster_path: nil, genre_ids: nil)
		#expect(Suggestion(posterless, kind: .show, genreNames: [:]) == nil)

		let arrival = TMDbSuggestedTitle(id: 9, name: nil, title: "Arrival", first_air_date: nil,
		                                 release_date: "2016-11-10", overview: nil, vote_average: 7.6,
		                                 poster_path: "/arrival.jpg", genre_ids: [18])
		let film = try #require(Suggestion(arrival, kind: .film, genreNames: [18: "Drama"]))
		#expect(film.title == "Arrival")
		#expect(film.year == 2016)
		#expect(film.averageScore == 7.6)
		#expect(film.overview.isEmpty)
	}

	@Test func alikenessWeighsGenresTheSeedTheKindAndTheYear() {
		let severance = Show(title: "Severance", genre: "Drama, Mystery, Sci-Fi & Fantasy", firstAirYear: "2022",
		                     tmdbID: 95396)
		let arrival = Film(title: "Arrival", genre: "Drama, Science Fiction", year: "2016", tmdbID: 329865)
		let zodiac = Film(title: "Zodiac", genre: "Crime, Thriller", year: "2007", tmdbID: 1949)
		var suggested = suggestion(.show, 1, "Suggested", year: 2022, genres: ["Drama", "Mystery", "Sci-Fi & Fantasy"])
		suggested.seeds = [severance.id]

		let rows = Similarity.rows(for: suggested, in: [.film(zodiac), .show(severance), .film(arrival)])
		#expect(rows.map(\.title.title) == ["Severance", "Arrival", "Zodiac"])
		// Everything in common; half the genres and six years apart; nothing but the era.
		#expect(rows.map(\.percent) == [100, 34, 3])
		#expect(Similarity.closest(to: suggested, in: [.film(zodiac), .show(severance), .film(arrival)])?.title.title
			== "Severance")
		// Alike to the same degree, the first A–Z is closest, as it leads the rows.
		let lookalike = Film(title: "A Zodiac", genre: "Crime, Thriller", year: "2007", tmdbID: 1950)
		#expect(Similarity.closest(to: suggested, in: [.film(zodiac), .film(lookalike)])?.title.title == "A Zodiac")
		#expect(Similarity.closest(to: suggested, in: [])?.percent == nil)
	}

	@Test func genresLineUpAcrossTVAndFilmNames() {
		#expect(Similarity.genreSet(["Sci-Fi & Fantasy", "Kids"]) == ["science fiction", "fantasy", "family"])
		#expect(Similarity.genreSet(["Action & Adventure"]) == Similarity.genreSet(["Adventure", "action"]))
	}

	@Test func theReasonNamesTheFirstTitleItCameFrom() {
		let rated = Show(title: "Severance", tmdbID: 1, rating: .perfection)
		let added = Film(title: "Arrival", tmdbID: 2)
		let library: [WatchedTitle] = [.film(added), .show(rated)]
		var suggested = suggestion(.show, 3, "Suggested")
		suggested.seeds = [rated.id, added.id]
		#expect(DiscoverFeed.reason(for: suggested, in: library) == "Because you rated Severance Perfection")
		suggested.seeds = [added.id]
		#expect(DiscoverFeed.reason(for: suggested, in: library) == "Because you added Arrival")
	}

	@Test func aSwipeDecidesPastTheThresholdTheWayTheCardMoved() {
		func decision(_ moved: CGSize, heading: CGSize? = nil) -> CardDecision? {
			CardDecision.forSwipe(translation: moved, predictedEnd: heading ?? moved)
		}
		#expect(decision(CGSize(width: 150, height: 20)) == .add)
		#expect(decision(CGSize(width: -150, height: 40)) == .notInterested)
		#expect(decision(CGSize(width: 20, height: -160)) == .later)
		#expect(decision(CGSize(width: 0, height: 200)) == nil)          // down does nothing
		#expect(decision(CGSize(width: 90, height: 0)) == nil)           // not far enough
		// A flick counts where it was heading…
		#expect(decision(CGSize(width: 50, height: 0), heading: CGSize(width: 400, height: 10)) == .add)
		// …but not one thrown back the other way, or one that hardly moved.
		#expect(decision(CGSize(width: 150, height: 0), heading: CGSize(width: -300, height: 0)) == nil)
		#expect(decision(CGSize(width: 10, height: 0), heading: CGSize(width: 400, height: 0)) == nil)
	}

	@Test func aDraggedCardLeansTowardsItsDecision() {
		let right = CardDecision.leaning(CGSize(width: 60, height: 10))
		#expect(right?.decision == .add)
		#expect(right?.progress == 0.5)
		let up = CardDecision.leaning(CGSize(width: -10, height: -300))
		#expect(up?.decision == .later)
		#expect(up?.progress == 1)
		#expect(CardDecision.leaning(CGSize(width: 0, height: 80)) == nil)
	}

	@Test func fiveDecisionsMoveOnUnlessThreeOfThemWereAdds() {
		let a = UUID(), b = UUID(), c = UUID()
		var rotation = DiscoverRotation()
		/// Which of these decisions, taken in turn, moved Discover on.
		func moves(_ decisions: [CardDecision], from seed: UUID) -> [Bool] {
			decisions.map { rotation.record($0, from: seed) }
		}

		// Two adds in five aren't enough: the fifth decision moves on, whatever it is.
		#expect(moves([.add, .notInterested, .add, .notInterested, .notInterested], from: a)
			== [false, false, false, false, true])
		#expect(rotation.order([a, b, c]) == [b, c, a])

		// Three adds earn five more from the same title…
		#expect(moves([.add, .later, .add, .notInterested, .add], from: b) == [false, false, false, false, false])
		#expect(rotation.order([a, b, c]) == [b, c, a])
		// …which are weighed up on their own.
		#expect(moves([.add, .add, .later, .later, .later], from: b) == [false, false, false, false, true])
		#expect(rotation.order([a, b, c]) == [c, a, b])
	}

	@Test func aDecisionOnAnotherTitlesSuggestionStartsItsOwnCount() {
		let a = UUID(), b = UUID()
		var rotation = DiscoverRotation()
		func moves(_ decisions: [CardDecision], from seed: UUID) -> [Bool] {
			decisions.map { rotation.record($0, from: seed) }
		}

		#expect(moves(Array(repeating: .later, count: 4), from: a) == [false, false, false, false])
		#expect(moves([.later], from: b) == [false])
		#expect(moves([.later], from: a) == [false])               // a counts from one again
		#expect(rotation.order([a, b]) == [a, b])
	}

	@Test func aTitleHasRoomForWhatsLeftOfItsBatch() {
		let a = UUID(), b = UUID()
		var rotation = DiscoverRotation()
		#expect(rotation.room(for: a) == 5)
		rotation.record(.later, from: a)
		rotation.record(.add, from: a)
		#expect(rotation.room(for: a) == 3)
		#expect(rotation.room(for: b) == 5)
	}

	@Test func theTitleInUseKeepsTheLeadOverTitlesAddedMeanwhile() {
		let older = UUID(), inUse = UUID(), added = UUID()
		var rotation = DiscoverRotation()
		rotation.record(.add, from: inUse)
		// What was added from it is a seed too, and the newest added sorts first.
		#expect(rotation.order([added, older, inUse]) == [inUse, added, older])
		for _ in 0..<4 { rotation.record(.later, from: inUse) }
		#expect(rotation.order([added, older, inUse]) == [added, older, inUse])
	}

	@Test func passingEveryTitleGoesRoundAgain() {
		let a = UUID(), b = UUID()
		var rotation = DiscoverRotation()
		for _ in 0..<5 { rotation.record(.notInterested, from: a) }
		for _ in 0..<5 { rotation.record(.notInterested, from: b) }
		#expect(rotation.order([a, b]) == [a, b])                  // both passed: the longest ago leads
		rotation.record(.notInterested, from: a)
		#expect(rotation.order([a, b]) == [a, b])                  // back in use, it keeps the lead
		for _ in 0..<4 { rotation.record(.notInterested, from: a) }
		#expect(rotation.order([a, b]) == [b, a])
	}

	@Test func cardsReadyCountEachTitleOnlyAsFarAsItsTurnGoes() {
		let first = UUID(), unfetched = UUID(), second = UUID()
		let shared = suggestion(.show, 1, "Shared"), declined = suggestion(.show, 2, "Turned down")
		let firsts = [shared, declined] + (10..<16).map { suggestion(.show, $0, "First \($0)") }
		let seconds = [shared] + (20..<22).map { suggestion(.film, $0, "Second \($0)") }
		var rotation = DiscoverRotation()
		rotation.record(.later, from: first)
		rotation.record(.add, from: first)

		func ready(wanted: Int = 20, kind: BrowseKind = .all) -> Int {
			DiscoverFeed.ready(seedOrder: [first, unfetched, second], similar: [first: firsts, second: seconds],
			                   excluding: [declined.id], matching: DiscoverFilter(kind: kind), rotation: rotation,
			                   wanted: wanted)
		}
		// The three left in the first title's batch, Shared among them; none from
		// the title not fetched yet; and the second title's two not counted already.
		#expect(ready() == 5)
		#expect(ready(wanted: 4) == 4)
		#expect(ready(kind: .films) == 2)
	}

	@Test func theFilterKeepsAKindAndAnyPickedGenreAcrossTVAndFilmNames() {
		let show = suggestion(.show, 1, "Show", genres: ["Action & Adventure", "Drama"])
		let film = suggestion(.film, 2, "Film", genres: ["Comedy"])
		#expect(DiscoverFilter().matches(show) && DiscoverFilter().matches(film))
		#expect(DiscoverFilter().isDefault)
		#expect(!DiscoverFilter(kind: .films).matches(show))
		#expect(DiscoverFilter(kind: .films).matches(film))
		// TV's joint genre counts as each of its halves.
		#expect(DiscoverFilter(genres: ["Action"]).matches(show))
		#expect(!DiscoverFilter(genres: ["Action"]).matches(film))
		#expect(DiscoverFilter(kind: .shows, genres: ["Comedy", "Drama"]).matches(show))
		#expect(!DiscoverFilter(kind: .shows, genres: ["Comedy"]).isDefault)

		#expect(DiscoverFilter.genreOptions(for: .all, tv: ["Drama", "Action & Adventure"], movie: ["Action", "Drama"])
			== ["Action", "Action & Adventure", "Drama"])
		#expect(DiscoverFilter.genreOptions(for: .films, tv: ["Soap"], movie: ["Action"]) == ["Action"])
	}

	@Test func theSummaryLeadsWithTheTitleSuggestionsComeFrom() {
		#expect(DiscoverFilter().summary(seedTitle: nil) == nil)
		#expect(!DiscoverFilter(seed: UUID()).isDefault)
		#expect(DiscoverFilter(genres: ["Mystery", "Drama"], seed: UUID()).summary(seedTitle: "Severance")
			== "Severance · Drama, Mystery")
		#expect(DiscoverFilter(kind: .films, genres: ["A", "B", "C"]).summary(seedTitle: nil) == "Films · 3 genres")
		#expect(DiscoverFilter(kind: .shows, seed: UUID()).summary(seedTitle: "Dark") == "Dark · TV Shows")
	}

	@Test func moreLikeSaysWhatPickingATitleDoes() {
		#expect(DiscoverFeed.moreLikeCaption(for: nil) == "Suggestions from your whole library, best rated first.")
		let rated = Show(title: "Severance", tmdbID: 1, rating: .perfection)
		#expect(DiscoverFeed.moreLikeCaption(for: .show(rated))
			== "Only what\u{2019}s suggested because you rated Severance Perfection.")
		let added = Show(title: "Slow Horses", tmdbID: 2)
		#expect(DiscoverFeed.moreLikeCaption(for: .show(added))
			== "Only what\u{2019}s suggested because you added Slow Horses.")
	}

	@Test func seeAllGroupsTitlesByVerdictThenAddedAndSearchesThem() {
		let severance = Show(title: "Severance", tmdbID: 1, rating: .perfection)
		let arrival = Film(title: "Arrival", tmdbID: 2, rating: .perfection)
		let bear = Show(title: "The Bear", tmdbID: 3, rating: .goForIt)
		let slowHorses = Show(title: "Slow Horses", tmdbID: 4)
		let seeds: [WatchedTitle] = [.show(severance), .film(arrival), .show(bear), .show(slowHorses)]

		let groups = DiscoverFeed.seedGroups(seeds)
		#expect(groups.map(\.name) == ["Rated Perfection", "Rated Go For It", "Added"])
		#expect(groups[0].titles.map(\.title) == ["Severance", "Arrival"])
		#expect(groups[2].titles.map(\.title) == ["Slow Horses"])

		let searched = DiscoverFeed.seedGroups(seeds, matching: " s ")
		#expect(searched.map(\.name) == ["Rated Perfection", "Added"])
		#expect(searched.flatMap(\.titles).map(\.title) == ["Severance", "Slow Horses"])
		#expect(DiscoverFeed.seedGroups(seeds, matching: "zzz").isEmpty)
	}

	@Test func genreTilesAreDealtOntoTheShortestRowSoRowsEndLevel() {
		// Widths straight from the names' lengths, 6 apart.
		let rows = ChipRows.deal(["All", "Action", "Drama", "Comedy", "War", "Crime"], into: 3, spacing: 6) {
			CGFloat($0.count * 10)
		}
		#expect(rows == [["All", "Comedy"], ["Action", "Crime"], ["Drama", "War"]])
		#expect(ChipRows.deal(["A"], into: 3, spacing: 6) { _ in 10 } == [["A"]])
		#expect(ChipRows.rowCount(for: 12) == 2)
		#expect(ChipRows.rowCount(for: 28) == 3)
	}
}
