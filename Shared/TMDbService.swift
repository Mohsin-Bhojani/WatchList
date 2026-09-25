//
//  TMDbService.swift
//  WatchList
//
//  Pulls synopsis, posters/stills, season & episode structure, credits,
//  similar titles and technical specs from The Movie Database (TMDb).
//  Compiled into both the iPhone app and the watch app; each reads the key from
//  its own bundle. Turning TMDb's payloads into TechSpecs is iPhone-only, in
//  WatchList/TechSpecsFromTMDb.swift.
//
//  The API key is not stored here — see TMDbConfig below and README.md.

import Foundation

// MARK: - Config

enum TMDbConfig {
	/// The TMDb v3 API key. It is never stored in source: the build reads it
	/// from `Configuration/Secrets.xcconfig` (untracked — see README.md) and
	/// carries it into the generated Info.plist as `TMDBAPIKey`.
	///
	/// A `TMDB_API_KEY` environment variable wins when one is set, which is how
	/// a CI job or a one-off scheme override can supply a different key without
	/// touching the file.
	static let apiKey: String = {
		let environment = ProcessInfo.processInfo.environment["TMDB_API_KEY"] ?? ""
		if !environment.isEmpty { return environment }
		let bundled = Bundle.main.object(forInfoDictionaryKey: "TMDBAPIKey") as? String ?? ""
		return bundled.trimmingCharacters(in: .whitespacesAndNewlines)
	}()

	static var isConfigured: Bool { !apiKey.isEmpty }

	static let apiBase = "https://api.themoviedb.org/3"
	static let imageBase = "https://image.tmdb.org/t/p"

	/// Full poster URL (2:3). Returns "" when there's no path.
	static func poster(_ path: String?) -> String { image(path, size: "w500") }
	static func backdrop(_ path: String?) -> String { image(path, size: "w780") }
	static func still(_ path: String?) -> String { image(path, size: "w300") }
	/// Cast headshot (2:3). Small, because it's drawn as a 44pt circle.
	static func profile(_ path: String?) -> String { image(path, size: "w185") }
	/// A streaming service's square logo.
	static func logo(_ path: String?) -> String { image(path, size: "w92") }

	/// A tile in the Images tab. Deliberately small — a popular show has a few
	/// hundred of these and they are drawn barely 100pt wide.
	static func galleryThumb(_ path: String?) -> String { image(path, size: "w342") }

