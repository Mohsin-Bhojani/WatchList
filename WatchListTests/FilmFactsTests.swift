//
//  FilmFactsTests.swift
//  WatchListTests
//
//  The words and numbers on the iPhone film page: runtime, release date, TMDb
//  stars, vote counts and genres.
//

import Foundation
import Testing
@testable import WatchList

@MainActor
struct FilmFactsTests {
	private let british = Locale(identifier: "en_GB")

	@Test func runtimeReadsHoursAndPaddedMinutes() {
		#expect(FilmFacts.runtime(124) == "2h 04m")
		#expect(FilmFacts.runtime(120) == "2h 00m")
		#expect(FilmFacts.runtime(58) == "58m")
		#expect(FilmFacts.runtime(0) == nil)
		#expect(FilmFacts.runtime(nil) == nil)
	}

	@Test func releaseDateIsSpelledOut() {
		#expect(FilmFacts.releaseDate("2015-06-24", locale: british) == "24 June 2015")
		#expect(FilmFacts.releaseDate("", locale: british) == nil)
		#expect(FilmFacts.releaseDate("June 2015", locale: british) == nil)
	}

	@Test func theTMDbAverageBecomesHalfStars() {
		#expect(FilmFacts.stars(outOf10: 8.1) == [.full, .full, .full, .full, .empty])
		#expect(FilmFacts.stars(outOf10: 7.3) == [.full, .full, .full, .half, .empty])
		#expect(FilmFacts.stars(outOf10: 0) == Array(repeating: .empty, count: 5))
		#expect(FilmFacts.stars(outOf10: 12) == Array(repeating: .full, count: 5))
	}

	@Test func countsGenresAndDates() {
		#expect(FilmFacts.count(3072, locale: british) == "3,072")
		#expect(FilmFacts.count(0) == nil)
		#expect(FilmFacts.genres("Drama, Thriller") == "Drama · Thriller")
		#expect(FilmFacts.genres("") == "")
		let august2 = Date(timeIntervalSince1970: 1_785_672_000)   // 2 Aug 2026, midday UTC
		#expect(FilmFacts.shortDate(august2, locale: british) == "2 Aug 2026")
	}
}
