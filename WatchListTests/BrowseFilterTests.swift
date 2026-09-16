//
//  BrowseFilterTests.swift
//  WatchListTests
//
//  The Shows tab's Filter & Sort: the type, status and sort segments, the
//  genres a library produces, which titles pass a status and picked genres,
//  and the orders the grid can take, both ways round.
//

import Foundation
import Testing
@testable import WatchList

@MainActor
struct BrowseFilterTests {

	@Test func typeSegmentsRunAllThenEachKindAndNameTheHeader() {
		#expect(BrowseKind.allCases.map(\.label) == ["All", "TV Shows", "Films"])
		#expect(BrowseKind.allCases.map(\.title) == ["Shows", "TV Shows", "Films"])
		#expect(BrowseKind.all.includesShows && BrowseKind.all.includesFilms)
		#expect(BrowseKind.shows.includesShows && !BrowseKind.shows.includesFilms)
		#expect(!BrowseKind.films.includesShows && BrowseKind.films.includesFilms)
	}

	@Test func statusSegmentsRunAllWatchingToWatchWatched() {
		#expect(StatusFilter.allCases.map(\.title) == ["All", "Watching", "To Watch", "Watched"])
		#expect(StatusFilter.all.systemImage == nil)
	}

	@Test func sortSegmentsRunAddedAToZYearRating() {
		#expect(BrowseSort.allCases.map(\.title) == ["Added", "A–Z", "Year", "Rating"])
	}

	@Test func tappingTheChosenSortAgainReversesIt() {
		var order = BrowseOrder()
		#expect(order.summary == "Newest added first")
		#expect(order.arrowSymbol == "arrow.down")

		order.choose(.added)
		#expect(order == BrowseOrder(sort: .added, reversed: true))
		#expect(order.summary == "Oldest added first")
		#expect(order.arrowSymbol == "arrow.up")

		order.choose(.title)                                 // a new sort starts its usual way
		#expect(order == BrowseOrder(sort: .title, reversed: false))
		#expect(order.segmentTitle(for: .title) == "A–Z")
		#expect(order.arrowSymbol == nil)
		order.choose(.title)
		#expect(order.segmentTitle(for: .title) == "Z–A")
		#expect(order.segmentTitle(for: .year) == "Year")

		order.choose(.rating)
		#expect(order.summary == "Highest rated first")
	}

	@Test func genresAreSplitDeduplicatedAndSorted() {
		let genres = BrowseFilter.genres(in: ["Drama, Crime", "crime", "", "Action & Adventure, Drama"])
		#expect(genres == ["Action & Adventure", "Crime", "Drama"])
	}

	@Test func theStatusAndAnyPickedGenreHaveToMatch() {
		#expect(BrowseFilter.matches(status: .watching, genres: "Drama, Crime", statusFilter: .watching, picked: ["crime"]))
		#expect(BrowseFilter.matches(status: .watched, genres: "Drama, Crime", statusFilter: .all, picked: ["Comedy", "Crime"]))
		#expect(!BrowseFilter.matches(status: .watched, genres: "Drama, Crime", statusFilter: .all, picked: ["Comedy"]))
		#expect(!BrowseFilter.matches(status: .toWatch, genres: "Drama, Crime", statusFilter: .watching, picked: []))
		#expect(BrowseFilter.matches(status: .toWatch, genres: "", statusFilter: .all, picked: []))
	}

	@Test func aGenreHasToBeWholeNotPartOfAnother() {
		#expect(!BrowseFilter.matches(status: .watched, genres: "Action & Adventure", statusFilter: .all, picked: ["Action"]))
	}

	@Test func eachOrderRunsBothWaysWithTheUnknownLast() {
		let now = Date(timeIntervalSince1970: 1_800_000_000)
		let severance = Show(title: "Severance", firstAirYear: "2022", rating: .perfection)
		severance.dateAdded = now
		let blank = Show(title: "Blank")                       // no year, unrated
		blank.dateAdded = now.addingTimeInterval(-30)
		let arrival = Film(title: "arrival", year: "2016", rating: .goForIt)
		arrival.stars = 4.5
		arrival.dateAdded = now.addingTimeInterval(-60)
		let zodiac = Film(title: "Zodiac", year: "2007")       // unrated
		zodiac.dateAdded = now.addingTimeInterval(-120)
		let items: [WatchedTitle] = [.film(zodiac), .show(blank), .film(arrival), .show(severance)]

		func order(_ sort: BrowseSort, reversed: Bool = false) -> [String] {
			BrowseFilter.sorted(items, by: BrowseOrder(sort: sort, reversed: reversed)).map(\.title)
		}
		#expect(order(.added) == ["Severance", "Blank", "arrival", "Zodiac"])
		#expect(order(.added, reversed: true) == ["Zodiac", "arrival", "Blank", "Severance"])
		#expect(order(.title) == ["arrival", "Blank", "Severance", "Zodiac"])
		#expect(order(.title, reversed: true) == ["Zodiac", "Severance", "Blank", "arrival"])
		#expect(order(.year) == ["Severance", "arrival", "Zodiac", "Blank"])
		#expect(order(.year, reversed: true) == ["Zodiac", "arrival", "Severance", "Blank"])
		#expect(order(.rating) == ["Severance", "arrival", "Blank", "Zodiac"])
		#expect(order(.rating, reversed: true) == ["arrival", "Severance", "Blank", "Zodiac"])
	}
}
