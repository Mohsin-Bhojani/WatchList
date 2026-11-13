//
//  Models.swift
//  WatchList
//
//  SwiftData models for the reworked app. The plain values they share with the
//  watch app — a title's kind, watch status, verdict and an episode's rating —
//  are in WatchListCore/LibraryValues.swift.
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
import WatchListCore

// MARK: - Enums

// MediaKind, WatchStatus, Rating and EpisodeTier are in WatchListCore/LibraryValues.swift,
// shared with the watch app.

// MARK: - Technical specs (value type persisted by SwiftData)

/// A bundle of "technical spec" facts. Populated from TMDb during import, and
/// shown on Film and Episode pages. Stored as a Codable value on the model.
public struct TechSpecs: Codable, Hashable {
	public init(runtimeMinutes: Int? = nil, releaseDate: String? = nil, status: String? = nil, originalLanguage: String? = nil, spokenLanguages: [String] = [], productionCompanies: [String] = [], productionCountries: [String] = [], budget: Int? = nil, revenue: Int? = nil, voteAverage: Double? = nil, voteCount: Int? = nil, productionCode: String? = nil, tmdbID: Int? = nil, imdbID: String? = nil, homepage: String? = nil) {
		self.runtimeMinutes = runtimeMinutes
		self.releaseDate = releaseDate
		self.status = status
		self.originalLanguage = originalLanguage
		self.spokenLanguages = spokenLanguages
		self.productionCompanies = productionCompanies
		self.productionCountries = productionCountries
		self.budget = budget
		self.revenue = revenue
		self.voteAverage = voteAverage
		self.voteCount = voteCount
		self.productionCode = productionCode
		self.tmdbID = tmdbID
		self.imdbID = imdbID
		self.homepage = homepage
	}

	public var runtimeMinutes: Int?
	public var releaseDate: String?
	public var status: String?            // e.g. "Released", "Returning Series", "Ended"
	public var originalLanguage: String?
	public var spokenLanguages: [String] = []
	public var productionCompanies: [String] = []
	public var productionCountries: [String] = []
	public var budget: Int?
	public var revenue: Int?
	public var voteAverage: Double?
	public var voteCount: Int?
	public var productionCode: String?
	public var tmdbID: Int?
	public var imdbID: String?
	public var homepage: String?

	/// True when there is at least one populated field worth rendering.
	public var hasContent: Bool {
		runtimeMinutes != nil || releaseDate?.isEmpty == false || status?.isEmpty == false ||
		originalLanguage?.isEmpty == false || !spokenLanguages.isEmpty || !productionCompanies.isEmpty ||
		!productionCountries.isEmpty || budget != nil || revenue != nil || voteAverage != nil ||
		productionCode?.isEmpty == false || homepage?.isEmpty == false
	}
}

// MARK: - Show

@Model
public final class Show {
	public var id: UUID
	public var title: String
	public var overview: String            // synopsis
	public var genre: String
	public var firstAirYear: String
	public var posterURL: String
	public var backdropURL: String
	public var imdbID: String?
	public var tmdbID: Int?
	public var status: WatchStatus
	public var rating: Rating?
	/// Stars picked by hand; nil shows the verdict's own.
	public var stars: Double?
	/// When its verdict was last given or changed; nil while it has none.
	public var ratedAt: Date?
	public var notes: String
	public var dateAdded: Date
	/// When it was marked Watched; nil while it isn't.
	public var watchedAt: Date?
	/// What stood out, picked on the rating card (Aspects.swift). Defaulted, so
	/// a store from before they existed migrates in place.
	public var likedAspects: [String] = []
	public var dislikedAspects: [String] = []

	@Relationship(deleteRule: .cascade, inverse: \Season.show)
	public var seasons: [Season]

	public init(title: String,
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

	public var sortedSeasons: [Season] { seasons.sorted { $0.seasonNumber < $1.seasonNumber } }
	public var episodeCount: Int { seasons.reduce(0) { $0 + $1.episodes.count } }
	public var watchedEpisodeCount: Int { seasons.reduce(0) { $0 + $1.episodes.filter { $0.status == .watched }.count } }
	public var subtitle: String {
		let s = seasons.count
		return "\(s) \(s == 1 ? "season" : "seasons") · \(episodeCount) ep"
	}
}

// MARK: - Season

@Model
public final class Season {
	public var id: UUID
	public var seasonNumber: Int
	public var name: String
	public var overview: String
	public var posterURL: String
	public var airYear: String
	public var status: WatchStatus
	public var rating: Rating?
	/// Stars picked by hand; nil shows the verdict's own.
	public var stars: Double?
	/// When its verdict was last given or changed; nil while it has none.
	public var ratedAt: Date?
	public var dateAdded: Date
	public var show: Show?
	/// The YouTube playlist its episodes play from (YouTubeLibrary.swift); nil
	/// when it has none. Defaulted, so older stores migrate in place.
	public var youtubePlaylistID: String? = nil

