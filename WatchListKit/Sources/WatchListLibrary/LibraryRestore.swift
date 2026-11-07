//
//  LibraryRestore.swift
//  WatchList
//
//  Settings' Restore: reads a file Export wrote and puts its titles back.
//
//  It only adds. A title already in the library — the same one, or the same
//  TMDb title added again since — is left exactly as it is, so restoring an old
//  file can never cost you a watched mark or a rating given since. Collections
//  already here gain the restored titles they held; ones that aren't come back
//  whole. Ids are kept, so a collection and its titles find each other again.
//
//  A format 2 file has no hand-picked stars, aspects, tech specs or stored
//  artwork of its own (LibraryExport.swift); those are filled in from what it
//  does have, and the daily refresh tops up the rest from TMDb.
//

import Foundation
import SwiftData
import WatchListCore

public enum LibraryRestore {

	public struct Report: Equatable {
		public var showsAdded = 0
		public var filmsAdded = 0
		public var collectionsAdded = 0
		public var collectionsMerged = 0
		public var decisionsAdded = 0
		/// Titles in the file that were already in the library.
		public var alreadyHere = 0

		public var addedSomething: Bool {
			showsAdded + filmsAdded + collectionsAdded + collectionsMerged + decisionsAdded > 0
		}

		/// Phrased for a settings row.
		public var summary: String {
			var parts: [String] = []
			if showsAdded > 0 { parts.append(count(showsAdded, "show")) }
			if filmsAdded > 0 { parts.append(count(filmsAdded, "film")) }
			if collectionsAdded > 0 { parts.append(count(collectionsAdded, "collection")) }
			var line = parts.isEmpty ? "Nothing new to add." : "Restored " + Self.joined(parts) + "."
			if alreadyHere > 0 {
				line += " \(count(alreadyHere, "title")) already here \(alreadyHere == 1 ? "was" : "were") left as \(alreadyHere == 1 ? "it was" : "they were")."
			}
			return line
		}

		private func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }

