//
//  TMDbService.swift
//  WatchList
//
//  Pulls synopsis, posters/stills, season & episode structure and technical
//  specs from The Movie Database (TMDb). Trivia is NOT available here — that
//  is scraped separately from IMDb (see IMDbTriviaService).
//
//  ⚠️ SETUP: paste your free TMDb v3 API key below. Get one at
//  https://www.themoviedb.org/settings/api
//

import Foundation

// MARK: - Config

enum TMDbConfig {
	/// 👉 Paste your free TMDb v3 API key here.
	static let apiKey = "4a3a809b918962381f1b77c5d5eb4b53"

	static var isConfigured: Bool { !apiKey.isEmpty && apiKey != "YOUR_TMDB_API_KEY" }

	static let apiBase = "https://api.themoviedb.org/3"
	static let imageBase = "https://image.tmdb.org/t/p"

	/// Full poster URL (2:3). Returns "" when there's no path.
	static func poster(_ path: String?) -> String { image(path, size: "w500") }
	static func backdrop(_ path: String?) -> String { image(path, size: "w780") }
	static func still(_ path: String?) -> String { image(path, size: "w300") }

	private static func image(_ path: String?, size: String) -> String {
		guard let path, !path.isEmpty else { return "" }
		return "\(imageBase)/\(size)\(path)"
	}
}

// MARK: - Errors

enum TMDbError: LocalizedError {
	case notConfigured
	case badURL
	case http(Int)
	case decoding

	var errorDescription: String? {
		switch self {
		case .notConfigured: return "Add your free TMDb API key in TMDbService.swift to enable automatic import."
		case .badURL:        return "Couldn't build the request URL."
		case .http(let c):   return "TMDb request failed (HTTP \(c))."
		case .decoding:      return "Couldn't read the response from TMDb."
		}
	}
}

// MARK: - DTOs

struct TMDbNamed: Decodable { let name: String? }
struct TMDbSpokenLanguage: Decodable { let english_name: String?; let name: String? }

struct TMDbExternalIDs: Decodable {
	let imdb_id: String?
}

struct TMDbFindResult: Decodable {
	let movie_results: [TMDbFindItem]
	let tv_results: [TMDbFindItem]
}

struct TMDbFindItem: Decodable {
	let id: Int
	let title: String?
	let name: String?
}

struct TMDbMovie: Decodable {
	let id: Int
	let title: String?
	let overview: String?
	let release_date: String?
	let poster_path: String?
	let backdrop_path: String?
	let runtime: Int?
	let status: String?
	let original_language: String?
	let budget: Int?
	let revenue: Int?
	let vote_average: Double?
	let vote_count: Int?
	let homepage: String?
	let genres: [TMDbNamed]?
	let spoken_languages: [TMDbSpokenLanguage]?
	let production_companies: [TMDbNamed]?
	let production_countries: [TMDbNamed]?
	let external_ids: TMDbExternalIDs?
}

struct TMDbTV: Decodable {
	let id: Int
	let name: String?
	let overview: String?
	let first_air_date: String?
	let poster_path: String?
	let backdrop_path: String?
	let status: String?
	let original_language: String?
	let vote_average: Double?
	let vote_count: Int?
	let homepage: String?
	let genres: [TMDbNamed]?
	let spoken_languages: [TMDbSpokenLanguage]?
	let production_companies: [TMDbNamed]?
	let production_countries: [TMDbNamed]?
	let seasons: [TMDbSeasonSummary]?
	let external_ids: TMDbExternalIDs?
}

struct TMDbSeasonSummary: Decodable {
	let season_number: Int
	let episode_count: Int?
	let name: String?
}

struct TMDbSeasonDetail: Decodable {
	let name: String?
	let overview: String?
	let poster_path: String?
	let air_date: String?
	let episodes: [TMDbEpisode]?
}

struct TMDbEpisode: Decodable {
	let id: Int?
	let episode_number: Int
	let season_number: Int?
	let name: String?
	let overview: String?
	let still_path: String?
	let air_date: String?
	let runtime: Int?
	let vote_average: Double?
	let vote_count: Int?
	let production_code: String?
}

struct TMDbSearchItem: Decodable, Identifiable {
	let id: Int
	let media_type: String?
	let title: String?
	let name: String?
	let poster_path: String?
	let release_date: String?
	let first_air_date: String?

	var displayTitle: String { title ?? name ?? "Untitled" }
}

struct TMDbSearchResponse: Decodable { let results: [TMDbSearchItem] }

// MARK: - Service

struct TMDbService {
	static let shared = TMDbService()
	private let session = URLSession.shared

	// MARK: Public API

	/// Resolve an IMDb id to TMDb movie/tv results.
	func find(imdbID: String) async throws -> TMDbFindResult {
		try await get("/find/\(imdbID)", query: ["external_source": "imdb_id"])
	}

	func movie(id: Int) async throws -> TMDbMovie {
		try await get("/movie/\(id)", query: ["append_to_response": "external_ids"])
	}

	func tv(id: Int) async throws -> TMDbTV {
		try await get("/tv/\(id)", query: ["append_to_response": "external_ids"])
	}

	func season(tvID: Int, seasonNumber: Int) async throws -> TMDbSeasonDetail {
		try await get("/tv/\(tvID)/season/\(seasonNumber)")
	}

	/// Resolve an episode's own IMDb id (episodes have their own trivia pages).
	func episodeIMDbID(tvID: Int, season: Int, episode: Int) async throws -> String? {
		let ids: TMDbExternalIDs = try await get("/tv/\(tvID)/season/\(season)/episode/\(episode)/external_ids")
		return ids.imdb_id
	}

	func multiSearch(query: String) async throws -> [TMDbSearchItem] {
		let response: TMDbSearchResponse = try await get("/search/multi", query: ["query": query])
		return response.results.filter { ($0.media_type == "movie" || $0.media_type == "tv") }
	}

	// MARK: Networking

	private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
		guard TMDbConfig.isConfigured else { throw TMDbError.notConfigured }

		var components = URLComponents(string: TMDbConfig.apiBase + path)
		var items = [URLQueryItem(name: "api_key", value: TMDbConfig.apiKey),
		             URLQueryItem(name: "language", value: "en-US")]
		for (k, v) in query { items.append(URLQueryItem(name: k, value: v)) }
		components?.queryItems = items
		guard let url = components?.url else { throw TMDbError.badURL }

		let (data, response) = try await session.data(from: url)
		guard let http = response as? HTTPURLResponse else { throw TMDbError.http(-1) }
		guard (200...299).contains(http.statusCode) else { throw TMDbError.http(http.statusCode) }

		do {
			return try JSONDecoder().decode(T.self, from: data)
		} catch {
			throw TMDbError.decoding
		}
	}
}

// MARK: - TechSpecs from TMDb

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
/*
 Multiple commands produce Target 'WatchList' (project 'WatchList') has copy command from '/Users/user/Desktop/Local Repo/WatchList/WatchList/Info.plist' to '/Users/user/Library/Developer/Xcode/DerivedData/WatchList-cssvgjmovlrqtpcukqfkeshionro/Build/Products/Debug-iphonesimulator/WatchList.app/Info.plist''/Users/user/Library/Developer/Xcode/DerivedData/WatchList-cssvgjmovlrqtpcukqfkeshionro/Build/Products/Debug-iphonesimulator/WatchList.app/Info.plist'
 Target 'WatchList' (project 'WatchList') has process command with output '/Users/user/Library/Developer/Xcode/DerivedData/WatchList-cssvgjmovlrqtpcukqfkeshionro/Build/Products/Debug-iphonesimulator/WatchList.app/Info.plist'
 */
