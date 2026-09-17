//
//  TechSpecsFromTMDb.swift
//  WatchList
//
//  Technical specs built from TMDb's film and episode payloads. Kept with the
//  iPhone app, beside the models, while the TMDb client itself is shared with
//  the watch app (Shared/TMDbService.swift).
//

import Foundation

extension TechSpecs {
	/// Build technical specs for a film from a TMDb movie payload.
	init(movie m: TMDbMovie) {
		self.init()
		runtimeMinutes = (m.runtime ?? 0) > 0 ? m.runtime : nil
		releaseDate = m.release_date
		status = m.status
		originalLanguage = m.original_language
		spokenLanguages = (m.spoken_languages ?? []).compactMap { $0.english_name ?? $0.name }
		productionCompanies = (m.production_companies ?? []).compactMap { $0.name }
		productionCountries = (m.production_countries ?? []).compactMap { $0.name }
		budget = (m.budget ?? 0) > 0 ? m.budget : nil
		revenue = (m.revenue ?? 0) > 0 ? m.revenue : nil
		voteAverage = m.vote_average
		voteCount = m.vote_count
		tmdbID = m.id
		imdbID = m.external_ids?.imdb_id
		homepage = m.homepage
	}

	/// Build technical specs for an episode, borrowing series-level facts (such
	/// as languages and production) from the parent show where the episode
	/// payload doesn't carry them.
	init(episode e: TMDbEpisode, tv: TMDbTV) {
		self.init()
		runtimeMinutes = (e.runtime ?? 0) > 0 ? e.runtime : nil
		releaseDate = e.air_date
		originalLanguage = tv.original_language
		spokenLanguages = (tv.spoken_languages ?? []).compactMap { $0.english_name ?? $0.name }
		productionCompanies = (tv.production_companies ?? []).compactMap { $0.name }
		productionCountries = (tv.production_countries ?? []).compactMap { $0.name }
		voteAverage = e.vote_average
		voteCount = e.vote_count
		productionCode = e.production_code
		tmdbID = e.id
	}
}
