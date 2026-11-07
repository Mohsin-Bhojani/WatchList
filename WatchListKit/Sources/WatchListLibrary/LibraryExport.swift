//
//  LibraryExport.swift
//  WatchList
//
//  Everything in the library as one JSON file, for Settings' Export. Every
//  film, show, season and episode row carries everything about it on its own —
//  ratings (stars, verdict, note), portrait and landscape images, what a
//  trailer needs, synopsis, genre, runtime, dates added, released and watched,
//  places to watch, the collections it's in, and its rating distributions — so
//  a row can be read without looking anything up elsewhere in the file.
//
//  Places to watch and trailers aren't fetched yet, so those stay empty. The
//  distributions count this person's own rating until there are others'.
//
//  Reads only. The library store, and the stars, watched dates and collections
//  kept beside it, are left exactly as they were.
//
//  Format 3 adds what Restore (LibraryRestore.swift) needs to put a title back
//  exactly — hand-picked stars, when a verdict was given, what stood out, tech
//  specs, the stored artwork — and Discover's decisions. Every one of those is
//  optional, so a format 2 file still restores, with those filled in as best
//  they can be.
//

import SwiftUI
import UniformTypeIdentifiers
import WatchListCore

public struct LibraryExport: Codable {
	public var app = "WatchList"
	public var formatVersion = 3
	public var exportedAt: Date
	public var films: [FilmRecord]
	public var shows: [ShowRecord]
	public var collections: [CollectionRecord]
	/// Discover's suggestions turned down or put off. Format 3 on.
	public var suggestionDecisions: [DecisionRecord]?
}

// MARK: - Rows

extension LibraryExport {
	public struct Ratings: Codable, Equatable {
		public init(stars: Double? = nil, verdict: String? = nil, note: String? = nil) {
			self.stars = stars
			self.verdict = verdict
			self.note = note
		}

		public var stars: Double?
		/// A verdict — or, for an episode, its Skip / Watch / Rewatch.
		public var verdict: String?
		public var note: String?
	}

	public struct Images: Codable, Equatable {
		public init(portrait: String? = nil, landscape: String? = nil) {
			self.portrait = portrait
			self.landscape = landscape
		}

		public var portrait: String?
		public var landscape: String?
	}

	/// Where TMDb lists the title's videos. The trailer itself isn't fetched
	/// yet, so `youtubeKey` stays empty.
	public struct Trailer: Codable, Equatable {
		public init(tmdbID: Int, videosPath: String, youtubeKey: String? = nil) {
			self.tmdbID = tmdbID
			self.videosPath = videosPath
			self.youtubeKey = youtubeKey
		}

		public var tmdbID: Int
		public var videosPath: String
		public var youtubeKey: String? = nil
	}

	public struct CollectionRef: Codable, Equatable {
		public init(id: UUID, name: String) {
			self.id = id
			self.name = name
		}

		public var id: UUID
		public var name: String
	}

	public struct EpisodeRef: Codable, Equatable {
		public init(code: String, seasonNumber: Int, episodeNumber: Int, title: String, airDate: String? = nil) {
			self.code = code
			self.seasonNumber = seasonNumber
			self.episodeNumber = episodeNumber
			self.title = title
			self.airDate = airDate
		}

		public var code: String
		public var seasonNumber: Int
		public var episodeNumber: Int
		public var title: String
		public var airDate: String?
	}

