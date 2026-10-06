//
//  AspectTests.swift
//  WatchListTests
//
//  What stood out in a title: how a chip's taps move an aspect between liked
//  and disliked, and how a title keeps the two lists.
//

import Foundation
import Testing
@testable import WatchList

@MainActor
struct AspectTests {

	@Test func aTapCyclesUnmarkedLikedDislikedUnmarked() {
		var taste = AspectTaste()
		#expect(taste.state(of: .ending) == .unmarked)
		taste.cycle(.ending)
		#expect(taste.state(of: .ending) == .liked)
		taste.cycle(.ending)
		#expect(taste.state(of: .ending) == .disliked)
		taste.cycle(.ending)
		#expect(taste.state(of: .ending) == .unmarked)
		#expect(taste.isEmpty)
	}

	@Test func anAspectIsNeverLikedAndDisliked() {
		let taste = AspectTaste(liked: ["Story", "Mystery"], disliked: ["Story", "Pacing"])
		#expect(taste.state(of: .story) == .liked)
		#expect(taste.state(of: .pacing) == .disliked)
		// "Mystery" isn't an aspect (any more): dropped rather than failing the load.
		#expect(taste.likedNames == ["Story"])
	}

	@Test func namesComeOutInTheOrderTheAspectsAreListed() {
		var taste = AspectTaste()
		taste.cycle(.vibe)
		taste.cycle(.story)
		taste.cycle(.acting)
		#expect(taste.likedNames == ["Story", "Acting", "Vibe"])
	}

	@Test func aFilmKeepsWhatStoodOut() {
		let film = Film(title: "Before Sunrise")
		#expect(film.aspectTaste.isEmpty)
		var taste = film.aspectTaste
		taste.cycle(.romance)
		taste.cycle(.ending)
		taste.cycle(.ending)
		film.aspectTaste = taste
		#expect(film.likedAspects == ["Romance"])
		#expect(film.dislikedAspects == ["Ending"])
	}

	@Test func aShowKeepsWhatStoodOut() {
		let show = Show(title: "Severance")
		var taste = show.aspectTaste
		taste.cycle(.visuals)
		show.aspectTaste = taste
		#expect(show.aspectTaste.state(of: .visuals) == .liked)
	}
}
