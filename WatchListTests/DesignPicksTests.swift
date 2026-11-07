//
//  DesignPicksTests.swift
//  WatchListTests
//
//  The decisions behind the alternatives picked for the app: which way to
//  watch goes first, what the verdict summary says, and how money reads.
//

import Foundation
import Testing
@testable import WatchList
@testable import WatchListCore
@testable import WatchListLibrary

@MainActor
struct BestWayToWatchTests {

	private func availability() -> TitleExtras.Availability {
		TitleExtras.Availability(offers: [
			.init(kind: .stream, services: [.init(id: 1, name: "First", logoURL: ""), .init(id: 2, name: "Yours", logoURL: "")]),
			.init(kind: .buy, services: [.init(id: 3, name: "Shop", logoURL: "")]),
		], link: nil)
	}

	@Test func yourServiceComesFirstWhenItHasIt() {
		let best = TitleExtras.best(availability(), yours: [9, 2])
		#expect(best?.service.name == "Yours")
		#expect(best?.kind == .stream)
	}

	@Test func elseTMDbsFirstOffer() {
		#expect(TitleExtras.best(availability(), yours: [])?.service.name == "First")
		#expect(TitleExtras.best(availability(), yours: [3])?.service.name == "First")   // buying isn't watching yours
	}

	@Test func nothingWithoutOffers() {
		#expect(TitleExtras.best(.init(offers: [], link: nil), yours: [1]) == nil)
	}
}

@MainActor
struct VerdictSentenceTests {

	private func counts(_ values: [Rating: Int]) -> [ProfileFeed.VerdictCount] {
		Rating.allCases.map { ProfileFeed.VerdictCount(rating: $0, count: values[$0] ?? 0) }
	}

	@Test func whatTheVerdictsComeTo() {
		#expect(VerdictSummaryCard.sentence(for: counts([:])).hasPrefix("Rate what you watch"))
		#expect(VerdictSummaryCard.sentence(for: counts([.perfection: 1, .goForIt: 1])) == "You've loved everything you've rated so far.")
		#expect(VerdictSummaryCard.sentence(for: counts([.timepass: 3, .goForIt: 1])) == "Most of what you rate, you call Timepass.")
		#expect(VerdictSummaryCard.sentence(for: counts([.skip: 3, .goForIt: 1])).hasPrefix("You're hard to please"))
	}

	@Test func theBreakdownInWords() {
		#expect(VerdictSummaryCard.breakdown(for: counts([.perfection: 1, .goForIt: 1]))
		        == "1 Perfection and 1 Go For It, from 2 rated titles.")
	}
}

@MainActor
struct MoneyTests {
	@Test func readsShort() {
		#expect(PhoneFilmDetailView.money(30_000_000) == "$30M")
		#expect(PhoneFilmDetailView.money(84_900_000) == "$84.9M")
		#expect(PhoneFilmDetailView.money(1_200_000_000) == "$1.2B")
		#expect(PhoneFilmDetailView.money(900_000) == "$900K")
	}
}

@MainActor
struct EpisodeNameTests {
	private func episode(_ title: String) -> Episode {
		Episode(episodeNumber: 2, seasonNumber: 2, title: title)
	}

	@Test func aNameThatIsOnlyTheCodeIsDropped() {
		#expect(ShowFacts.distinctName(episode("S2E2")) == nil)
		#expect(ShowFacts.distinctName(episode("s2 e2")) == nil)
	}

	@Test func aRealNameIsKept() {
		#expect(ShowFacts.distinctName(episode("Goodbye, Mrs. Selvig")) == "Goodbye, Mrs. Selvig")
	}

	@Test func noNameFallsBackToItsNumber() {
		#expect(ShowFacts.distinctName(episode("")) == "Episode 2")
	}
}
