//
//  FranchiseLoader.swift
//  WatchList
//
//  Asks TMDb which series your films are in, for the ones added before films
//  kept that. New films learn it when they're added (ImportCoordinator); these
//  are looked up a few at a time, once each, when the Collections tab opens.
//

import Foundation
import WatchListCore
import WatchListLibrary

@MainActor
enum FranchiseLoader {
	/// Most films looked up at one opening of the tab, so a big library fills
	/// in over a few visits instead of a burst of requests.
	static let batch = 40

	private static var running = false

	/// Looks up the films that haven't been, one after another. A film TMDb
	/// can't answer for is left to try again next time.
	static func backfill(_ films: [Film]) async {
		guard !running, TMDbConfig.isConfigured else { return }
		running = true
		defer { running = false }
		for film in films.filter(\.needsFranchiseCheck).prefix(batch) {
			guard !Task.isCancelled, let id = film.tmdbID else { return }
			guard let movie = try? await TMDbService.shared.movie(id: id) else { continue }
			film.setFranchise(from: movie)
		}
	}

	/// The films of one series, cached for the session.
	private static var series: [Int: TMDbCollection] = [:]

	static func collection(id: Int) async -> TMDbCollection? {
		if let cached = series[id] { return cached }
		guard let fetched = try? await TMDbService.shared.collection(id: id) else { return nil }
		series[id] = fetched
		return fetched
	}
}
