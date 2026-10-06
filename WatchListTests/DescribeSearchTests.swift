//
//  DescribeSearchTests.swift
//  WatchListTests
//
//  Describe's word list, which reads a sentence where Apple's on-device model
//  isn't there, how a model's answer is made safe, and the filter that carries
//  a description.
//

import Foundation
import Testing
@testable import WatchList

@MainActor
struct DescribeSearchTests {

	private let genres = ["Action", "Adventure", "Comedy", "Drama", "Horror", "Romance", "Science Fiction", "Thriller"]

	@Test func aRomanticAskWithNoSadEndingWantsRomanceAndAHappyEnding() {
		let query = WordListInterpreter.interpret("I wanna watch something romantic that doesn't have a sad ending",
		                                          genreNames: genres)
		#expect(query.genres == ["Romance"])
		#expect(query.ending == .happy)
		#expect(query.keywords == ["happy ending"])
		#expect(query.avoidGenres.isEmpty)
	}

	@Test func aPhonesCurlyApostropheStillNegates() {
		let query = WordListInterpreter.interpret("something romantic that doesn\u{2019}t have a sad ending",
		                                          genreNames: genres)
		#expect(query.ending == .happy)
	}

	@Test func sadIsAnEndingNotAGenre() {
		let query = WordListInterpreter.interpret("a sad movie", genreNames: genres)
		#expect(query.genres.isEmpty)
		#expect(query.kind == .film)
	}

	@Test func aNegatedGenreIsAvoided() {
		let query = WordListInterpreter.interpret("something funny but not scary", genreNames: genres)
		#expect(query.genres == ["Comedy"])
		#expect(query.avoidGenres == ["Horror"])
	}

	@Test func theTypeIsReadFromItsWords() {
		#expect(WordListInterpreter.interpret("a tense thriller series", genreNames: genres).kind == .show)
		#expect(WordListInterpreter.interpret("a tense thriller", genreNames: genres).kind == nil)
	}

	@Test func genresTMDbDoesntHaveAreNotAsked() {
		let query = WordListInterpreter.interpret("a documentary", genreNames: genres)
		#expect(query.genres.isEmpty)
	}

	@Test func aTvGenreNameStillFindsItsFilmEquivalent() {
		let query = WordListInterpreter.interpret("some space opera", genreNames: ["Sci-Fi & Fantasy"])
		#expect(query.genres == ["Science Fiction"])
	}

	@Test func aModelsAnswerKeepsOnlyRealGenresAndReadsItsWords() {
		let query = WordListInterpreter.sanitized(genres: ["romance", "Cozy", "Comedy", "Drama", "Action"],
		                                          avoid: ["Horror", "Romance"], keywords: [" Feel-Good ", ""],
		                                          kind: "Film", ending: "happy", genreNames: genres)
		#expect(query.genres == ["Romance", "Comedy", "Drama"])
		#expect(query.avoidGenres == ["Horror"])
		#expect(query.keywords == ["feel-good", "happy ending"])
		#expect(query.kind == .film)
		#expect(query.ending == .happy)
		#expect(WordListInterpreter.sanitized(genres: [], avoid: [], keywords: [], kind: "either", ending: "any",
		                                      genreNames: genres).isEmpty)
	}

	@Test func theSummaryNamesWhatWasRead() {
		var query = DescribedQuery()
		query.genres = ["Romance"]
		query.ending = .happy
		query.avoidGenres = ["Horror"]
		#expect(query.summary == "Romance \u{00B7} happy ending \u{00B7} not Horror")
	}

	@Test func aDescriptionNarrowsTheFilterAndResetsWithIt() {
		var filter = DiscoverFilter()
		#expect(filter.isDefault)
		filter.describe = "romantic"
		#expect(!filter.isDefault)
		#expect(filter.summary(seedTitle: nil) == "\u{201C}romantic\u{201D}")
		filter = DiscoverFilter()
		#expect(filter.isDefault)
	}
}
