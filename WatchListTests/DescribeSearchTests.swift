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
		                                          kind: "Film", ending: "happy", genreNames: genres,
		                                          text: "something romantic and feel-good, not scary")
		#expect(query.genres == ["Romance", "Comedy", "Drama"])
		#expect(query.avoidGenres == ["Horror"])
		#expect(query.keywords == ["feel-good", "happy ending"])
		#expect(query.kind == .film)
		#expect(query.ending == .happy)
		#expect(WordListInterpreter.sanitized(genres: [], avoid: [], keywords: [], kind: "either", ending: "any",
		                                      genreNames: genres, text: "anything").isEmpty)
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

	@Test func aModelsInventionsAreDroppedWhenTheSentenceDidntAskForThem() {
		// What the model made of "British lingo and royalty with modern business like in The Gentlemen":
		// an ending and genres to avoid that nobody asked for, and Action twice.
		let query = WordListInterpreter.sanitized(
			genres: ["Action", "Action & Adventure"], avoid: ["Drama", "Romance"], keywords: [], kind: "either",
			ending: "happy", genreNames: genres + ["Action & Adventure"],
			text: "British lingo and royalty with modern business like in The Gentlemen")
		#expect(query.genres == ["Action"])
		#expect(query.avoidGenres.isEmpty)
		#expect(query.ending == nil)
		#expect(query.keywords.isEmpty)
	}

	@Test func anEndingAndAvoidedGenresAreKeptWhenTheSentenceAsksForThem() {
		let query = WordListInterpreter.sanitized(
			genres: ["Comedy"], avoid: ["Horror"], keywords: [], kind: "either", ending: "happy", genreNames: genres,
			text: "something funny, not scary, that ends well and makes me feel good")
		#expect(query.avoidGenres == ["Horror"])
		#expect(query.ending == .happy)
	}

	// MARK: Titles named

	@Test func aTitleAfterLikeIsPickedOutOfTheSentence() {
		#expect(TitleReference.extract(from: "British lingo and royalty with modern business like in The Gentlemen")
			== ["The Gentlemen"])
		#expect(TitleReference.extract(from: "something similar to Succession, but funnier") == ["Succession"])
		#expect(TitleReference.extract(from: "a cozy mystery that reminds me of Only Murders in the Building")
			== ["Only Murders in the Building"])
		#expect(TitleReference.extract(from: "I want something like the gentlemen") == ["the gentlemen"])
	}

	@Test func likeWithoutATitleNamesNothing() {
		#expect(TitleReference.extract(from: "something like a cozy night in").isEmpty)
		#expect(TitleReference.extract(from: "a dislike of horror").isEmpty)
		#expect(TitleReference.extract(from: "something romantic").isEmpty)
		// A capital A after like is a title: A Quiet Place.
		#expect(TitleReference.extract(from: "something like A Quiet Place") == ["A Quiet Place"])
	}

	@Test func aTitleIsMatchedLooselyButNotLoosely() {
		#expect(TitleReference.isMatch(typed: "the gentlemen", title: "The Gentlemen"))
		#expect(TitleReference.isMatch(typed: "Gentlemen", title: "The Gentlemen"))
		#expect(TitleReference.isMatch(typed: "Only Murders in the Building", title: "Only Murders in the Building"))
		#expect(!TitleReference.isMatch(typed: "Gentle", title: "The Gentlemen"))
		#expect(!TitleReference.isMatch(typed: "a cozy night", title: "Cozy Night In: Part Two"))
	}

	@Test func aModelsTitleCountsOnlyIfTheSentenceHasIt() {
		let query = WordListInterpreter.sanitized(
			genres: ["Comedy"], avoid: [], keywords: [], similarTo: ["The Gentlemen", "Snatch"], kind: "either",
			ending: "any", genreNames: genres, text: "British lingo and royalty like in the gentlemen")
		#expect(query.references == ["The Gentlemen"])
	}

	@Test func theSummaryNamesTheTitlesToo() {
		var query = DescribedQuery()
		query.genres = ["Comedy"]
		query.references = ["The Gentlemen"]
		#expect(query.summary == "Comedy \u{00B7} like The Gentlemen")
		#expect(!query.isEmpty)
	}

	// MARK: Endings

	@Test func aWantedEndingLeavesOutTheOppositeAndKeepsWhatIsntKnown() {
		#expect(EndingFit.rank(wanted: .happy, judged: .happy) == 0)
		#expect(EndingFit.rank(wanted: .happy, judged: nil) == 1)
		#expect(EndingFit.rank(wanted: .happy, judged: .bittersweet) == 1)
		#expect(EndingFit.rank(wanted: .happy, judged: .sad) == nil)
		#expect(EndingFit.rank(wanted: .sad, judged: .happy) == nil)
		#expect(EndingFit.rank(wanted: .bittersweet, judged: .sad) == 2)
		#expect(EndingFit.rank(wanted: .open, judged: .open) == 0)
	}

	private func suggestion(_ id: Int) -> Suggestion {
		Suggestion(kind: .film, tmdbID: id, title: "Film \(id)", year: nil, posterURL: "p.jpg", averageScore: nil,
		           genres: ["Romance"], overview: "A love story.")
	}

	@Test func judgedEndingsDropTheWrongOnesAndPutTheRightOnesFirst() async {
		let session = DescribeSession()
		var query = DescribedQuery()
		query.ending = .happy
		session.setForTesting(candidates: (1...4).map(suggestion), query: query)
		let feelings: [Int: EndingFeel] = [1: .sad, 2: .bittersweet, 3: .happy]
		session.judge = { feelings[$0.tmdbID] }

		// Before anything's judged, every candidate stays, in the taste's order.
		#expect(session.results.map(\.tmdbID) == [1, 2, 3, 4])
		await session.judgeEndings(wanted: .happy)
		// 1 is sad, so it's out; 3 reads happy, so it's first; 2 and 4 follow.
		#expect(session.results.map(\.tmdbID) == [3, 2, 4])
		#expect(session.endingNote(for: suggestion(3)) == "reads as a happy ending")
		#expect(session.endingNote(for: suggestion(4)) == nil)
	}

	@Test func noEndingAskedForJudgesNothing() async {
		let session = DescribeSession()
		session.setForTesting(candidates: [suggestion(1), suggestion(2)], query: DescribedQuery())
		session.judge = { _ in Issue.record("judged without being asked"); return .sad }
		await session.judgeEndings(wanted: nil)
		#expect(session.results.map(\.tmdbID) == [1, 2])
	}
}
