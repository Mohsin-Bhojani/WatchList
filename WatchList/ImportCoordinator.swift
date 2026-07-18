//
//  ImportCoordinator.swift
//  WatchList
//
//  Turns a pasted IMDb link (or a TMDb search pick) into fully-populated
//  SwiftData models: a Film, or a Show with all of its Seasons & Episodes.
//
//  Trivia is intentionally NOT fetched here — it is scraped lazily the first
//  time the user opens a Film or Episode page, so importing stays fast.
//

import Foundation
import SwiftData
import Combine

@MainActor
final class ImportCoordinator: ObservableObject {
	enum Phase: Equatable {
		case idle
		case resolving
		case fetchingDetails
		case fetchingEpisodes(done: Int, total: Int)
		case done
		case failed(String)
	}

	@Published var phase: Phase = .idle

	var isWorking: Bool {
		switch phase {
		case .idle, .done, .failed: return false
		default: return true
		}
	}

	/// Import from a pasted IMDb URL or raw id. Inserts the result into `context`.
	/// Returns the created Film or Show on success.
	@discardableResult
	func importFromIMDb(_ raw: String, into context: ModelContext) async -> Any? {
		guard let imdbID = IMDb.id(from: raw) else {
			phase = .failed("That doesn't look like an IMDb link. Expected something like https://www.imdb.com/title/tt0468569/")
			return nil
		}
		guard TMDbConfig.isConfigured else {
			phase = .failed(TMDbError.notConfigured.localizedDescription)
			return nil
		}

		do {
			phase = .resolving
			let find = try await TMDbService.shared.find(imdbID: imdbID)

			if let tv = find.tv_results.first {
				return try await importShow(tmdbID: tv.id, imdbID: imdbID, into: context)
			} else if let movie = find.movie_results.first {
				return try await importFilm(tmdbID: movie.id, imdbID: imdbID, into: context)
			} else {
				phase = .failed("No TMDb match for \(imdbID).")
				return nil
			}
		} catch {
			phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
			return nil
		}
	}

	/// Import directly from a TMDb search pick.
	@discardableResult
	func importFromTMDb(id: Int, kind: MediaKind, into context: ModelContext) async -> Any? {
		guard TMDbConfig.isConfigured else {
			phase = .failed(TMDbError.notConfigured.localizedDescription)
			return nil
		}
		do {
			switch kind {
			case .show: return try await importShow(tmdbID: id, imdbID: nil, into: context)
			case .film: return try await importFilm(tmdbID: id, imdbID: nil, into: context)
			}
		} catch {
			phase = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
			return nil
		}
	}

	// MARK: - Film

	private func importFilm(tmdbID: Int, imdbID: String?, into context: ModelContext) async throws -> Film {
		phase = .fetchingDetails
		let m = try await TMDbService.shared.movie(id: tmdbID)
		let film = Film(
			title: m.title ?? "Untitled",
			synopsis: m.overview ?? "",
			genre: (m.genres ?? []).compactMap { $0.name }.joined(separator: ", "),
			year: String((m.release_date ?? "").prefix(4)),
			posterURL: TMDbConfig.poster(m.poster_path),
			backdropURL: TMDbConfig.backdrop(m.backdrop_path),
			imdbID: m.external_ids?.imdb_id ?? imdbID,
			tmdbID: m.id,
			specs: TechSpecs(movie: m)
		)
		context.insert(film)
		phase = .done
		return film
	}

	// MARK: - Show (+ seasons + episodes)

	private func importShow(tmdbID: Int, imdbID: String?, into context: ModelContext) async throws -> Show {
		phase = .fetchingDetails
		let tv = try await TMDbService.shared.tv(id: tmdbID)

		let show = Show(
			title: tv.name ?? "Untitled",
			overview: tv.overview ?? "",
			genre: (tv.genres ?? []).compactMap { $0.name }.joined(separator: ", "),
			firstAirYear: String((tv.first_air_date ?? "").prefix(4)),
			posterURL: TMDbConfig.poster(tv.poster_path),
			backdropURL: TMDbConfig.backdrop(tv.backdrop_path),
			imdbID: tv.external_ids?.imdb_id ?? imdbID,
			tmdbID: tv.id
		)
		context.insert(show)

		// Skip "Season 0" (specials) unless it's the only one.
		let seasonNumbers = (tv.seasons ?? [])
			.map { $0.season_number }
			.filter { $0 > 0 }
			.sorted()
		let total = seasonNumbers.count

		for (idx, number) in seasonNumbers.enumerated() {
			phase = .fetchingEpisodes(done: idx, total: total)
			guard let detail = try? await TMDbService.shared.season(tvID: tmdbID, seasonNumber: number) else { continue }

			let season = Season(
				seasonNumber: number,
				name: detail.name ?? "Season \(number)",
				overview: detail.overview ?? "",
				posterURL: TMDbConfig.poster(detail.poster_path),
				airYear: String((detail.air_date ?? "").prefix(4))
			)
			season.show = show
			context.insert(season)

			for e in (detail.episodes ?? []) {
				let episode = Episode(
					episodeNumber: e.episode_number,
					seasonNumber: number,
					title: e.name ?? "Episode \(e.episode_number)",
					synopsis: e.overview ?? "",
					stillURL: TMDbConfig.still(e.still_path),
					airDate: e.air_date ?? "",
					runtimeMinutes: e.runtime,
					specs: TechSpecs(episode: e, tv: tv),
					tmdbShowID: tmdbID
				)
				episode.season = season
				context.insert(episode)
			}
		}

		phase = .done
		return show
	}
}
