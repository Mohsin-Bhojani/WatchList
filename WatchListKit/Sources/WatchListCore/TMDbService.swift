//
//  TMDbService.swift
//  WatchList
//
//  Pulls synopsis, posters/stills, season & episode structure, credits,
//  similar titles and technical specs from The Movie Database (TMDb).
//  Compiled into both the iPhone app and the watch app; each reads the key from
//  its own bundle. Turning TMDb's payloads into TechSpecs is iPhone-only, in
//  WatchListLibrary/TechSpecsFromTMDb.swift.
//
//  The API key is not stored here — see TMDbConfig below and README.md.

import Foundation

// MARK: - Config

public enum TMDbConfig {
	/// The TMDb v3 API key. It is never stored in source: the build reads it
	/// from `Configuration/Secrets.xcconfig` (untracked — see README.md) and
	/// carries it into the generated Info.plist as `TMDBAPIKey`.
	///
	/// A `TMDB_API_KEY` environment variable wins when one is set, which is how
	/// a CI job or a one-off scheme override can supply a different key without
	/// touching the file.
	public static let apiKey: String = {
		let environment = ProcessInfo.processInfo.environment["TMDB_API_KEY"] ?? ""
		if !environment.isEmpty { return environment }
		let bundled = Bundle.main.object(forInfoDictionaryKey: "TMDBAPIKey") as? String ?? ""
		return bundled.trimmingCharacters(in: .whitespacesAndNewlines)
	}()

	public static var isConfigured: Bool { !apiKey.isEmpty }

	public static let apiBase = "https://api.themoviedb.org/3"
	public static let imageBase = "https://image.tmdb.org/t/p"

	/// Full poster URL (2:3). Returns "" when there's no path.
	public static func poster(_ path: String?) -> String { image(path, size: "w500") }
	public static func backdrop(_ path: String?) -> String { image(path, size: "w780") }
	public static func still(_ path: String?) -> String { image(path, size: "w300") }
	/// Cast headshot (2:3). Small, because it's drawn as a 44pt circle.
	public static func profile(_ path: String?) -> String { image(path, size: "w185") }

	/// A tile in the Images tab. Deliberately small — a popular show has a few
	/// hundred of these and they are drawn barely 100pt wide.
	public static func galleryThumb(_ path: String?) -> String { image(path, size: "w342") }

	/// A streaming service's square logo, drawn small.
	public static func logo(_ path: String?) -> String { image(path, size: "w92") }

	/// What the full-screen viewer loads.
	public static func fullSize(_ path: String?) -> String { image(path, size: "original") }

	private static func image(_ path: String?, size: String) -> String {
		guard let path, !path.isEmpty else { return "" }
		return "\(imageBase)/\(size)\(path)"
	}
}

// MARK: - Errors

public enum TMDbError: LocalizedError {
	case notConfigured
	case badURL
	case http(Int)
	case decoding

	public var errorDescription: String? {
		switch self {
		case .notConfigured: return "No TMDb API key. Copy Configuration/Secrets.example.xcconfig to Secrets.xcconfig, add your key and rebuild — see README.md."
		case .badURL:        return "Couldn't build the request URL."
		case .http(let c):   return "TMDb request failed (HTTP \(c))."
		case .decoding:      return "Couldn't read the response from TMDb."
		}
	}
}

// MARK: - DTOs

public struct TMDbNamed: Decodable { public let name: String? }
public struct TMDbSpokenLanguage: Decodable { public let english_name: String?; public let name: String? }

public struct TMDbExternalIDs: Decodable {
	public init(imdb_id: String? = nil) {
		self.imdb_id = imdb_id
	}

	public let imdb_id: String?
}

public struct TMDbFindResult: Decodable {
	public init(movie_results: [TMDbFindItem], tv_results: [TMDbFindItem]) {
		self.movie_results = movie_results
		self.tv_results = tv_results
	}

	public let movie_results: [TMDbFindItem]
	public let tv_results: [TMDbFindItem]
}

public struct TMDbFindItem: Decodable {
	public init(id: Int, title: String? = nil, name: String? = nil) {
		self.id = id
		self.title = title
		self.name = name
	}

	public let id: Int
	public let title: String?
	public let name: String?
}