	public struct FilmRecord: Codable {
		public init(id: UUID, title: String, status: String, ratings: Ratings, images: Images, trailer: Trailer? = nil, synopsis: String, genre: String, runtimeMinutes: Int? = nil, releaseDate: String? = nil, dateAdded: Date, dateWatched: Date? = nil, placesToWatch: [String], collections: [CollectionRef], verdictDistribution: [String: Int], starDistribution: [String: Int], imdbID: String? = nil, tmdbID: Int? = nil, handPickedStars: Double? = nil, ratedAt: Date? = nil, likedAspects: [String]? = nil, dislikedAspects: [String]? = nil, specs: TechSpecs? = nil, year: String? = nil) {
			self.id = id
			self.title = title
			self.status = status
			self.ratings = ratings
			self.images = images
			self.trailer = trailer
			self.synopsis = synopsis
			self.genre = genre
			self.runtimeMinutes = runtimeMinutes
			self.releaseDate = releaseDate
			self.dateAdded = dateAdded
			self.dateWatched = dateWatched
			self.placesToWatch = placesToWatch
			self.collections = collections
			self.verdictDistribution = verdictDistribution
			self.starDistribution = starDistribution
			self.imdbID = imdbID
			self.tmdbID = tmdbID
			self.handPickedStars = handPickedStars
			self.ratedAt = ratedAt
			self.likedAspects = likedAspects
			self.dislikedAspects = dislikedAspects
			self.specs = specs
			self.year = year
		}

		public var id: UUID
		public var title: String
		public var status: String
		public var ratings: Ratings
		public var images: Images
		public var trailer: Trailer?
		public var synopsis: String
		public var genre: String
		public var runtimeMinutes: Int?
		public var releaseDate: String?
		public var dateAdded: Date
		public var dateWatched: Date?
		public var placesToWatch: [String]
		public var collections: [CollectionRef]
		public var verdictDistribution: [String: Int]
		public var starDistribution: [String: Int]
		public var imdbID: String?
		public var tmdbID: Int?
		// Format 3 on.
		public var handPickedStars: Double?
		public var ratedAt: Date?
		public var likedAspects: [String]?
		public var dislikedAspects: [String]?
		public var specs: TechSpecs?
		public var year: String?
	}

	public struct ShowRecord: Codable {
		public init(id: UUID, title: String, status: String, ratings: Ratings, images: Images, trailer: Trailer? = nil, synopsis: String, genre: String, nextEpisode: EpisodeRef? = nil, airingDate: String? = nil, dateAdded: Date, dateFirstEpisodeWatched: Date? = nil, placesToWatch: [String], collections: [CollectionRef], verdictDistribution: [String: Int], starDistribution: [String: Int], numberOfSeasons: Int, seasons: [SeasonRecord], imdbID: String? = nil, tmdbID: Int? = nil, handPickedStars: Double? = nil, ratedAt: Date? = nil, likedAspects: [String]? = nil, dislikedAspects: [String]? = nil, firstAirYear: String? = nil, dateWatched: Date? = nil) {
			self.id = id
			self.title = title
			self.status = status
			self.ratings = ratings
			self.images = images
			self.trailer = trailer
			self.synopsis = synopsis
			self.genre = genre
			self.nextEpisode = nextEpisode
			self.airingDate = airingDate
			self.dateAdded = dateAdded
			self.dateFirstEpisodeWatched = dateFirstEpisodeWatched
			self.placesToWatch = placesToWatch
			self.collections = collections
			self.verdictDistribution = verdictDistribution
			self.starDistribution = starDistribution
			self.numberOfSeasons = numberOfSeasons
			self.seasons = seasons
			self.imdbID = imdbID
			self.tmdbID = tmdbID
			self.handPickedStars = handPickedStars
			self.ratedAt = ratedAt
			self.likedAspects = likedAspects
			self.dislikedAspects = dislikedAspects
			self.firstAirYear = firstAirYear
			self.dateWatched = dateWatched
		}

		public var id: UUID
		public var title: String
		public var status: String
		public var ratings: Ratings
		public var images: Images
		public var trailer: Trailer?
		public var synopsis: String
		public var genre: String
		/// The episode after the one most recently marked Watched.
		public var nextEpisode: EpisodeRef?
		/// The first season's first episode's air date.
		public var airingDate: String?
		public var dateAdded: Date
		public var dateFirstEpisodeWatched: Date?
		public var placesToWatch: [String]
		public var collections: [CollectionRef]
		public var verdictDistribution: [String: Int]
		public var starDistribution: [String: Int]
		public var numberOfSeasons: Int
		public var seasons: [SeasonRecord]
		public var imdbID: String?
		public var tmdbID: Int?
		// Format 3 on.
		public var handPickedStars: Double?
		public var ratedAt: Date?
		public var likedAspects: [String]?
		public var dislikedAspects: [String]?
		public var firstAirYear: String?
		public var dateWatched: Date?
	}

