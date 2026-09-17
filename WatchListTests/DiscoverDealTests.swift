//
//  DiscoverDealTests.swift
//  WatchListTests
//
//  Discover's deal, as the iPhone and the watch both work it out: More like
//  narrowing it to one title, waiting for the next title's suggestions after
//  moving on, and a swipe on the watch's smaller card.
//

import Foundation
import Testing
@testable import WatchList

@MainActor
struct DiscoverDealTests {

	/// A seed as the watch has one: no model behind it.
	private struct Seed: SuggestionSeed {
		let id = UUID()
		var kind: MediaKind = .show
		var tmdbID: Int? = 1
	}

	private func suggestion(_ kind: MediaKind, _ tmdbID: Int, genres: [String] = []) -> Suggestion {
		Suggestion(kind: kind, tmdbID: tmdbID, title: "Title \(tmdbID)", year: nil, posterURL: "",
		           averageScore: nil, genres: genres)
	}

	@Test func moreLikeDealsFromTheOneTitleWhileItFitsTheType() {
		let show = Seed(kind: .show), film = Seed(kind: .film)
		let fromShow = suggestion(.show, 10), fromFilm = suggestion(.film, 20)
		func deal(_ filter: DiscoverFilter) -> DiscoverDeal<Seed> {
			DiscoverDeal(seeds: [show, film], filter: filter, rotation: DiscoverRotation(),
			             similar: [show.id: [fromShow], film.id: [fromFilm]], fetched: [show.id, film.id],
			             excluded: [], putOff: [:])
		}

		let everything = deal(DiscoverFilter())
		#expect(everything.queue.map(\.id) == [fromShow.id, fromFilm.id])
		#expect(everything.picked == nil)

		let moreLikeFilm = deal(DiscoverFilter(seed: film.id))
		#expect(moreLikeFilm.picked?.id == film.id)
		#expect(moreLikeFilm.current?.id == fromFilm.id)
		#expect(moreLikeFilm.ordered.map(\.id) == [film.id])

		// Films only: the show isn't a seed, so More like on it narrows nothing.
		let filmsLikeShow = deal(DiscoverFilter(kind: .films, seed: show.id))
		#expect(filmsLikeShow.picked == nil)
		#expect(filmsLikeShow.seeds.map(\.id) == [film.id])
		#expect(filmsLikeShow.current?.id == fromFilm.id)
	}

	@Test func movingOnWaitsForTheNextTitlesSuggestions() {
		let first = Seed(), next = Seed()
		let leftOver = suggestion(.show, 10), fromNext = suggestion(.show, 20)
		var rotation = DiscoverRotation()
		for _ in 0..<5 { rotation.record(.notInterested, from: first.id) }

		func deal(similar: [UUID: [Suggestion]], fetched: Set<UUID>) -> DiscoverDeal<Seed> {
			DiscoverDeal(seeds: [first, next], filter: DiscoverFilter(), rotation: rotation,
			             similar: similar, fetched: fetched, excluded: [], putOff: [:])
		}

		// The first title is passed and the next isn't fetched: no card rather
		// than the passed title's again.
		let waiting = deal(similar: [first.id: [leftOver]], fetched: [first.id])
		#expect(waiting.seedOrder == [next.id, first.id])
		#expect(waiting.current == nil)
		#expect(waiting.ordered.map(\.id) == [next.id, first.id])

		let arrived = deal(similar: [first.id: [leftOver], next.id: [fromNext]], fetched: [first.id, next.id])
		#expect(arrived.current?.id == fromNext.id)

		// Fetched with nothing to offer: the passed title's card is better than none.
		let empty = deal(similar: [first.id: [leftOver], next.id: []], fetched: [first.id, next.id])
		#expect(empty.current?.id == leftOver.id)
	}

	@Test func whatsReadySkipsTheExcludedAndThePutOff() {
		let seed = Seed()
		let owned = suggestion(.show, 1), later = suggestion(.show, 2), fresh = suggestion(.show, 3)
		let deal = DiscoverDeal(seeds: [seed], filter: DiscoverFilter(), rotation: DiscoverRotation(),
		                        similar: [seed.id: [owned, later, fresh]], fetched: [seed.id],
		                        excluded: [owned.id], putOff: [later.id: .now])
		#expect(deal.queue.map(\.id) == [fresh.id, later.id])
		#expect(deal.skipped == [owned.id, later.id])
		#expect(deal.ready == 1)
	}

	@Test func aSmallerCardDecidesOverAShorterSwipe() {
		let flick = CGSize(width: 40, height: 4)
		#expect(CardDecision.forSwipe(translation: flick, predictedEnd: flick) == nil)
		#expect(CardDecision.forSwipe(translation: flick, predictedEnd: flick, threshold: 36) == .add)
		// A quarter of the threshold still has to be moved, not just flung.
		#expect(CardDecision.forSwipe(translation: CGSize(width: 0, height: -8),
		                              predictedEnd: CGSize(width: 0, height: -60), threshold: 36) == nil)
		#expect(CardDecision.forSwipe(translation: CGSize(width: 0, height: -10),
		                              predictedEnd: CGSize(width: 0, height: -60), threshold: 36) == .later)
		#expect(CardDecision.leaning(CGSize(width: -18, height: 0), threshold: 36)?.progress == 0.5)
	}
}