public struct TMDbMovie: Decodable {
	public init(id: Int, title: String? = nil, overview: String? = nil, release_date: String? = nil, poster_path: String? = nil, backdrop_path: String? = nil, runtime: Int? = nil, status: String? = nil, original_language: String? = nil, budget: Int? = nil, revenue: Int? = nil, vote_average: Double? = nil, vote_count: Int? = nil, homepage: String? = nil, genres: [TMDbNamed]? = nil, spoken_languages: [TMDbSpokenLanguage]? = nil, production_companies: [TMDbNamed]? = nil, production_countries: [TMDbNamed]? = nil, external_ids: TMDbExternalIDs? = nil) {
		self.id = id
		self.title = title
		self.overview = overview
		self.release_date = release_date
		self.poster_path = poster_path
		self.backdrop_path = backdrop_path
		self.runtime = runtime
		self.status = status
		self.original_language = original_language
		self.budget = budget
		self.revenue = revenue
		self.vote_average = vote_average
		self.vote_count = vote_count
		self.homepage = homepage
		self.genres = genres
		self.spoken_languages = spoken_languages
		self.production_companies = production_companies
		self.production_countries = production_countries
		self.external_ids = external_ids
	}

	public let id: Int
	public let title: String?
	public let overview: String?
	public let release_date: String?
	public let poster_path: String?
	public let backdrop_path: String?
	public let runtime: Int?
	public let status: String?
	public let original_language: String?
	public let budget: Int?
	public let revenue: Int?
	public let vote_average: Double?
	public let vote_count: Int?
	public let homepage: String?
	public let genres: [TMDbNamed]?
	public let spoken_languages: [TMDbSpokenLanguage]?
	public let production_companies: [TMDbNamed]?
	public let production_countries: [TMDbNamed]?
	public let external_ids: TMDbExternalIDs?
}

public struct TMDbTV: Decodable {
	public init(id: Int, name: String? = nil, overview: String? = nil, first_air_date: String? = nil, poster_path: String? = nil, backdrop_path: String? = nil, status: String? = nil, original_language: String? = nil, vote_average: Double? = nil, vote_count: Int? = nil, homepage: String? = nil, genres: [TMDbNamed]? = nil, spoken_languages: [TMDbSpokenLanguage]? = nil, production_companies: [TMDbNamed]? = nil, production_countries: [TMDbNamed]? = nil, seasons: [TMDbSeasonSummary]? = nil, external_ids: TMDbExternalIDs? = nil) {
		self.id = id
		self.name = name
		self.overview = overview
		self.first_air_date = first_air_date
		self.poster_path = poster_path
		self.backdrop_path = backdrop_path
		self.status = status
		self.original_language = original_language
		self.vote_average = vote_average
		self.vote_count = vote_count
		self.homepage = homepage
		self.genres = genres
		self.spoken_languages = spoken_languages
		self.production_companies = production_companies
		self.production_countries = production_countries
		self.seasons = seasons
		self.external_ids = external_ids
	}

	public let id: Int
	public let name: String?
	public let overview: String?
	public let first_air_date: String?
	public let poster_path: String?
	public let backdrop_path: String?
	public let status: String?
	public let original_language: String?
	public let vote_average: Double?
	public let vote_count: Int?
	public let homepage: String?
	public let genres: [TMDbNamed]?
	public let spoken_languages: [TMDbSpokenLanguage]?
	public let production_companies: [TMDbNamed]?
	public let production_countries: [TMDbNamed]?
	public let seasons: [TMDbSeasonSummary]?
	public let external_ids: TMDbExternalIDs?
}

public struct TMDbSeasonSummary: Decodable {
	public init(season_number: Int, episode_count: Int? = nil, name: String? = nil) {
		self.season_number = season_number
		self.episode_count = episode_count
		self.name = name
	}

	public let season_number: Int
	public let episode_count: Int?
	public let name: String?
}

public struct TMDbSeasonDetail: Decodable {
	public init(name: String? = nil, overview: String? = nil, poster_path: String? = nil, air_date: String? = nil, episodes: [TMDbEpisode]? = nil) {
		self.name = name
		self.overview = overview
		self.poster_path = poster_path
		self.air_date = air_date
		self.episodes = episodes
	}

	public let name: String?
	public let overview: String?
	public let poster_path: String?
	public let air_date: String?
	public let episodes: [TMDbEpisode]?
}