	public struct SeasonRecord: Codable {
		public init(id: UUID, seasonNumber: Int, name: String, status: String, ratings: Ratings, images: Images, trailer: Trailer? = nil, synopsis: String, genre: String, runtimeMinutes: Int? = nil, releaseDate: String? = nil, dateAdded: Date, dateFirstEpisodeWatched: Date? = nil, dateLastEpisodeWatched: Date? = nil, placesToWatch: [String], collections: [CollectionRef], verdictDistribution: [String: Int], starDistribution: [String: Int], numberOfEpisodes: Int, episodes: [EpisodeRecord], handPickedStars: Double? = nil, ratedAt: Date? = nil, posterURL: String? = nil, airYear: String? = nil) {
			self.id = id
			self.seasonNumber = seasonNumber
			self.name = name
			self.status = status
			self.ratings = ratings
			self.images = images
			self.trailer = trailer
			self.synopsis = synopsis
			self.genre = genre
			self.runtimeMinutes = runtimeMinutes
			self.releaseDate = releaseDate
			self.dateAdded = dateAdded
			self.dateFirstEpisodeWatched = dateFirstEpisodeWatched
			self.dateLastEpisodeWatched = dateLastEpisodeWatched
			self.placesToWatch = placesToWatch
			self.collections = collections
			self.verdictDistribution = verdictDistribution
			self.starDistribution = starDistribution
			self.numberOfEpisodes = numberOfEpisodes
			self.episodes = episodes
			self.handPickedStars = handPickedStars
			self.ratedAt = ratedAt
			self.posterURL = posterURL
			self.airYear = airYear
		}

		public var id: UUID
		public var seasonNumber: Int
		public var name: String
		public var status: String
		public var ratings: Ratings
		public var images: Images
		public var trailer: Trailer?
		public var synopsis: String
		public var genre: String
		/// Its episodes' runtimes added up.
		public var runtimeMinutes: Int?
		public var releaseDate: String?
		public var dateAdded: Date
		public var dateFirstEpisodeWatched: Date?
		public var dateLastEpisodeWatched: Date?
		public var placesToWatch: [String]
		public var collections: [CollectionRef]
		public var verdictDistribution: [String: Int]
		public var starDistribution: [String: Int]
		public var numberOfEpisodes: Int
		public var episodes: [EpisodeRecord]
		// Format 3 on. `images` falls back to the show's; these are its own.
		public var handPickedStars: Double?
		public var ratedAt: Date?
		public var posterURL: String?
		public var airYear: String?
	}

	public struct EpisodeRecord: Codable {
		public init(id: UUID, code: String, seasonNumber: Int, episodeNumber: Int, title: String, status: String, ratings: Ratings, images: Images, trailer: Trailer? = nil, synopsis: String, genre: String, runtimeMinutes: Int? = nil, releaseDate: String? = nil, dateAdded: Date, dateWatched: Date? = nil, placesToWatch: [String], collections: [CollectionRef], verdictDistribution: [String: Int], starDistribution: [String: Int], imdbID: String? = nil, stillURL: String? = nil, specs: TechSpecs? = nil, tmdbShowID: Int? = nil) {
			self.id = id
			self.code = code
			self.seasonNumber = seasonNumber
			self.episodeNumber = episodeNumber
			self.title = title
			self.status = status
			self.ratings = ratings
			self.images = images
			self.trailer = trailer
			self.synopsis = synopsis
			self.genre = genre
			self.runtimeMinutes = runtimeMinutes
			self.releaseDate = releaseDate
			self.dateAdded = dateAdded
			self.dateWatched = dateWatched
			self.placesToWatch = placesToWatch
			self.collections = collections
			self.verdictDistribution = verdictDistribution
			self.starDistribution = starDistribution
			self.imdbID = imdbID
			self.stillURL = stillURL
			self.specs = specs
			self.tmdbShowID = tmdbShowID
		}

