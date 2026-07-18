//
//  TriviaLoader.swift
//  WatchList
//
//  Lazily fetches IMDb trivia for a Film, Show or Episode the first time its
//  page is opened, then caches the result on the model so we don't re-scrape.
//

import Foundation
import SwiftData

enum TriviaLoader {

	/// Fetch trivia for a film (uses its stored IMDb id).
	@MainActor
	static func loadIfNeeded(for film: Film) async {
		guard !film.triviaFetched else { return }
		guard let imdbID = film.imdbID, !imdbID.isEmpty else { film.triviaFetched = true; return }
		let items = await IMDbTriviaService.shared.trivia(imdbID: imdbID)
		film.trivia = items
		film.triviaFetched = true
	}

	/// Fetch trivia for a show (series-level trivia page).
	@MainActor
	static func loadIfNeeded(for show: Show) async {
		guard !show.triviaFetched else { return }
		guard let imdbID = show.imdbID, !imdbID.isEmpty else { show.triviaFetched = true; return }
		let items = await IMDbTriviaService.shared.trivia(imdbID: imdbID)
		show.trivia = items
		show.triviaFetched = true
	}

	/// Fetch trivia for an episode. Resolves the episode's own IMDb id via TMDb
	/// first (episodes have their own trivia pages), if we don't have it yet.
	@MainActor
	static func loadIfNeeded(for episode: Episode) async {
		guard !episode.triviaFetched else { return }

		if episode.imdbID == nil || episode.imdbID?.isEmpty == true {
			if let showID = episode.tmdbShowID,
			   let resolved = try? await TMDbService.shared.episodeIMDbID(
					tvID: showID, season: episode.seasonNumber, episode: episode.episodeNumber) {
				episode.imdbID = resolved
			}
		}

		guard let imdbID = episode.imdbID, !imdbID.isEmpty else { episode.triviaFetched = true; return }
		let items = await IMDbTriviaService.shared.trivia(imdbID: imdbID)
		episode.trivia = items
		episode.triviaFetched = true
	}
}