public struct TMDbEpisode: Decodable {
	public init(id: Int? = nil, episode_number: Int, season_number: Int? = nil, name: String? = nil, overview: String? = nil, still_path: String? = nil, air_date: String? = nil, runtime: Int? = nil, vote_average: Double? = nil, vote_count: Int? = nil, production_code: String? = nil) {
		self.id = id
		self.episode_number = episode_number
		self.season_number = season_number
		self.name = name
		self.overview = overview
		self.still_path = still_path
		self.air_date = air_date
		self.runtime = runtime
		self.vote_average = vote_average
		self.vote_count = vote_count
		self.production_code = production_code
	}

	public let id: Int?
	public let episode_number: Int
	public let season_number: Int?
	public let name: String?
	public let overview: String?
	public let still_path: String?
	public let air_date: String?
	public let runtime: Int?
	public let vote_average: Double?
	public let vote_count: Int?
	public let production_code: String?
}

public struct TMDbSearchItem: Decodable, Identifiable {
	public init(id: Int, media_type: String? = nil, title: String? = nil, name: String? = nil, poster_path: String? = nil, release_date: String? = nil, first_air_date: String? = nil) {
		self.id = id
		self.media_type = media_type
		self.title = title
		self.name = name
		self.poster_path = poster_path
		self.release_date = release_date
		self.first_air_date = first_air_date
	}

	public let id: Int
	public let media_type: String?
	public let title: String?
	public let name: String?
	public let poster_path: String?
	public let release_date: String?
	public let first_air_date: String?

	public var displayTitle: String { title ?? name ?? "Untitled" }
}

public struct TMDbSearchResponse: Decodable { public let results: [TMDbSearchItem] }

// MARK: - Credits DTOs

/// One character a person played, as returned by the `aggregate_credits`
/// endpoints. A person can hold several roles across a run of a show.
public struct TMDbCreditRole: Decodable {
	public init(character: String? = nil, episode_count: Int? = nil) {
		self.character = character
		self.episode_count = episode_count
	}

	public let character: String?
	public let episode_count: Int?
}

/// A cast member from `/aggregate_credits` — the only credits shape that
/// carries episode counts.
public struct TMDbAggregateCastMember: Decodable {
	public init(id: Int, name: String? = nil, profile_path: String? = nil, total_episode_count: Int? = nil, order: Int? = nil, roles: [TMDbCreditRole]? = nil) {
		self.id = id
		self.name = name
		self.profile_path = profile_path
		self.total_episode_count = total_episode_count
		self.order = order
		self.roles = roles
	}

	public let id: Int
	public let name: String?
	public let profile_path: String?
	public let total_episode_count: Int?
	public let order: Int?
	public let roles: [TMDbCreditRole]?
}

public struct TMDbAggregateCredits: Decodable {
	public init(cast: [TMDbAggregateCastMember]? = nil) {
		self.cast = cast
	}

	public let cast: [TMDbAggregateCastMember]?
}

/// A cast member from the plain `/credits` endpoints (episode level), which
/// bill by `order` and have no episode counts.
public struct TMDbCastMember: Decodable {
	public init(id: Int, name: String? = nil, character: String? = nil, profile_path: String? = nil, order: Int? = nil) {
		self.id = id
		self.name = name
		self.character = character
		self.profile_path = profile_path
		self.order = order
	}

	public let id: Int
	public let name: String?
	public let character: String?
	public let profile_path: String?
	public let order: Int?
}

public struct TMDbCrewMember: Decodable {
	public init(id: Int, name: String? = nil, job: String? = nil, department: String? = nil) {
		self.id = id
		self.name = name
		self.job = job
		self.department = department
	}

	public let id: Int
	public let name: String?
	public let job: String?
	public let department: String?
}

public struct TMDbCredits: Decodable {
	public init(cast: [TMDbCastMember]? = nil, crew: [TMDbCrewMember]? = nil, guest_stars: [TMDbCastMember]? = nil) {
		self.cast = cast
		self.crew = crew
		self.guest_stars = guest_stars
	}

	public let cast: [TMDbCastMember]?
	public let crew: [TMDbCrewMember]?
	public let guest_stars: [TMDbCastMember]?
}

// MARK: - Similar / genre DTOs

/// A title from `/tv/{id}/similar`. Note it carries `genre_ids`, not names —
/// see `TMDbService.tvGenres()` for the lookup table.
public struct TMDbSimilarTV: Decodable {
	public init(id: Int, name: String? = nil, first_air_date: String? = nil, vote_average: Double? = nil, poster_path: String? = nil, genre_ids: [Int]? = nil) {
		self.id = id
		self.name = name
		self.first_air_date = first_air_date
		self.vote_average = vote_average
		self.poster_path = poster_path
		self.genre_ids = genre_ids
	}