		public var id: UUID
		public var code: String
		public var seasonNumber: Int
		public var episodeNumber: Int
		public var title: String
		public var status: String
		public var ratings: Ratings
		public var images: Images
		public var trailer: Trailer?
		public var synopsis: String
		public var genre: String
		public var runtimeMinutes: Int?
		public var releaseDate: String?
		public var dateAdded: Date
		public var dateWatched: Date?
		public var placesToWatch: [String]
		public var collections: [CollectionRef]
		public var verdictDistribution: [String: Int]
		public var starDistribution: [String: Int]
		public var imdbID: String?
		// Format 3 on. `images` falls back to the show's; this is its own.
		public var stillURL: String?
		public var specs: TechSpecs?
		public var tmdbShowID: Int?
	}

	public struct CollectionRecord: Codable {
		public init(id: UUID, name: String, created: Date, titleIDs: [UUID], titles: [String]) {
			self.id = id
			self.name = name
			self.created = created
			self.titleIDs = titleIDs
			self.titles = titles
		}

		public var id: UUID
		public var name: String
		public var created: Date
		public var titleIDs: [UUID]
		/// The same titles by name, for reading the file by eye.
		public var titles: [String]
	}

	public struct DecisionRecord: Codable, Equatable {
		public init(key: String, choice: String, decidedAt: Date) {
			self.key = key
			self.choice = choice
			self.decidedAt = decidedAt
		}

		public var key: String
		public var choice: String
		public var decidedAt: Date
	}
}

// MARK: - Distributions

/// A title's rating distributions. Until there are other people's ratings to
/// count, each is this person's own: one on the rating given, or all zero.
public enum RatingDistribution {
	public static func verdicts(_ rating: Rating?) -> [String: Int] {
		Dictionary(uniqueKeysWithValues: Rating.allCases.map { ($0.rawValue, $0 == rating ? 1 : 0) })
	}

	public static func episodeRatings(_ tier: EpisodeTier?) -> [String: Int] {
		Dictionary(uniqueKeysWithValues: EpisodeTier.allCases.map { ($0.rawValue, $0 == tier ? 1 : 0) })
	}

	/// "0", "0.5" … "5".
	public static func stars(_ value: Double?) -> [String: Int] {
		Dictionary(uniqueKeysWithValues: StarRating.values.map { (StarRating.label($0), $0 == value ? 1 : 0) })
	}
}

// MARK: - Building

extension LibraryExport {
	/// Films and shows A–Z, seasons and episodes in number order, collections
	/// as they're listed.
	public init(shows: [Show], films: [Film], collections: [TitleCollection],
	     decisions: [SuggestionDecision] = [], now: Date = .now) {
		let rows = ExportRows(collections: collections)
		let byTitle: (String, String) -> Bool = { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
		exportedAt = now
		self.films = films.sorted { byTitle($0.title, $1.title) }.map(rows.film)
		self.shows = shows.sorted { byTitle($0.title, $1.title) }.map(rows.show)

		var names: [UUID: String] = [:]
		for show in shows { names[show.id] = show.title }
		for film in films { names[film.id] = film.title }
		self.collections = collections.map { collection in
			CollectionRecord(id: collection.id, name: collection.name, created: collection.created,
			                 titleIDs: collection.titleIDs, titles: collection.titleIDs.compactMap { names[$0] })
		}
		suggestionDecisions = decisions.sorted { $0.key < $1.key }.map {
			DecisionRecord(key: $0.key, choice: $0.choice.rawValue, decidedAt: $0.decidedAt)
		}
	}

	/// Reads a file `encoded()` wrote — this format or an earlier one.
	public static func decoded(from data: Data) throws -> LibraryExport {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return try decoder.decode(LibraryExport.self, from: data)
	}

	/// Pretty-printed with sorted keys and ISO 8601 dates, so it reads and
	/// compares well.
	public func encoded() throws -> Data {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		encoder.dateEncodingStrategy = .iso8601
		return try encoder.encode(self)
	}

	/// "WatchList Export 2026-09-14", dated in the given time zone.
	public static func defaultFilename(for date: Date, timeZone: TimeZone = .current) -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.timeZone = timeZone
		formatter.dateFormat = "yyyy-MM-dd"
		return "WatchList Export \(formatter.string(from: date))"
	}
}

