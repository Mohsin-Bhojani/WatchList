//
//  Models.swift
//  WatchList
//
//  SwiftData models for the reworked app. The plain values they share with the
//  watch app — a title's kind, watch status, verdict and an episode's rating —
//  are in Shared/LibraryValues.swift.
//
//  Hierarchy:
//    Show  ->  Season  ->  Episode      (TV)
//    Film                                (movies)
//    TitleCollection                     (your own collections, by title id)
//    SuggestionDecision                  (Discover suggestions turned down or put off)
//
//  Watched dates, verdict dates and hand-picked stars live on the titles
//  themselves, kept in step with status and verdict by WatchTracking.swift.
//
//  - Synopses live on Shows, Episodes and Films.
//  - Technical specs live on Films and Episodes only (per the product spec).
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Enums

// MediaKind, WatchStatus, Rating and EpisodeTier are in Shared/LibraryValues.swift,
// shared with the watch app.

// MARK: - Technical specs (value type persisted by SwiftData)

/// A bundle of "technical spec" facts. Populated from TMDb during import, and
/// shown on Film and Episode pages. Stored as a Codable value on the model.
struct TechSpecs: Codable, Hashable {
	var runtimeMinutes: Int?
	var releaseDate: String?
	var status: String?            // e.g. "Released", "Returning Series", "Ended"
	var originalLanguage: String?
	var spokenLanguages: [String] = []
	var productionCompanies: [String] = []
	var productionCountries: [String] = []
	var budget: Int?
	var revenue: Int?
	var voteAverage: Double?
	var voteCount: Int?
	var productionCode: String?
	var tmdbID: Int?
	var imdbID: String?
	var homepage: String?

	/// True when there is at least one populated field worth rendering.
	var hasContent: Bool {
		runtimeMinutes != nil || releaseDate?.isEmpty == false || status?.isEmpty == false ||
		originalLanguage?.isEmpty == false || !spokenLanguages.isEmpty || !productionCompanies.isEmpty ||
		!productionCountries.isEmpty || budget != nil || revenue != nil || voteAverage != nil ||
		productionCode?.isEmpty == false || homepage?.isEmpty == false
	}
}

// MARK: - Show

@Model
final class Show {
	var id: UUID
	var title: String
	var overview: String            // synopsis
	var genre: String
	var firstAirYear: String
	var posterURL: String
	var backdropURL: String
	var imdbID: String?
	var tmdbID: Int?
	var status: WatchStatus
	var rating: Rating?
	/// Stars picked by hand; nil shows the verdict's own.
	var stars: Double?
	/// When its verdict was last given or changed; nil while it has none.
	var ratedAt: Date?
	var notes: String
	var dateAdded: Date
	/// When it was marked Watched; nil while it isn't.
	var watchedAt: Date?

	@Relationship(deleteRule: .cascade, inverse: \Season.show)
	var seasons: [Season]

	init(title: String,
	     overview: String = "",
	     genre: String = "",
	     firstAirYear: String = "",
	     posterURL: String = "",
	     backdropURL: String = "",
	     imdbID: String? = nil,
	     tmdbID: Int? = nil,
	     status: WatchStatus = .toWatch,
	     rating: Rating? = nil,
	     notes: String = "") {
		self.id = UUID()
		self.title = title
		self.overview = overview
		self.genre = genre
		self.firstAirYear = firstAirYear
		self.posterURL = posterURL
		self.backdropURL = backdropURL
		self.imdbID = imdbID
		self.tmdbID = tmdbID
		self.status = status
		self.rating = rating
		self.ratedAt = rating == nil ? nil : Date()
		self.notes = notes
		self.dateAdded = Date()
		self.watchedAt = status == .watched ? Date() : nil
		self.seasons = []
	}

	var sortedSeasons: [Season] { seasons.sorted { $0.seasonNumber < $1.seasonNumber } }
	var episodeCount: Int { seasons.reduce(0) { $0 + $1.episodes.count } }
	var watchedEpisodeCount: Int { seasons.reduce(0) { $0 + $1.episodes.filter { $0.status == .watched }.count } }
	var subtitle: String {
		let s = seasons.count
		return "\(s) \(s == 1 ? "season" : "seasons") · \(episodeCount) ep"
	}
}

// MARK: - Season

@Model
final class Season {
	var id: UUID
	var seasonNumber: Int
	var name: String
	var overview: String
	var posterURL: String
	var airYear: String
	var status: WatchStatus
	var rating: Rating?
	/// Stars picked by hand; nil shows the verdict's own.
	var stars: Double?
	/// When its verdict was last given or changed; nil while it has none.
	var ratedAt: Date?
	var dateAdded: Date
	var show: Show?

	@Relationship(deleteRule: .cascade, inverse: \Episode.season)
	var episodes: [Episode]

	init(seasonNumber: Int,
	     name: String = "",
	     overview: String = "",
	     posterURL: String = "",
	     airYear: String = "",
	     status: WatchStatus = .toWatch,
	     rating: Rating? = nil) {
		self.id = UUID()
		self.seasonNumber = seasonNumber
		self.name = name.isEmpty ? "Season \(seasonNumber)" : name
		self.overview = overview
		self.posterURL = posterURL
		self.airYear = airYear
		self.status = status
		self.rating = rating
		self.ratedAt = rating == nil ? nil : Date()
		self.dateAdded = Date()
		self.episodes = []
	}