	@Relationship(deleteRule: .cascade, inverse: \Episode.season)
	public var episodes: [Episode]

	public init(seasonNumber: Int,
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

	public var sortedEpisodes: [Episode] { episodes.sorted { $0.episodeNumber < $1.episodeNumber } }
	public var watchedCount: Int { episodes.filter { $0.status == .watched }.count }
	public var displayName: String { name.isEmpty ? "Season \(seasonNumber)" : name }
}

// MARK: - Episode

@Model
public final class Episode {
	public var id: UUID
	public var episodeNumber: Int
	public var seasonNumber: Int
	public var title: String
	public var synopsis: String            // pulled from TMDb
	public var stillURL: String
	public var airDate: String
	public var runtimeMinutes: Int?
	public var specs: TechSpecs?           // technical specs (films + episodes only)
	public var status: WatchStatus
	public var episodeTier: EpisodeTier?   // Skip / Watch / Rewatch (episode-only rating)
	public var watchedAt: Date?            // when it was marked Watched; nil while it isn't
	public var imdbID: String?             // this episode's own IMDb id, for the link out
	public var tmdbShowID: Int?            // needed to resolve episode external ids
	public var season: Season?
	/// The YouTube video it plays from, matched from its season's playlist.
	public var youtubeVideoID: String? = nil

	public init(episodeNumber: Int,
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

	public var displayTitle: String { title.isEmpty ? "Episode \(episodeNumber)" : title }
}

// MARK: - Film

@Model
public final class Film {
	public var id: UUID
	public var title: String
	public var synopsis: String            // pulled from TMDb
	public var genre: String
	public var year: String
	public var posterURL: String
	public var backdropURL: String
	public var imdbID: String?
	public var tmdbID: Int?
	public var specs: TechSpecs?           // technical specs
	public var status: WatchStatus
	public var rating: Rating?
	/// Stars picked by hand; nil shows the verdict's own.
	public var stars: Double?
	/// When its verdict was last given or changed; nil while it has none.
	public var ratedAt: Date?
	public var notes: String
	public var dateAdded: Date
	/// When it was marked Watched; nil while it isn't.
	public var watchedAt: Date?
	/// What stood out, picked on the rating card (Aspects.swift). Defaulted, so
	/// a store from before they existed migrates in place.
	public var likedAspects: [String] = []
	public var dislikedAspects: [String] = []
	/// The film series TMDb puts it in (Franchises.swift); nil when it's in
	/// none or hasn't been looked up. Defaulted, so older stores migrate in place.
	public var franchiseID: Int? = nil
	public var franchiseName: String? = nil
	/// When TMDb was last asked which series it's in; nil until it has been.
	public var franchiseCheckedAt: Date? = nil

	public init(title: String,
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
public final class TitleCollection {
	public var id: UUID
	public var name: String
	/// Show and film ids, in the order they were added.
	public var titleIDs: [UUID]
	public var created: Date

	public init(name: String, titleIDs: [UUID] = [], created: Date = .now) {
		self.id = UUID()
		self.name = name
		self.titleIDs = titleIDs
		self.created = created
	}
}

// MARK: - Discover

/// What you did with one of Discover's suggestions. Adding one needs no record:
/// being in the library keeps it out of the queue.
public enum SuggestionChoice: String, Codable {
	/// Never offered again.
	case notInterested
	/// Back of the queue, offered again once the fresh suggestions run out.
	case later
}

@Model
public final class SuggestionDecision {
	/// The title's kind and TMDb id, as `AddCandidate` keys them.
	@Attribute(.unique) public var key: String
	public var choice: SuggestionChoice
	public var decidedAt: Date

	public init(key: String, choice: SuggestionChoice, decidedAt: Date = .now) {
		self.key = key
		self.choice = choice
		self.decidedAt = decidedAt
	}
}

// MARK: - IMDb helpers

public enum IMDb {
	/// Extracts an IMDb title id (e.g. "tt0468569") from a pasted link or raw id.
	public static func id(from raw: String) -> String? {
		let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }
		if let match = trimmed.range(of: "tt[0-9]+", options: .regularExpression) {
			return String(trimmed[match])
		}
		return nil
	}

	public static func titleURL(_ id: String) -> URL? { URL(string: "https://www.imdb.com/title/\(id)/") }

	/// Deep-links to a specific season's episode list on the show's IMDb page.
	public static func seasonURL(_ id: String, season: Int) -> URL? {
		URL(string: "https://www.imdb.com/title/\(id)/episodes/?season=\(season)")
	}
}