	public let id: Int
	public let name: String?
	public let first_air_date: String?
	public let vote_average: Double?
	public let poster_path: String?
	public let genre_ids: [Int]?
}

public struct TMDbSimilarResponse: Decodable { public let results: [TMDbSimilarTV] }

/// A title from `/movie/{id}/similar`. The same payload as its TV counterpart
/// with `title` / `release_date` in place of `name` / `first_air_date`, and its
/// genre ids come from the movie table rather than the TV one.
public struct TMDbSimilarMovie: Decodable {
	public init(id: Int, title: String? = nil, release_date: String? = nil, vote_average: Double? = nil, poster_path: String? = nil, genre_ids: [Int]? = nil) {
		self.id = id
		self.title = title
		self.release_date = release_date
		self.vote_average = vote_average
		self.poster_path = poster_path
		self.genre_ids = genre_ids
	}

	public let id: Int
	public let title: String?
	public let release_date: String?
	public let vote_average: Double?
	public let poster_path: String?
	public let genre_ids: [Int]?
}

public struct TMDbSimilarMovieResponse: Decodable { public let results: [TMDbSimilarMovie] }

public struct TMDbGenre: Decodable {
	public init(id: Int, name: String? = nil) {
		self.id = id
		self.name = name
	}

	public let id: Int
	public let name: String?
}

public struct TMDbGenreList: Decodable { public let genres: [TMDbGenre] }

/// A title's keywords: films send them under `keywords`, shows under `results`.
public struct TMDbTitleKeywords: Decodable {
	public init(keywords: [TMDbKeywordSearch.Keyword]? = nil, results: [TMDbKeywordSearch.Keyword]? = nil) {
		self.keywords = keywords
		self.results = results
	}

	public let keywords: [TMDbKeywordSearch.Keyword]?
	public let results: [TMDbKeywordSearch.Keyword]?

	public var all: [TMDbKeywordSearch.Keyword] { keywords ?? results ?? [] }
}

public struct TMDbKeywordSearch: Decodable {
	public init(results: [Keyword]) {
		self.results = results
	}

	public struct Keyword: Decodable { public let id: Int; public let name: String }
	public let results: [Keyword]
}

// MARK: - Image DTOs

/// One artwork file. `iso_639_1` is the language of any text burnt into it —
/// null means textless, which is why the images endpoints must not be asked in
/// a single language (see `TMDbService.get(localized:)`).
public struct TMDbImage: Decodable {
	public init(file_path: String? = nil, width: Int? = nil, height: Int? = nil, aspect_ratio: Double? = nil, vote_average: Double? = nil, iso_639_1: String? = nil) {
		self.file_path = file_path
		self.width = width
		self.height = height
		self.aspect_ratio = aspect_ratio
		self.vote_average = vote_average
		self.iso_639_1 = iso_639_1
	}

	public let file_path: String?
	public let width: Int?
	public let height: Int?
	public let aspect_ratio: Double?
	public let vote_average: Double?
	public let iso_639_1: String?
}

/// The `/images` payload. Which arrays come back depends on the endpoint:
/// a series has posters/backdrops/logos, a season only posters, an episode
/// only stills.
public struct TMDbImageSet: Decodable {
	public init(posters: [TMDbImage]? = nil, backdrops: [TMDbImage]? = nil, logos: [TMDbImage]? = nil, stills: [TMDbImage]? = nil) {
		self.posters = posters
		self.backdrops = backdrops
		self.logos = logos
		self.stills = stills
	}

	public let posters: [TMDbImage]?
	public let backdrops: [TMDbImage]?
	public let logos: [TMDbImage]?
	public let stills: [TMDbImage]?
}

// MARK: - Service

// MARK: - Videos and where to watch DTOs

public struct TMDbVideo: Decodable, Equatable {
	public init(key: String, site: String? = nil, type: String? = nil, official: Bool? = nil, iso_639_1: String? = nil, published_at: String? = nil, name: String? = nil) {
		self.key = key
		self.site = site
		self.type = type
		self.official = official
		self.iso_639_1 = iso_639_1
		self.published_at = published_at
		self.name = name
	}

	public let key: String
	public let site: String?
	public let type: String?
	public let official: Bool?
	public let iso_639_1: String?
	public let published_at: String?
	public let name: String?
}

