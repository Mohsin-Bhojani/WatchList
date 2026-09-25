//
//  CommunityTests.swift
//  WatchListTests
//
//  Everyone on WatchList: the rating that leads, the spread under it, how
//  your own rating is counted in, and how the gauge is sliced.
//

import Foundation
import Testing
@testable import WatchList

@MainActor
struct CommunityTests {

	private func opinion(_ counts: [String: Int], scale: CommunityScale = .verdict,
	                     yours: String? = nil) -> CommunityOpinion {
		CommunityOpinion(scale: scale, counts: counts, yours: yours)
	}

	@Test func theSpreadRunsBestRatingFirstWhicheverScale() {
		#expect(opinion([:]).spread.map(\.option) == ["Perfection", "Go For It", "Timepass", "Skip"])
		#expect(opinion([:], scale: .tier).spread.map(\.option) == ["Rewatch", "Watch", "Skip"])
		// Every rating is listed, whether or not anyone gave it.
		#expect(opinion(["Skip": 2]).spread.map(\.count) == [0, 0, 0, 2])
	}

	@Test func theHeadlineIsTheRatingMostPeopleGave() throws {
		let leading = try #require(opinion(["Go For It": 13, "Perfection": 5, "Skip": 3]).leading)
		#expect(leading.option == "Go For It")
		#expect((leading.share * 100).rounded() == 62)      // as the design has it: "62% Go for it"

		// A tie goes to the better rating.
		let tied = try #require(opinion(["Go For It": 3, "Perfection": 3]).leading)
		#expect(tied.option == "Perfection")

		// Nobody has rated it: no headline.
		#expect(opinion([:]).leading == nil)
	}

	@Test func sharesAreOutOfEveryoneWhoRatedIt() {
		let spread = opinion(["Perfection": 1, "Timepass": 3])
		#expect(spread.total == 4)
		#expect(spread.share(of: "Timepass") == 0.75)
		#expect(spread.share(of: "Skip") == 0)
		#expect(opinion([:]).share(of: "Skip") == 0)
	}

	@Test func yourRatingIsCountedLikeAnyoneElses() {
		let others = opinion(["Go For It": 2])
		let counted = others.counting(yours: "Perfection")
		#expect(counted.total == 3)
		#expect(counted.counts["Perfection"] == 1)
		#expect(counted.yours == "Perfection")
		// Yours joining a rating others gave adds to it.
		#expect(others.counting(yours: "Go For It").counts["Go For It"] == 3)
		// Nothing of your own: unchanged.
		#expect(others.counting(yours: nil) == others)
	}

	@Test func thisDeviceKnowsOnlyYou() async {
		let others = await ThisDeviceCommunity().others(for: .film(tmdbID: 1), scale: .verdict)
		#expect(others.isEmpty)

		let mine = await Community.opinion(for: .film(tmdbID: 1), scale: .verdict, yours: "Timepass")
		#expect(mine.total == 1)
		#expect(mine.leading?.option == "Timepass")
		#expect(mine.leading?.share == 1)

		let unrated = await Community.opinion(for: .show(tmdbID: 2), scale: .verdict, yours: nil)
		#expect(unrated.total == 0)
		#expect(unrated.leading == nil)
	}

	// MARK: Gauge

	@Test func theGaugeSplitsInScaleOrderAndFillsEndToEnd() {
		let segments = CommunityGauge.segments(opinion(["Skip": 1, "Perfection": 2, "Go For It": 1]))
		#expect(segments.map(\.option) == ["Perfection", "Go For It", "Skip"])
		#expect(segments.first?.from == 0)
		#expect(segments.last?.to == 1)
		// Half to Perfection, with a hairline before the next slice.
		#expect(abs((segments.first?.to ?? 0) - 0.496) < 0.0001)
		#expect(abs(segments[1].from - 0.504) < 0.0001)
	}

	@Test func aSingleRatingFillsTheWholeGauge() {
		let segments = CommunityGauge.segments(opinion(["Timepass": 1]))
		#expect(segments.count == 1)
		#expect(segments.first?.from == 0 && segments.first?.to == 1)
		#expect(CommunityGauge.segments(opinion([:])).isEmpty)
	}
}
