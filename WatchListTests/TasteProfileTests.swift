//
//  TasteProfileTests.swift
//  WatchListTests
//
//  How the library's verdicts and aspects become a score for a suggestion.
//

import Foundation
import Testing
@testable import WatchList

@MainActor
struct TasteProfileTests {

	private func sample(_ genres: [String], _ rating: Rating?, liked: [String] = [], disliked: [String] = []) -> TasteSample {
		TasteSample(genres: Similarity.genreSet(genres), rating: rating,
		            aspects: AspectTaste(liked: liked, disliked: disliked))
	}

	private func suggestion(_ genres: [String]) -> Suggestion {
		Suggestion(kind: .film, tmdbID: 1, title: "S", year: nil, posterURL: "p.jpg", averageScore: nil, genres: genres)
	}

	@Test func anEmptyLibraryHasNoViewOnAnything() {
		let profile = TasteProfile([TasteSample]())
		#expect(profile.score(suggestion(["Romance"])) == 50)
		#expect(profile.strongestGenre(for: suggestion(["Romance"])) == nil)
	}

	@Test func verdictsPullGenresUpOrDown() {
		let profile = TasteProfile([sample(["Romance"], .perfection), sample(["Horror"], .skip)])
		#expect(profile.score(suggestion(["Romance"])) > 50)
		#expect(profile.score(suggestion(["Horror"])) < 50)
		#expect(profile.score(suggestion(["Western"])) == 50)
	}

	@Test func oneTitleDoesntDecideAGenreButSeveralDo() {
		let one = TasteProfile([sample(["Drama"], .perfection)])
		let many = TasteProfile((0..<6).map { _ in sample(["Drama"], .perfection) })
		#expect(one.affinity(for: suggestion(["Drama"])) < many.affinity(for: suggestion(["Drama"])))
		#expect(many.affinity(for: suggestion(["Drama"])) < 1)
	}

	@Test func aTitleWithNoVerdictSaysNothing() {
		let profile = TasteProfile([sample(["Drama"], nil)])
		#expect(profile.genreAffinity.isEmpty)
	}

	@Test func dislikedAspectsWeakenALovedTitle() {
		let plain = TasteProfile([sample(["Drama"], .perfection)])
		let marked = TasteProfile([sample(["Drama"], .perfection, liked: ["Acting"], disliked: ["Ending", "Pacing"])])
		#expect(marked.affinity(for: suggestion(["Drama"])) < plain.affinity(for: suggestion(["Drama"])))
	}

	@Test func likingRomanceLeansTowardTheGenreEvenOnAnotherGenresTitle() {
		let profile = TasteProfile([sample(["Drama"], .goForIt, liked: ["Romance"])])
		#expect(profile.score(suggestion(["Romance"])) > 50)
		let against = TasteProfile([sample(["Drama"], .goForIt, disliked: ["Romance"])])
		#expect(against.score(suggestion(["Romance"])) < 50)
	}

	@Test func tvAndFilmGenreNamesLineUp() {
		let profile = TasteProfile([sample(["Sci-Fi & Fantasy"], .perfection)])
		#expect(profile.score(suggestion(["Science Fiction"])) > 50)
	}

	@Test func theStrongestGenreIsTheOneThatMovesTheScoreMost() {
		let profile = TasteProfile([sample(["Romance"], .perfection), sample(["Romance"], .perfection),
		                            sample(["Comedy"], .timepass)])
		let strongest = profile.strongestGenre(for: suggestion(["Comedy", "Romance"]))
		#expect(strongest?.genre == "romance")
		#expect((strongest?.affinity ?? 0) > 0)
	}

	@Test func rankingFavoursTasteAndKeepsTMDbsOrderForTies() {
		let profile = TasteProfile([sample(["Romance"], .perfection), sample(["Horror"], .skip)])
		let horror = suggestion(["Horror"]), western = suggestion(["Western"]), other = suggestion(["Mystery"])
		let romance = suggestion(["Romance"])
		let ranked = profile.ranked([horror, western, other, romance])
		#expect(ranked.map(\.genres) == [["Romance"], ["Western"], ["Mystery"], ["Horror"]])
	}
}