public struct TMDbVideoList: Decodable { public let results: [TMDbVideo]? }

public struct TMDbWatchProvider: Decodable, Equatable {
	public init(provider_id: Int, provider_name: String? = nil, logo_path: String? = nil, display_priority: Int? = nil) {
		self.provider_id = provider_id
		self.provider_name = provider_name
		self.logo_path = logo_path
		self.display_priority = display_priority
	}

	public let provider_id: Int
	public let provider_name: String?
	public let logo_path: String?
	public let display_priority: Int?
}

/// One country's offers. `link` is TMDb's page for the title there.
public struct TMDbRegionProviders: Decodable, Equatable {
	public init(link: String? = nil, flatrate: [TMDbWatchProvider]? = nil, free: [TMDbWatchProvider]? = nil, ads: [TMDbWatchProvider]? = nil, rent: [TMDbWatchProvider]? = nil, buy: [TMDbWatchProvider]? = nil) {
		self.link = link
		self.flatrate = flatrate
		self.free = free
		self.ads = ads
		self.rent = rent
		self.buy = buy
	}

	public let link: String?
	public let flatrate: [TMDbWatchProvider]?
	public let free: [TMDbWatchProvider]?
	public let ads: [TMDbWatchProvider]?
	public let rent: [TMDbWatchProvider]?
	public let buy: [TMDbWatchProvider]?
}

/// The services a region has, from /watch/providers/movie or /tv.
public struct TMDbWatchProviderList: Decodable { public let results: [TMDbWatchProvider]? }

/// Offers by country code ("GB", "US"). TMDb's data comes from JustWatch,
/// which has to be credited wherever it's shown.
public struct TMDbWatchProviders: Decodable { public let results: [String: TMDbRegionProviders]? }

public struct TMDbService {
	public static let shared = TMDbService()
	private let session = URLSession.shared

	// MARK: Public API

	/// Resolve an IMDb id to TMDb movie/tv results.
	public func find(imdbID: String) async throws -> TMDbFindResult {
		try await get("/find/\(imdbID)", query: ["external_source": "imdb_id"])
	}

	public func movie(id: Int) async throws -> TMDbMovie {
		try await get("/movie/\(id)", query: ["append_to_response": "external_ids"])
	}

	public func tv(id: Int) async throws -> TMDbTV {
		try await get("/tv/\(id)", query: ["append_to_response": "external_ids"])
	}

	public func season(tvID: Int, seasonNumber: Int) async throws -> TMDbSeasonDetail {
		try await get("/tv/\(tvID)/season/\(seasonNumber)")
	}

	public func multiSearch(query: String) async throws -> [TMDbSearchItem] {
		let response: TMDbSearchResponse = try await get("/search/multi", query: ["query": query])
		return response.results.filter { ($0.media_type == "movie" || $0.media_type == "tv") }
	}

	// MARK: Credits

	/// Series-wide cast, with a total episode count per person.
	public func aggregateCredits(tvID: Int) async throws -> TMDbAggregateCredits {
		try await get("/tv/\(tvID)/aggregate_credits")
	}

	/// One season's cast. `aggregate_credits` rather than `credits` because only
	/// the aggregate shape carries the per-season episode counts we sort on.
	public func seasonAggregateCredits(tvID: Int, seasonNumber: Int) async throws -> TMDbAggregateCredits {
		try await get("/tv/\(tvID)/season/\(seasonNumber)/aggregate_credits")
	}

	/// One episode's cast, guest stars and crew.
	public func episodeCredits(tvID: Int, season: Int, episode: Int) async throws -> TMDbCredits {
		try await get("/tv/\(tvID)/season/\(season)/episode/\(episode)/credits")
	}

	/// A film's cast and crew. Films have no `aggregate_credits` — there are no
	/// episodes to count — so this is the plain billing-order shape.
	public func movieCredits(movieID: Int) async throws -> TMDbCredits {
		try await get("/movie/\(movieID)/credits")
	}

	// MARK: Similar

	public func similar(tvID: Int) async throws -> [TMDbSimilarTV] {
		let response: TMDbSimilarResponse = try await get("/tv/\(tvID)/similar")
		return response.results
	}

	public func similar(movieID: Int) async throws -> [TMDbSimilarMovie] {
		let response: TMDbSimilarMovieResponse = try await get("/movie/\(movieID)/similar")
		return response.results
	}