		private static func joined(_ parts: [String]) -> String {
			guard parts.count > 1 else { return parts.first ?? "" }
			return parts.dropLast().joined(separator: ", ") + " and " + parts.last!
		}
	}

	public enum RestoreError: LocalizedError {
		case notAnExport

		public var errorDescription: String? {
			"That file isn't a WatchList export."
		}
	}

	/// Reads `data` as an export, or says why it can't.
	public static func read(_ data: Data) throws -> LibraryExport {
		guard let export = try? LibraryExport.decoded(from: data), export.app == "WatchList" else {
			throw RestoreError.notAnExport
		}
		return export
	}

	/// Adds what `export` holds that the library doesn't, into `context`.
	@discardableResult
	public static func restore(_ export: LibraryExport, into context: ModelContext) throws -> Report {
		let shows = try context.fetch(FetchDescriptor<Show>())
		let films = try context.fetch(FetchDescriptor<Film>())
		let collections = try context.fetch(FetchDescriptor<TitleCollection>())
		let decisions = try context.fetch(FetchDescriptor<SuggestionDecision>())

		var report = Report()
		/// The file's title ids as they are in the library after this.
		var ids: [UUID: UUID] = [:]

		let showsByID = Dictionary(shows.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
		let showsByTMDb = Dictionary(shows.compactMap { s in s.tmdbID.map { ($0, s) } }, uniquingKeysWith: { a, _ in a })
		for record in export.shows {
			if let here = showsByID[record.id] ?? record.tmdbID.flatMap({ showsByTMDb[$0] }) {
				ids[record.id] = here.id
				report.alreadyHere += 1
				continue
			}
			insert(show(from: record), into: context)
			ids[record.id] = record.id
			report.showsAdded += 1
		}

		let filmsByID = Dictionary(films.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
		let filmsByTMDb = Dictionary(films.compactMap { f in f.tmdbID.map { ($0, f) } }, uniquingKeysWith: { a, _ in a })
		for record in export.films {
			if let here = filmsByID[record.id] ?? record.tmdbID.flatMap({ filmsByTMDb[$0] }) {
				ids[record.id] = here.id
				report.alreadyHere += 1
				continue
			}
			context.insert(film(from: record))
			ids[record.id] = record.id
			report.filmsAdded += 1
		}

		let collectionsByID = Dictionary(collections.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
		for record in export.collections {
			let titleIDs = record.titleIDs.compactMap { ids[$0] }
			if let here = collectionsByID[record.id] {
				let missing = titleIDs.filter { !here.titleIDs.contains($0) }
				if !missing.isEmpty {
					here.titleIDs.append(contentsOf: missing)
					report.collectionsMerged += 1
				}
				continue
			}
			let collection = TitleCollection(name: record.name, titleIDs: titleIDs, created: record.created)
			collection.id = record.id
			context.insert(collection)
			report.collectionsAdded += 1
		}

		let decided = Set(decisions.map(\.key))
		for record in export.suggestionDecisions ?? [] where !decided.contains(record.key) {
			guard let choice = SuggestionChoice(rawValue: record.choice) else { continue }
			context.insert(SuggestionDecision(key: record.key, choice: choice, decidedAt: record.decidedAt))
			report.decisionsAdded += 1
		}

		try context.save()
		return report
	}

	// MARK: Records to models

	private static func insert(_ show: Show, into context: ModelContext) {
		context.insert(show)
		for season in show.seasons {
			context.insert(season)
			for episode in season.episodes { context.insert(episode) }
		}
	}

	public static func film(from r: LibraryExport.FilmRecord) -> Film {
		let verdict = r.ratings.verdict.flatMap(Rating.init(rawValue:))
		let film = Film(title: r.title, synopsis: r.synopsis, genre: r.genre,
		                year: r.year ?? year(of: r.releaseDate),
		                posterURL: r.images.portrait ?? "", backdropURL: r.images.landscape ?? "",
		                imdbID: r.imdbID, tmdbID: r.tmdbID,
		                specs: r.specs ?? fallbackSpecs(runtime: r.runtimeMinutes, releaseDate: r.releaseDate),
		                status: status(r.status), notes: r.ratings.note ?? "")
		film.id = r.id
		film.dateAdded = r.dateAdded
		film.watchedAt = film.status == .watched ? (r.dateWatched ?? r.dateAdded) : nil
		rate(film, verdict: verdict, handPicked: r.handPickedStars, shown: r.ratings.stars,
		     ratedAt: r.ratedAt, fallbackDate: r.dateWatched ?? r.dateAdded)
		film.likedAspects = r.likedAspects ?? []
		film.dislikedAspects = r.dislikedAspects ?? []
		return film
	}

	public static func show(from r: LibraryExport.ShowRecord) -> Show {
		let verdict = r.ratings.verdict.flatMap(Rating.init(rawValue:))
		let poster = r.images.portrait ?? ""
		let backdrop = r.images.landscape ?? ""
		let show = Show(title: r.title, overview: r.synopsis, genre: r.genre,
		                firstAirYear: r.firstAirYear ?? year(of: r.airingDate),
		                posterURL: poster, backdropURL: backdrop,
		                imdbID: r.imdbID, tmdbID: r.tmdbID, status: status(r.status), notes: r.ratings.note ?? "")
		show.id = r.id
		show.dateAdded = r.dateAdded
		show.watchedAt = show.status == .watched ? (r.dateWatched ?? r.dateFirstEpisodeWatched ?? r.dateAdded) : nil
		rate(show, verdict: verdict, handPicked: r.handPickedStars, shown: r.ratings.stars,
		     ratedAt: r.ratedAt, fallbackDate: r.dateAdded)
		show.likedAspects = r.likedAspects ?? []
		show.dislikedAspects = r.dislikedAspects ?? []

		for s in r.seasons {
			let season = Season(seasonNumber: s.seasonNumber, name: s.name, overview: s.synopsis,
			                    // Format 2 wrote the show's poster where a season had none.
			                    posterURL: s.posterURL ?? (s.images.portrait == poster ? "" : s.images.portrait ?? ""),
			                    airYear: s.airYear ?? year(of: s.releaseDate),
			                    status: status(s.status))
			season.id = s.id
			season.dateAdded = s.dateAdded
			rate(season, verdict: s.ratings.verdict.flatMap(Rating.init(rawValue:)), handPicked: s.handPickedStars,
			     shown: s.ratings.stars, ratedAt: s.ratedAt, fallbackDate: s.dateAdded)
			season.show = show
			show.seasons.append(season)

			for e in s.episodes {
				let episode = Episode(episodeNumber: e.episodeNumber, seasonNumber: e.seasonNumber, title: e.title,
				                      synopsis: e.synopsis,
				                      // Format 2 wrote the show's backdrop where an episode had no still.
				                      stillURL: e.stillURL ?? (e.images.landscape == backdrop ? "" : e.images.landscape ?? ""),
				                      airDate: e.releaseDate ?? "", runtimeMinutes: e.runtimeMinutes,
				                      specs: e.specs, status: status(e.status),
				                      episodeTier: e.ratings.verdict.flatMap(EpisodeTier.init(rawValue:)),
				                      imdbID: e.imdbID, tmdbShowID: e.tmdbShowID ?? r.tmdbID)
				episode.id = e.id
				episode.watchedAt = episode.status == .watched ? (e.dateWatched ?? e.dateAdded) : nil
				episode.season = season
				season.episodes.append(episode)
			}
		}
		return show
	}

	// MARK: Pieces

	/// The verdict and stars as they were: hand-picked stars when the file has
	/// them, otherwise the shown stars kept only where they differ from the
	/// verdict's own.
	private static func rate(_ title: some Rated, verdict: Rating?, handPicked: Double?, shown: Double?,
	                         ratedAt: Date?, fallbackDate: Date) {
		title.rating = verdict
		let own: Double? = if let verdict { StarRating.stars(for: verdict) } else { nil }
		let picked = handPicked ?? (shown == own ? nil : shown)
		title.stars = StarRating.explicit(picked, afterChoosing: verdict)
		title.ratedAt = verdict == nil ? nil : (ratedAt ?? fallbackDate)
	}

	private static func status(_ raw: String) -> WatchStatus {
		WatchStatus(rawValue: raw) ?? .toWatch
	}

	private static func year(of date: String?) -> String {
		String((date ?? "").prefix(4))
	}

	private static func fallbackSpecs(runtime: Int?, releaseDate: String?) -> TechSpecs? {
		guard runtime != nil || releaseDate != nil else { return nil }
		return TechSpecs(runtimeMinutes: runtime, releaseDate: releaseDate)
	}
}