	/// What the full-screen viewer loads.
	static func fullSize(_ path: String?) -> String { image(path, size: "original") }

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
		case .notConfigured: return "No TMDb API key. Copy Configuration/Secrets.example.xcconfig to Secrets.xcconfig, add your key and rebuild — see README.md."
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

// MARK: - Credits DTOs

/// One character a person played, as returned by the `aggregate_credits`
/// endpoints. A person can hold several roles across a run of a show.
struct TMDbCreditRole: Decodable {
	let character: String?
	let episode_count: Int?
}

/// A cast member from `/aggregate_credits` — the only credits shape that
/// carries episode counts.
struct TMDbAggregateCastMember: Decodable {
	let id: Int
	let name: String?
	let profile_path: String?
	let total_episode_count: Int?
	let order: Int?
	let roles: [TMDbCreditRole]?
}

struct TMDbAggregateCredits: Decodable {
	let cast: [TMDbAggregateCastMember]?
}

/// A cast member from the plain `/credits` endpoints (episode level), which
/// bill by `order` and have no episode counts.
struct TMDbCastMember: Decodable {
	let id: Int
	let name: String?
	let character: String?
	let profile_path: String?
	let order: Int?
}

struct TMDbCrewMember: Decodable {
	let id: Int
	let name: String?
	let job: String?
	let department: String?
}

struct TMDbCredits: Decodable {
	let cast: [TMDbCastMember]?
	let crew: [TMDbCrewMember]?
	let guest_stars: [TMDbCastMember]?
}

// MARK: - Similar / genre DTOs

/// A title from `/tv/{id}/similar`. Note it carries `genre_ids`, not names —
/// see `TMDbService.tvGenres()` for the lookup table.
struct TMDbSimilarTV: Decodable {
	let id: Int
	let name: String?
	let first_air_date: String?
	let vote_average: Double?
	let poster_path: String?
	let genre_ids: [Int]?
}

struct TMDbSimilarResponse: Decodable { let results: [TMDbSimilarTV] }

/// A title from `/movie/{id}/similar`. The same payload as its TV counterpart
/// with `title` / `release_date` in place of `name` / `first_air_date`, and its
/// genre ids come from the movie table rather than the TV one.
struct TMDbSimilarMovie: Decodable {
	let id: Int
	let title: String?
	let release_date: String?
	let vote_average: Double?
	let poster_path: String?
	let genre_ids: [Int]?
}

struct TMDbSimilarMovieResponse: Decodable { let results: [TMDbSimilarMovie] }

struct TMDbGenre: Decodable {
	let id: Int
	let name: String?
}

struct TMDbGenreList: Decodable { let genres: [TMDbGenre] }

// MARK: - Image DTOs

/// One artwork file. `iso_639_1` is the language of any text burnt into it —
/// null means textless, which is why the images endpoints must not be asked in
/// a single language (see `TMDbService.get(localized:)`).
struct TMDbImage: Decodable {
	let file_path: String?
	let width: Int?
	let height: Int?
	let aspect_ratio: Double?
	let vote_average: Double?
	let iso_639_1: String?
}

/// The `/images` payload. Which arrays come back depends on the endpoint:
/// a series has posters/backdrops/logos, a season only posters, an episode
/// only stills.
struct TMDbImageSet: Decodable {
	let posters: [TMDbImage]?
	let backdrops: [TMDbImage]?
	let logos: [TMDbImage]?
	let stills: [TMDbImage]?
}

// MARK: - Video DTOs

/// One video TMDb links to — almost always a YouTube upload, `key` being its id.
struct TMDbVideo: Decodable {
	let key: String?
	let name: String?
	let site: String?
	let type: String?
	let official: Bool?
	let published_at: String?
	let iso_639_1: String?
}

struct TMDbVideoList: Decodable { let results: [TMDbVideo] }

// MARK: - Watch provider DTOs

/// A service offering a title. TMDb's data comes from JustWatch.
struct TMDbProvider: Decodable {
	let provider_id: Int?
	let provider_name: String?
	let logo_path: String?
	let display_priority: Int?
}

/// One country's offers. `link` is TMDb's watch page for the title there.
struct TMDbProviderRegion: Decodable {
	let link: String?
	let flatrate: [TMDbProvider]?
	let free: [TMDbProvider]?
	let ads: [TMDbProvider]?
	let rent: [TMDbProvider]?
	let buy: [TMDbProvider]?
}

/// Every country's offers, keyed by ISO 3166-1 code.
struct TMDbProviderResponse: Decodable { let results: [String: TMDbProviderRegion] }

/// A country TMDb has watch data for.
struct TMDbRegion: Decodable {
	let iso_3166_1: String
	let english_name: String?
}

struct TMDbRegionList: Decodable { let results: [TMDbRegion] }

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

	func multiSearch(query: String) async throws -> [TMDbSearchItem] {
		let response: TMDbSearchResponse = try await get("/search/multi", query: ["query": query])
		return response.results.filter { ($0.media_type == "movie" || $0.media_type == "tv") }
	}

	// MARK: Credits

	/// Series-wide cast, with a total episode count per person.
	func aggregateCredits(tvID: Int) async throws -> TMDbAggregateCredits {
		try await get("/tv/\(tvID)/aggregate_credits")
	}

	/// One season's cast. `aggregate_credits` rather than `credits` because only
	/// the aggregate shape carries the per-season episode counts we sort on.
	func seasonAggregateCredits(tvID: Int, seasonNumber: Int) async throws -> TMDbAggregateCredits {
		try await get("/tv/\(tvID)/season/\(seasonNumber)/aggregate_credits")
	}

	/// One episode's cast, guest stars and crew.
	func episodeCredits(tvID: Int, season: Int, episode: Int) async throws -> TMDbCredits {
		try await get("/tv/\(tvID)/season/\(season)/episode/\(episode)/credits")
	}

	/// A film's cast and crew. Films have no `aggregate_credits` — there are no
	/// episodes to count — so this is the plain billing-order shape.
	func movieCredits(movieID: Int) async throws -> TMDbCredits {
		try await get("/movie/\(movieID)/credits")
	}

	// MARK: Similar

	func similar(tvID: Int) async throws -> [TMDbSimilarTV] {
		let response: TMDbSimilarResponse = try await get("/tv/\(tvID)/similar")
		return response.results
	}

	func similar(movieID: Int) async throws -> [TMDbSimilarMovie] {
		let response: TMDbSimilarMovieResponse = try await get("/movie/\(movieID)/similar")
		return response.results
	}