	var sortedEpisodes: [Episode] { episodes.sorted { $0.episodeNumber < $1.episodeNumber } }
	var watchedCount: Int { episodes.filter { $0.status == .watched }.count }
	var displayName: String { name.isEmpty ? "Season \(seasonNumber)" : name }
}

// MARK: - Episode

@Model
final class Episode {
	var id: UUID
	var episodeNumber: Int
	var seasonNumber: Int
	var title: String
	var synopsis: String            // pulled from TMDb
	var stillURL: String
	var airDate: String
	var runtimeMinutes: Int?
	var specs: TechSpecs?           // technical specs (films + episodes only)
	var status: WatchStatus
	var episodeTier: EpisodeTier?   // Skip / Watch / Rewatch (episode-only rating)
	var watchedAt: Date?            // when it was marked Watched; nil while it isn't
	var imdbID: String?             // this episode's own IMDb id, for the link out
	var tmdbShowID: Int?            // needed to resolve episode external ids
	var season: Season?

	init(episodeNumber: Int,
	     seasonNumber: Int,
	     title: String,
	     synopsis: String = "",
	     stillURL: String = "",
	     airDate: String = "",
	     runtimeMinutes: Int? = nil,
	     specs: TechSpecs? = nil,
	     status: WatchStatus = .toWatch,
	     episodeTier: EpisodeTier? = nil,
	     imdbID: String? = nil,
	     tmdbShowID: Int? = nil) {
		self.id = UUID()
		self.episodeNumber = episodeNumber
		self.seasonNumber = seasonNumber
		self.title = title
		self.synopsis = synopsis
		self.stillURL = stillURL
		self.airDate = airDate
		self.runtimeMinutes = runtimeMinutes
		self.specs = specs
		self.status = status
		self.episodeTier = episodeTier
		self.watchedAt = status == .watched ? Date() : nil
		self.imdbID = imdbID
		self.tmdbShowID = tmdbShowID
	}

	var code: String { String(format: "S%02dE%02d", seasonNumber, episodeNumber) }
	var displayTitle: String { title.isEmpty ? "Episode \(episodeNumber)" : title }
}

// MARK: - Film

@Model
final class Film {
	var id: UUID
	var title: String
	var synopsis: String            // pulled from TMDb
	var genre: String
	var year: String
	var posterURL: String
	var backdropURL: String
	var imdbID: String?
	var tmdbID: Int?
	var specs: TechSpecs?           // technical specs
	var status: WatchStatus
	var rating: Rating?
	/// Stars picked by hand; nil shows the verdict's own.
	var stars: Double?
	/// When its verdict was last given or changed; nil while it has none.
	var ratedAt: Date?
	var notes: String
	var dateAdded: Date
	/// When it was marked Watched; nil while it isn't.
	var watchedAt: Date?

	init(title: String,
	     synopsis: String = "",
	     genre: String = "",
	     year: String = "",
	     posterURL: String = "",
	     backdropURL: String = "",
	     imdbID: String? = nil,
	     tmdbID: Int? = nil,
	     specs: TechSpecs? = nil,
	     status: WatchStatus = .toWatch,
	     rating: Rating? = nil,
	     notes: String = "") {
		self.id = UUID()
		self.title = title
		self.synopsis = synopsis
		self.genre = genre
		self.year = year
		self.posterURL = posterURL
		self.backdropURL = backdropURL
		self.imdbID = imdbID
		self.tmdbID = tmdbID
		self.specs = specs
		self.status = status
		self.rating = rating
		self.ratedAt = rating == nil ? nil : Date()
		self.notes = notes
		self.dateAdded = Date()
		self.watchedAt = status == .watched ? Date() : nil
	}
}

// MARK: - Collection

/// One of your own collections: a name and the titles in it, in the order they
/// were added. Titles are kept by id, so a title can be in any number of
/// collections and deleting a collection never deletes a title.
@Model
final class TitleCollection {
	var id: UUID
	var name: String
	/// Show and film ids: in the order they were added, until you reorder them.
	var titleIDs: [UUID]
	var created: Date

	init(name: String, titleIDs: [UUID] = [], created: Date = .now) {
		self.id = UUID()
		self.name = name
		self.titleIDs = titleIDs
		self.created = created
	}
}

// MARK: - Discover

/// What you did with one of Discover's suggestions. Adding one needs no record:
/// being in the library keeps it out of the queue.
enum SuggestionChoice: String, Codable {
	/// Never offered again.
	case notInterested
	/// Back of the queue, offered again once the fresh suggestions run out.
	case later
}

@Model
final class SuggestionDecision {
	/// The title's kind and TMDb id, as `AddCandidate` keys them.
	@Attribute(.unique) var key: String
	var choice: SuggestionChoice
	var decidedAt: Date

	init(key: String, choice: SuggestionChoice, decidedAt: Date = .now) {
		self.key = key
		self.choice = choice
		self.decidedAt = decidedAt
	}
}

// MARK: - IMDb helpers

enum IMDb {
	/// Extracts an IMDb title id (e.g. "tt0468569") from a pasted link or raw id.
	static func id(from raw: String) -> String? {
		let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }
		if let match = trimmed.range(of: "tt[0-9]+", options: .regularExpression) {
			return String(trimmed[match])
		}
		return nil
	}

	static func titleURL(_ id: String) -> URL? { URL(string: "https://www.imdb.com/title/\(id)/") }

	/// Deep-links to a specific season's episode list on the show's IMDb page.
	static func seasonURL(_ id: String, season: Int) -> URL? {
		URL(string: "https://www.imdb.com/title/\(id)/episodes/?season=\(season)")
	}
}