/// Turns library records into export rows, with everything a row needs looked
/// up in one place.
private struct ExportRows {
	typealias Row = LibraryExport

	let collections: [TitleCollection]

	func film(_ film: Film) -> Row.FilmRecord {
		let ratings = ratings(film, note: film.notes)
		return Row.FilmRecord(
			id: film.id, title: film.title, status: film.status.rawValue, ratings: ratings,
			images: Row.Images(portrait: text(film.posterURL), landscape: text(film.backdropURL)),
			trailer: film.tmdbID.map { Row.Trailer(tmdbID: $0, videosPath: "/movie/\($0)/videos") },
			synopsis: film.synopsis, genre: film.genre, runtimeMinutes: film.specs?.runtimeMinutes,
			releaseDate: text(film.specs?.releaseDate) ?? text(film.year),
			dateAdded: film.dateAdded, dateWatched: film.watchedAt, placesToWatch: [],
			collections: collectionRefs(film.id),
			verdictDistribution: RatingDistribution.verdicts(film.rating),
			starDistribution: RatingDistribution.stars(ratings.stars),
			imdbID: film.imdbID, tmdbID: film.tmdbID,
			handPickedStars: film.stars, ratedAt: film.ratedAt,
			likedAspects: film.likedAspects, dislikedAspects: film.dislikedAspects,
			specs: film.specs, year: text(film.year))
	}

	func show(_ show: Show) -> Row.ShowRecord {
		let ratings = ratings(show, note: show.notes)
		let ordered = HomeFeed.runningOrder(of: show)
		let collections = collectionRefs(show.id)
		let firstEpisode = show.sortedSeasons.first { $0.seasonNumber > 0 }?.sortedEpisodes.first ?? ordered.first
		return Row.ShowRecord(
			id: show.id, title: show.title, status: show.status.rawValue, ratings: ratings,
			images: Row.Images(portrait: text(show.posterURL), landscape: text(show.backdropURL)),
			trailer: show.tmdbID.map { Row.Trailer(tmdbID: $0, videosPath: "/tv/\($0)/videos") },
			synopsis: show.overview, genre: show.genre,
			nextEpisode: ShowFacts.nextAfterLastWatched(ordered).map(episodeRef),
			airingDate: text(firstEpisode?.airDate) ?? text(show.firstAirYear),
			dateAdded: show.dateAdded,
			dateFirstEpisodeWatched: ordered.compactMap(\.watchedAt).min(),
			placesToWatch: [], collections: collections,
			verdictDistribution: RatingDistribution.verdicts(show.rating),
			starDistribution: RatingDistribution.stars(ratings.stars),
			numberOfSeasons: show.seasons.count,
			seasons: show.sortedSeasons.map { season($0, of: show, collections: collections) },
			imdbID: show.imdbID, tmdbID: show.tmdbID,
			handPickedStars: show.stars, ratedAt: show.ratedAt,
			likedAspects: show.likedAspects, dislikedAspects: show.dislikedAspects,
			firstAirYear: text(show.firstAirYear), dateWatched: show.watchedAt)
	}

