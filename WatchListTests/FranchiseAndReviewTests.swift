//
//  FranchiseAndReviewTests.swift
//  WatchListTests
//
//  Film series grouped from your films, their order and progress, and TMDb
//  reviews made readable.
//

import Foundation
import Testing
@testable import WatchList
@testable import WatchListCore
@testable import WatchListLibrary

@MainActor
struct FranchiseAndReviewTests {

	private func movie(_ id: Int, series: TMDbCollectionRef?) -> TMDbMovie {
		TMDbMovie(id: id, title: "Film \(id)", belongs_to_collection: series)
	}

	@Test func aFilmKeepsItsSeriesOrThatItHasNone() {
		let matrix = Film(title: "The Matrix", tmdbID: 603)
		#expect(matrix.needsFranchiseCheck)
		matrix.setFranchise(from: movie(603, series: TMDbCollectionRef(id: 2344, name: "The Matrix Collection")))
		#expect(matrix.franchiseID == 2344)
		#expect(matrix.franchiseName == "The Matrix")
		#expect(!matrix.needsFranchiseCheck)

		let alone = Film(title: "Heat", tmdbID: 949)
		alone.setFranchise(from: movie(949, series: nil))
		#expect(alone.franchiseID == nil)
		#expect(!alone.needsFranchiseCheck)

		#expect(!Film(title: "Home video").needsFranchiseCheck)   // no TMDb id to ask with
	}

	@Test func filmsGroupBySeriesBiggestFirstOldestWithin() {
		func film(_ title: String, _ year: String, series: Int?, name: String?, watched: Bool = false) -> Film {
			let f = Film(title: title, year: year, tmdbID: Int.random(in: 1...999_999),
			             status: watched ? .watched : .toWatch)
			f.franchiseID = series
			f.franchiseName = name
			return f
		}
		let groups = Franchises.groups([
			film("The Matrix Reloaded", "2003", series: 1, name: "The Matrix", watched: true),
			film("The Matrix", "1999", series: 1, name: "The Matrix", watched: true),
			film("John Wick", "2014", series: 2, name: "John Wick"),
			film("Heat", "1995", series: nil, name: nil),
		])
		#expect(groups.map(\.name) == ["The Matrix", "John Wick"])
		#expect(groups[0].films.map(\.title) == ["The Matrix", "The Matrix Reloaded"])
		#expect(groups[0].watchedCount == 2)
		#expect(Franchises.cardLine(groups[1]) == "1 film in your library · 0 watched")
	}

	@Test func seriesRunInReleaseOrderAndCountOnlyWhatsOut() {
		let parts = Franchises.ordered([
			TMDbCollectionPart(id: 3, title: "Third", release_date: ""),
			TMDbCollectionPart(id: 2, title: "Second", release_date: "2003-05-15"),
			TMDbCollectionPart(id: 1, title: "First", release_date: "1999-03-31"),
			TMDbCollectionPart(id: 4, title: "Fourth", release_date: "2030-01-01"),
		])
		#expect(parts.map(\.id) == [1, 2, 4, 3])

		let seen = Film(title: "First", tmdbID: 1, status: .watched)
		let listed = Film(title: "Second", tmdbID: 2)
		#expect(Franchises.progress(parts: parts, films: [seen, listed], today: "2026-11-13") == "1 of 2 watched")
	}

	@Test func seriesNamesDropTheWordCollection() {
		#expect(Franchises.displayName("Harry Potter Collection") == "Harry Potter")
		#expect(Franchises.displayName("Alien") == "Alien")
		#expect(Franchises.displayName(" Collection") == "Collection")
	}

	@Test func reviewsReadAsPlainText() {
		let raw = "**Great** film.<br/>Really <em>great</em>.\r\n\r\n\r\n\r\nSee [my blog](https://x.y) &amp; more.  \n"
		#expect(ReviewText.cleaned(raw) == "Great film.\nReally great.\n\nSee my blog & more.")
	}

	@Test func reviewersStarsAndDatesRead() {
		let review = TMDbReview(id: "a", author: "jdoe",
		                        author_details: .init(name: "", username: "jdoe", rating: 7),
		                        content: "Fine.", created_at: "2023-03-15T12:30:00.123Z")
		#expect(ReviewText.author(review) == "jdoe")
		#expect(ReviewText.stars(review) == 3.5)
		#expect(ReviewText.date(review) != nil)

		let anonymous = TMDbReview(id: "b", author: nil, content: "   ")
		#expect(ReviewText.author(anonymous) == "A TMDb user")
		#expect(ReviewText.stars(anonymous) == nil)
		#expect(ReviewText.readable([review, anonymous]).map(\.id) == ["a"])
	}
}