	/// The id -> name table for TV genres. `/similar` only returns ids, so this
	/// is what turns them back into the genre names we show.
	func tvGenres() async throws -> [TMDbGenre] {
		let list: TMDbGenreList = try await get("/genre/tv/list")
		return list.genres
	}

	/// The same table for films. TMDb keeps the two lists separate and the ids
	/// do not line up, so a film's genre ids must be resolved against this one.
	func movieGenres() async throws -> [TMDbGenre] {
		let list: TMDbGenreList = try await get("/genre/movie/list")
		return list.genres
	}

	// MARK: Images
	//
	// All three go out unlocalised. TMDb filters `/images` by the `language`
	// parameter, so the usual en-US would return only English-titled artwork and
	// drop every textless poster — the opposite of what the Images tab is for.

	/// Every poster, backdrop and logo TMDb holds for a series.
	func tvImages(tvID: Int) async throws -> TMDbImageSet {
		try await get("/tv/\(tvID)/images", localized: false)
	}

	/// One season's posters.
	func seasonImages(tvID: Int, seasonNumber: Int) async throws -> TMDbImageSet {
		try await get("/tv/\(tvID)/season/\(seasonNumber)/images", localized: false)
	}

	/// One episode's stills.
	func episodeImages(tvID: Int, season: Int, episode: Int) async throws -> TMDbImageSet {
		try await get("/tv/\(tvID)/season/\(season)/episode/\(episode)/images", localized: false)
	}

	/// Every poster, backdrop and logo TMDb holds for a film.
	func movieImages(movieID: Int) async throws -> TMDbImageSet {
		try await get("/movie/\(movieID)/images", localized: false)
	}

	// MARK: Videos
	//
	// English, plus uploads with no language set. TMDb returns only English
	// videos unless asked, and a film's page can list forty of them, so there's
	// no call to widen it to every dub and subtitle.

	/// A series' trailers, teasers, clips and featurettes.
	func videos(tvID: Int) async throws -> [TMDbVideo] {
		let list: TMDbVideoList = try await get("/tv/\(tvID)/videos", query: Self.videoLanguages)
		return list.results
	}

	/// A film's trailers, teasers, clips and featurettes.
	func videos(movieID: Int) async throws -> [TMDbVideo] {
		let list: TMDbVideoList = try await get("/movie/\(movieID)/videos", query: Self.videoLanguages)
		return list.results
	}

	private static let videoLanguages = ["include_video_language": "en,null"]

	// MARK: Where to watch

	/// Where a series streams, rents and sells, in every country at once.
	func watchProviders(tvID: Int) async throws -> [String: TMDbProviderRegion] {
		let response: TMDbProviderResponse = try await get("/tv/\(tvID)/watch/providers")
		return response.results
	}

	/// Where a film streams, rents and sells, in every country at once.
	func watchProviders(movieID: Int) async throws -> [String: TMDbProviderRegion] {
		let response: TMDbProviderResponse = try await get("/movie/\(movieID)/watch/providers")
		return response.results
	}

	/// The countries TMDb has watch data for.
	func watchRegions() async throws -> [TMDbRegion] {
		let list: TMDbRegionList = try await get("/watch/providers/regions")
		return list.results
	}

	// MARK: Networking

	private func get<T: Decodable>(_ path: String,
	                               query: [String: String] = [:],
	                               localized: Bool = true) async throws -> T {
		guard TMDbConfig.isConfigured else { throw TMDbError.notConfigured }

		var components = URLComponents(string: TMDbConfig.apiBase + path)
		var items = [URLQueryItem(name: "api_key", value: TMDbConfig.apiKey)]
		if localized { items.append(URLQueryItem(name: "language", value: "en-US")) }
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
/*
 Multiple commands produce Target 'WatchList' (project 'WatchList') has copy command from '/Users/user/Desktop/Local Repo/WatchList/WatchList/Info.plist' to '/Users/user/Library/Developer/Xcode/DerivedData/WatchList-cssvgjmovlrqtpcukqfkeshionro/Build/Products/Debug-iphonesimulator/WatchList.app/Info.plist''/Users/user/Library/Developer/Xcode/DerivedData/WatchList-cssvgjmovlrqtpcukqfkeshionro/Build/Products/Debug-iphonesimulator/WatchList.app/Info.plist'
 Target 'WatchList' (project 'WatchList') has process command with output '/Users/user/Library/Developer/Xcode/DerivedData/WatchList-cssvgjmovlrqtpcukqfkeshionro/Build/Products/Debug-iphonesimulator/WatchList.app/Info.plist'
 */