	private func season(_ season: Season, of show: Show, collections: [Row.CollectionRef]) -> Row.SeasonRecord {
		let episodes = season.sortedEpisodes
		let ratings = ratings(season, note: nil)
		let watched = episodes.compactMap(\.watchedAt)
		let runtimes = episodes.compactMap { $0.runtimeMinutes ?? $0.specs?.runtimeMinutes }
		let portrait = text(season.posterURL) ?? text(show.posterURL)
		return Row.SeasonRecord(
			id: season.id, seasonNumber: season.seasonNumber, name: season.displayName,
			status: season.status.rawValue, ratings: ratings,
			images: Row.Images(portrait: portrait,
			                   landscape: text(episodes.first?.stillURL) ?? text(show.backdropURL)),
			trailer: show.tmdbID.map { Row.Trailer(tmdbID: $0, videosPath: "/tv/\($0)/season/\(season.seasonNumber)/videos") },
			synopsis: season.overview, genre: show.genre,
			runtimeMinutes: runtimes.isEmpty ? nil : runtimes.reduce(0, +),
			releaseDate: text(episodes.first?.airDate) ?? text(season.airYear),
			dateAdded: season.dateAdded,
			dateFirstEpisodeWatched: watched.min(), dateLastEpisodeWatched: watched.max(),
			placesToWatch: [], collections: collections,
			verdictDistribution: RatingDistribution.verdicts(season.rating),
			starDistribution: RatingDistribution.stars(ratings.stars),
			numberOfEpisodes: episodes.count,
			episodes: episodes.map { episode($0, in: season, of: show, portrait: portrait, collections: collections) },
			handPickedStars: season.stars, ratedAt: season.ratedAt,
			posterURL: text(season.posterURL), airYear: text(season.airYear))
	}

	private func episode(_ episode: Episode, in season: Season, of show: Show, portrait: String?,
	                     collections: [Row.CollectionRef]) -> Row.EpisodeRecord {
		let tmdbID = episode.tmdbShowID ?? show.tmdbID
		return Row.EpisodeRecord(
			id: episode.id, code: ShowFacts.code(episode), seasonNumber: episode.seasonNumber,
			episodeNumber: episode.episodeNumber, title: episode.displayTitle, status: episode.status.rawValue,
			ratings: Row.Ratings(stars: nil, verdict: episode.episodeTier?.rawValue, note: nil),
			images: Row.Images(portrait: portrait, landscape: text(episode.stillURL) ?? text(show.backdropURL)),
			trailer: tmdbID.map {
				Row.Trailer(tmdbID: $0, videosPath: "/tv/\($0)/season/\(episode.seasonNumber)/episode/\(episode.episodeNumber)/videos")
			},
			synopsis: episode.synopsis, genre: show.genre,
			runtimeMinutes: episode.runtimeMinutes ?? episode.specs?.runtimeMinutes,
			releaseDate: text(episode.airDate), dateAdded: season.dateAdded,
			dateWatched: episode.watchedAt, placesToWatch: [], collections: collections,
			verdictDistribution: RatingDistribution.episodeRatings(episode.episodeTier),
			starDistribution: RatingDistribution.stars(nil),
			imdbID: episode.imdbID,
			stillURL: text(episode.stillURL), specs: episode.specs, tmdbShowID: episode.tmdbShowID)
	}

	// MARK: Pieces

	private func ratings(_ title: some Rated, note: String?) -> Row.Ratings {
		Row.Ratings(stars: title.shownStars, verdict: title.rating?.rawValue, note: text(note))
	}

	private func collectionRefs(_ titleID: UUID) -> [Row.CollectionRef] {
		collections.filter { $0.titleIDs.contains(titleID) }.map { Row.CollectionRef(id: $0.id, name: $0.name) }
	}

	private func episodeRef(_ episode: Episode) -> Row.EpisodeRef {
		Row.EpisodeRef(code: ShowFacts.code(episode), seasonNumber: episode.seasonNumber,
		               episodeNumber: episode.episodeNumber, title: episode.displayTitle,
		               airDate: text(episode.airDate))
	}

	/// Nil for an empty or missing string, so the file says "null" rather than "".
	private func text(_ value: String?) -> String? {
		guard let value, !value.isEmpty else { return nil }
		return value
	}
}

/// The export as a document the system's Save sheet can write.
public nonisolated struct ExportDocument: FileDocument {
	public static var readableContentTypes: [UTType] { [.json] }

	public let data: Data

	public init(data: Data) {
		self.data = data
	}

	public init(configuration: ReadConfiguration) throws {
		data = configuration.file.regularFileContents ?? Data()
	}

	public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		FileWrapper(regularFileWithContents: data)
	}
}
