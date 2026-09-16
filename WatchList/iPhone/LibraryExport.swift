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

import SwiftUI
import UniformTypeIdentifiers

struct LibraryExport: Codable {
	var app = "WatchList"
	var formatVersion = 2
	var exportedAt: Date
	var films: [FilmRecord]
	var shows: [ShowRecord]
	var collections: [CollectionRecord]
}

// MARK: - Rows

extension LibraryExport {
	struct Ratings: Codable, Equatable {
		var stars: Double?
		/// A verdict — or, for an episode, its Skip / Watch / Rewatch.
		var verdict: String?
		var note: String?
	}

	struct Images: Codable, Equatable {
		var portrait: String?
		var landscape: String?
	}

	/// Where TMDb lists the title's videos. The trailer itself isn't fetched
	/// yet, so `youtubeKey` stays empty.
	struct Trailer: Codable, Equatable {
		var tmdbID: Int
		var videosPath: String
		var youtubeKey: String? = nil
	}

	struct CollectionRef: Codable, Equatable {
		var id: UUID
		var name: String
	}

	struct EpisodeRef: Codable, Equatable {
		var code: String
		var seasonNumber: Int
		var episodeNumber: Int
		var title: String
		var airDate: String?
	}

	struct FilmRecord: Codable {
		var id: UUID
		var title: String
		var status: String
		var ratings: Ratings
		var images: Images
		var trailer: Trailer?
		var synopsis: String
		var genre: String
		var runtimeMinutes: Int?
		var releaseDate: String?
		var dateAdded: Date
		var dateWatched: Date?
		var placesToWatch: [String]
		var collections: [CollectionRef]
		var verdictDistribution: [String: Int]
		var starDistribution: [String: Int]
		var imdbID: String?
		var tmdbID: Int?
	}

	struct ShowRecord: Codable {
		var id: UUID
		var title: String
		var status: String
		var ratings: Ratings
		var images: Images
		var trailer: Trailer?
		var synopsis: String
		var genre: String
		/// The episode after the one most recently marked Watched.
		var nextEpisode: EpisodeRef?
		/// The first season's first episode's air date.
		var airingDate: String?
		var dateAdded: Date
		var dateFirstEpisodeWatched: Date?
		var placesToWatch: [String]
		var collections: [CollectionRef]
		var verdictDistribution: [String: Int]
		var starDistribution: [String: Int]
		var numberOfSeasons: Int
		var seasons: [SeasonRecord]
		var imdbID: String?
		var tmdbID: Int?
	}

	struct SeasonRecord: Codable {
		var id: UUID
		var seasonNumber: Int
		var name: String
		var status: String
		var ratings: Ratings
		var images: Images
		var trailer: Trailer?
		var synopsis: String
		var genre: String
		/// Its episodes' runtimes added up.
		var runtimeMinutes: Int?
		var releaseDate: String?
		var dateAdded: Date
		var dateFirstEpisodeWatched: Date?
		var dateLastEpisodeWatched: Date?
		var placesToWatch: [String]
		var collections: [CollectionRef]
		var verdictDistribution: [String: Int]
		var starDistribution: [String: Int]
		var numberOfEpisodes: Int
		var episodes: [EpisodeRecord]
	}

	struct EpisodeRecord: Codable {
		var id: UUID
		var code: String
		var seasonNumber: Int
		var episodeNumber: Int
		var title: String
		var status: String
		var ratings: Ratings
		var images: Images
		var trailer: Trailer?
		var synopsis: String
		var genre: String
		var runtimeMinutes: Int?
		var releaseDate: String?
		var dateAdded: Date
		var dateWatched: Date?
		var placesToWatch: [String]
		var collections: [CollectionRef]
		var verdictDistribution: [String: Int]
		var starDistribution: [String: Int]
		var imdbID: String?
	}

	struct CollectionRecord: Codable {
		var id: UUID
		var name: String
		var created: Date
		var titleIDs: [UUID]
		/// The same titles by name, for reading the file by eye.
		var titles: [String]
	}
}

// MARK: - Distributions

/// A title's rating distributions. Until there are other people's ratings to
/// count, each is this person's own: one on the rating given, or all zero.
enum RatingDistribution {
	static func verdicts(_ rating: Rating?) -> [String: Int] {
		Dictionary(uniqueKeysWithValues: Rating.allCases.map { ($0.rawValue, $0 == rating ? 1 : 0) })
	}

	static func episodeRatings(_ tier: EpisodeTier?) -> [String: Int] {
		Dictionary(uniqueKeysWithValues: EpisodeTier.allCases.map { ($0.rawValue, $0 == tier ? 1 : 0) })
	}

	/// "0", "0.5" … "5".
	static func stars(_ value: Double?) -> [String: Int] {
		Dictionary(uniqueKeysWithValues: StarRating.values.map { (StarRating.label($0), $0 == value ? 1 : 0) })
	}
}

// MARK: - Building

extension LibraryExport {
	/// Films and shows A–Z, seasons and episodes in number order, collections
	/// as they're listed.
	init(shows: [Show], films: [Film], collections: [TitleCollection], now: Date = .now) {
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
	}

	/// Pretty-printed with sorted keys and ISO 8601 dates, so it reads and
	/// compares well.
	func encoded() throws -> Data {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
		encoder.dateEncodingStrategy = .iso8601
		return try encoder.encode(self)
	}

	/// "WatchList Export 2026-09-14", dated in the given time zone.
	static func defaultFilename(for date: Date, timeZone: TimeZone = .current) -> String {
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
			imdbID: film.imdbID, tmdbID: film.tmdbID)
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
			imdbID: show.imdbID, tmdbID: show.tmdbID)
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
			episodes: episodes.map { episode($0, in: season, of: show, portrait: portrait, collections: collections) })
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
			imdbID: episode.imdbID)
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
nonisolated struct ExportDocument: FileDocument {
	static var readableContentTypes: [UTType] { [.json] }

	let data: Data

	init(data: Data) {
		self.data = data
	}

	init(configuration: ReadConfiguration) throws {
		data = configuration.file.regularFileContents ?? Data()
	}

	func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
		FileWrapper(regularFileWithContents: data)
	}
}
