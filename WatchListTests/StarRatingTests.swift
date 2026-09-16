//
//  StarRatingTests.swift
//  WatchListTests
//
//  The half-star scale beside the verdicts: which verdict a star rating means,
//  which stars a verdict means, how hand-picked stars survive a change of
//  verdict, and how a title keeps them.
//

import Foundation
import Testing
@testable import WatchList

@MainActor
struct StarRatingTests {

	@Test func starsPickTheVerdict() {
		let expected: [(Double, Rating)] = [
			(0, .skip), (0.5, .skip), (1, .skip), (1.5, .skip), (2, .skip),
			(2.5, .timepass), (3, .timepass), (3.5, .timepass),
			(4, .goForIt), (4.5, .goForIt),
			(5, .perfection),
		]
		for (stars, verdict) in expected {
			#expect(StarRating.verdict(for: stars) == verdict, "\(stars) stars")
		}
	}

	@Test func verdictsAssumeTheirStars() {
		#expect(StarRating.stars(for: .skip) == 1)
		#expect(StarRating.stars(for: .timepass) == 3)
		#expect(StarRating.stars(for: .goForIt) == 4)
		#expect(StarRating.stars(for: .perfection) == 5)
	}

	@Test func theScaleRunsFromZeroToFiveInHalves() {
		#expect(StarRating.values == [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5])
		#expect(StarRating.snapped(3.26) == 3.5)
		#expect(StarRating.snapped(-1) == 0)
		#expect(StarRating.snapped(7) == 5)
		#expect(StarRating.label(4.5) == "4.5")
		#expect(StarRating.label(4) == "4")
	}

	@Test func handPickedStarsShowWhileTheyFitTheVerdict() {
		#expect(StarRating.shown(explicit: 4.5, verdict: .goForIt) == 4.5)
		// The verdict was changed where stars aren't shown: its own stars win.
		#expect(StarRating.shown(explicit: 4.5, verdict: .skip) == 1)
		#expect(StarRating.shown(explicit: nil, verdict: .timepass) == 3)
		#expect(StarRating.shown(explicit: 2, verdict: nil) == nil)
	}

	@Test func choosingAVerdictKeepsOnlyStarsThatFitIt() {
		#expect(StarRating.explicit(4.5, afterChoosing: .goForIt) == 4.5)
		#expect(StarRating.explicit(4.5, afterChoosing: .perfection) == nil)
		#expect(StarRating.explicit(4.5, afterChoosing: nil) == nil)
		#expect(StarRating.explicit(nil, afterChoosing: .skip) == nil)
	}

	@Test func thePickerReadsHalvesFromWhereItsTouched() {
		// 28pt stars 6pt apart: the first spans 0–28, the second 34–62.
		func at(_ x: CGFloat) -> Double { StarRatingPicker.value(atX: x, size: 28, spacing: 6) }
		#expect(at(-5) == 0)
		#expect(at(0) == 0)
		#expect(at(10) == 0.5)
		#expect(at(20) == 1)
		#expect(at(31) == 1)       // the gap after the first star
		#expect(at(40) == 1.5)
		#expect(at(160) == 5)
		#expect(at(400) == 5)
	}

	@Test func aTitleKeepsOnlyStarsThatFitItsVerdict() {
		let film = Film(title: "Film", rating: .goForIt)
		film.stars = 4.5
		#expect(film.shownStars == 4.5)
		film.setVerdict(.goForIt)
		#expect(film.stars == 4.5)
		film.setVerdict(.skip)
		#expect(film.stars == nil)
		#expect(film.shownStars == 1)
		film.setVerdict(nil)
		#expect(film.shownStars == nil)
	}
}
