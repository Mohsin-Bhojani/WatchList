//
//  ArtworkPickerTests.swift
//  WatchListTests
//
//  Choosing a title's artwork: which gallery images suit which slot, the size
//  each is saved at, and what a pick writes to the title.
//

import Foundation
import Testing
@testable import WatchList

@MainActor
struct ArtworkPickerTests {

	private func entry(_ path: String, _ kind: ImageEntry.Kind) -> ImageEntry {
		ImageEntry(id: path, kind: kind, thumbURL: "", fullURL: "", width: 1920, height: 1080,
		           language: nil, voteAverage: 0)
	}

	@Test func eachSlotTakesTheShapeThatSuitsIt() {
		#expect(ArtworkSlot.poster.fits(.poster))
		#expect(!ArtworkSlot.poster.fits(.backdrop))
		#expect(ArtworkSlot.landscape.fits(.backdrop))
		#expect(ArtworkSlot.landscape.fits(.still))
		// A logo is neither.
		#expect(!ArtworkSlot.poster.fits(.logo) && !ArtworkSlot.landscape.fits(.logo))
	}

	@Test func aPickIsSavedAtTheSizeAnImportSavesIt() {
		#expect(ArtworkSlot.poster.url(for: entry("/p.jpg", .poster)) == TMDbConfig.poster("/p.jpg"))
		#expect(ArtworkSlot.landscape.url(for: entry("/b.jpg", .backdrop)) == TMDbConfig.backdrop("/b.jpg"))
	}

	@Test func choosingWritesToTheTitleAndIsRemembered() {
		let show = Show(title: "Chosen", posterURL: "old-poster", backdropURL: "old-backdrop")
		let target = ArtworkTarget(id: show.id,
		                           current: [.poster: show.posterURL, .landscape: show.backdropURL],
		                           apply: [.poster: { show.posterURL = $0 },
		                                   .landscape: { show.backdropURL = $0 }])
		#expect(target.slots == [.poster, .landscape])

		target.choose(entry("/new-backdrop.jpg", .backdrop), as: .landscape)
		#expect(show.backdropURL == TMDbConfig.backdrop("/new-backdrop.jpg"))
		#expect(show.posterURL == "old-poster")
		#expect(ArtworkChoice.chosen(.landscape, for: show.id))
		#expect(!ArtworkChoice.chosen(.poster, for: show.id))

		ArtworkChoice.forget(.landscape, for: show.id)
		#expect(!ArtworkChoice.chosen(.landscape, for: show.id))
	}

	@Test func aSeasonTakesAPosterAndAnEpisodeALandscape() {
		let season = Season(seasonNumber: 2)
		let seasonTarget = ArtworkTarget(id: season.id, current: [.poster: season.posterURL],
		                                 apply: [.poster: { season.posterURL = $0 }])
		#expect(seasonTarget.slots == [.poster])

		let episode = Episode(episodeNumber: 1, seasonNumber: 2, title: "One")
		let episodeTarget = ArtworkTarget(id: episode.id, current: [.landscape: episode.stillURL],
		                                  apply: [.landscape: { episode.stillURL = $0 }])
		#expect(episodeTarget.slots == [.landscape])
		// Nothing to apply for the slot it hasn't: the pick is ignored.
		episodeTarget.choose(entry("/p.jpg", .poster), as: .poster)
		#expect(episode.stillURL.isEmpty)
	}
}
