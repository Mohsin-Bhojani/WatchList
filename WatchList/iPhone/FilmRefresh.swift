//
//  FilmRefresh.swift
//  WatchList
//
//  Refresh metadata, from a film page's menu: fetches the film from TMDb again
//  and takes whatever has changed there — title, synopsis, genres, year, the
//  poster and landscape artwork, and the facts in its specs (runtime, release
//  date, TMDb's rating). Your own side of it — status, verdict, stars, note,
//  watched date — is never touched, and a poster or landscape you picked by
//  hand from the Artwork sheet (ArtworkChoice) stays.
//
//  Only fields Film already has are written, so the library store is untouched.
//

import Foundation

enum FilmRefresh {
	enum Outcome: Equatable {
		/// What changed, in the words the alert lists them in.
		case updated([String])
		case upToDate
		case failed
		/// Added by hand, with no TMDb id to look it up by.
		case notOnTMDb

		var message: String {
			switch self {
			case .updated(let changes): return "Updated " + ListFormatter.localizedString(byJoining: changes) + "."
			case .upToDate: return "Everything's up to date."
			case .failed: return "Couldn't reach TMDb. Try again later."
			case .notOnTMDb: return "This film was added by hand, so there's nothing to refresh it from."
			}
		}
	}

	@MainActor
	static func refresh(_ film: Film) async -> Outcome {
		guard let tmdbID = film.tmdbID else { return .notOnTMDb }
		guard let movie = try? await TMDbService.shared.movie(id: tmdbID) else { return .failed }
		let changes = apply(movie, to: film,
		                    keepPoster: ArtworkChoice.chosen(.poster, for: film.id),
		                    keepLandscape: ArtworkChoice.chosen(.landscape, for: film.id))
		return changes.isEmpty ? .upToDate : .updated(changes)
	}

	/// Writes TMDb's current details over the film's, and names what changed.
	/// A field TMDb has gone blank on keeps what the film already has.
	@discardableResult
	static func apply(_ movie: TMDbMovie, to film: Film, keepPoster: Bool, keepLandscape: Bool) -> [String] {
		var changes: [String] = []
		func update(_ name: String, _ current: String, _ fresh: String, _ set: (String) -> Void) {
			guard !fresh.isEmpty, fresh != current else { return }
			set(fresh)
			changes.append(name)
		}

		update("title", film.title, movie.title ?? "") { film.title = $0 }
		update("synopsis", film.synopsis, movie.overview ?? "") { film.synopsis = $0 }
		update("genres", film.genre, (movie.genres ?? []).compactMap(\.name).joined(separator: ", ")) {
			film.genre = $0
		}
		update("year", film.year, String((movie.release_date ?? "").prefix(4))) { film.year = $0 }
		if !keepPoster {
			update("poster", film.posterURL, TMDbConfig.poster(movie.poster_path)) { film.posterURL = $0 }
		}
		if !keepLandscape {
			update("landscape artwork", film.backdropURL, TMDbConfig.backdrop(movie.backdrop_path)) {
				film.backdropURL = $0
			}
		}
		if film.imdbID == nil, let imdbID = movie.external_ids?.imdb_id, !imdbID.isEmpty {
			film.imdbID = imdbID
			changes.append("IMDb link")
		}

		var fresh = TechSpecs(movie: movie)
		let old = film.specs
		// Facts TMDb leaves out this time keep the ones the film had.
		fresh.runtimeMinutes = fresh.runtimeMinutes ?? old?.runtimeMinutes
		fresh.releaseDate = fresh.releaseDate ?? old?.releaseDate
		if fresh.voteAverage == nil {
			fresh.voteAverage = old?.voteAverage
			fresh.voteCount = old?.voteCount
		}
		fresh.imdbID = fresh.imdbID ?? old?.imdbID
		if fresh != old {
			if fresh.runtimeMinutes != old?.runtimeMinutes, fresh.runtimeMinutes != nil { changes.append("runtime") }
			if fresh.releaseDate != old?.releaseDate, fresh.releaseDate != nil { changes.append("release date") }
			if fresh.voteAverage != old?.voteAverage || fresh.voteCount != old?.voteCount {
				changes.append("TMDb rating")
			}
			film.specs = fresh
		}
		return changes
	}
}