	/// The id -> name table for TV genres. `/similar` only returns ids, so this
	/// is what turns them back into the genre names we show.
	public func tvGenres() async throws -> [TMDbGenre] {
		let list: TMDbGenreList = try await get("/genre/tv/list")
		return list.genres
	}

	/// The same table for films. TMDb keeps the two lists separate and the ids
	/// do not line up, so a film's genre ids must be resolved against this one.
	public func movieGenres() async throws -> [TMDbGenre] {
		let list: TMDbGenreList = try await get("/genre/movie/list")
		return list.genres
	}

	// MARK: Discover

	/// Titles matching what someone described: every genre in `genreIDs`, none of
	/// `withoutGenreIDs`, and any of `keywordIDs` when there are some. Popular
	/// first, with enough votes to mean something.
	public func discover(_ kind: MediaKind, genreIDs: [Int], withoutGenreIDs: [Int], keywordIDs: [Int],
	              page: Int = 1) async throws -> [TMDbSuggestedTitle] {
		var query = ["sort_by": "popularity.desc", "vote_count.gte": "300", "vote_average.gte": "6.3",
		             "include_adult": "false", "page": String(page)]
		if !genreIDs.isEmpty { query["with_genres"] = genreIDs.map(String.init).joined(separator: ",") }
		if !withoutGenreIDs.isEmpty { query["without_genres"] = withoutGenreIDs.map(String.init).joined(separator: ",") }
		if !keywordIDs.isEmpty { query["with_keywords"] = keywordIDs.map(String.init).joined(separator: "|") }
		let response: TMDbSuggestedPage = try await get(kind == .show ? "/discover/tv" : "/discover/movie", query: query)
		return response.results
	}

	/// The keywords TMDb files a show or film under, such as "heist" or "london".
	public func keywords(_ kind: MediaKind, id: Int) async throws -> [TMDbKeywordSearch.Keyword] {
		let response: TMDbTitleKeywords = try await get((kind == .show ? "/tv/" : "/movie/") + "\(id)/keywords")
		return response.all
	}

	/// TMDb's id for a keyword such as "happy ending", or nil when it has none.
	public func keywordID(for name: String) async throws -> Int? {
		let response: TMDbKeywordSearch = try await get("/search/keyword", query: ["query": name])
		return response.results.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
			?? response.results.first?.id
	}

	// MARK: Images
	//
	// All three go out unlocalised. TMDb filters `/images` by the `language`
	// parameter, so the usual en-US would return only English-titled artwork and
	// drop every textless poster — the opposite of what the Images tab is for.

	/// Every poster, backdrop and logo TMDb holds for a series.
	public func tvImages(tvID: Int) async throws -> TMDbImageSet {
		try await get("/tv/\(tvID)/images", localized: false)
	}

	/// One season's posters.
	public func seasonImages(tvID: Int, seasonNumber: Int) async throws -> TMDbImageSet {
		try await get("/tv/\(tvID)/season/\(seasonNumber)/images", localized: false)
	}

	/// One episode's stills.
	public func episodeImages(tvID: Int, season: Int, episode: Int) async throws -> TMDbImageSet {
		try await get("/tv/\(tvID)/season/\(season)/episode/\(episode)/images", localized: false)
	}

	/// Every poster, backdrop and logo TMDb holds for a film.
	public func movieImages(movieID: Int) async throws -> TMDbImageSet {
		try await get("/movie/\(movieID)/images", localized: false)
	}

	// MARK: Videos and where to watch

	/// Trailers, teasers and clips. Unlocalised, then filtered by language on
	/// the phone, so a title with no English trailer still has one to offer.
	public func videos(_ kind: MediaKind, id: Int) async throws -> [TMDbVideo] {
		let path = kind == .film ? "/movie/\(id)/videos" : "/tv/\(id)/videos"
		let list: TMDbVideoList = try await get(path, localized: false)
		return list.results ?? []
	}

	/// Every streaming, rental and shop service TMDb lists for `kind` in `region`.
	public func watchProviderList(_ kind: MediaKind, region: String) async throws -> [TMDbWatchProvider] {
		let list: TMDbWatchProviderList = try await get(kind == .film ? "/watch/providers/movie" : "/watch/providers/tv",
		                                                query: ["watch_region": region])
		return list.results ?? []
	}

	public func watchProviders(_ kind: MediaKind, id: Int) async throws -> TMDbWatchProviders {
		try await get(kind == .film ? "/movie/\(id)/watch/providers" : "/tv/\(id)/watch/providers")
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
