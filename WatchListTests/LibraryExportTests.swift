//
//  LibraryExportTests.swift
//  WatchListTests
//
//  Settings' JSON export: that every film, show, season and episode row
//  carries everything about it, and that the file reads back.
//

import Foundation
import Testing
@testable import WatchList

@MainActor
struct LibraryExportTests {

	private let now = Date(timeIntervalSince1970: 1_800_000_000)

	/// A show with two seasons — S1 E1 and E2 Watched, S2 E1 not — a rated film,
	/// an unrated one, and a collection holding the rated film and the show.
	private func library() -> (show: Show, film: Film, unrated: Film, collection: TitleCollection) {
		let show = Show(title: "Severance", tmdbID: 95396, status: .watching, rating: .goForIt, notes: "Weird and good")
		show.posterURL = "poster.jpg"
		show.backdropURL = "backdrop.jpg"
		show.genre = "Drama, Mystery"
		show.stars = 4.5
		for number in [1, 2] {
			let season = Season(seasonNumber: number, rating: number == 1 ? .perfection : nil)
			season.show = show
			show.seasons.append(season)
			for episodeNumber in number == 1 ? [2, 1] : [1] {
				let episode = Episode(episodeNumber: episodeNumber, seasonNumber: number, title: "S\(number)E\(episodeNumber)",
				                      stillURL: "still-\(number)-\(episodeNumber).jpg",
				                      airDate: "2022-02-\(10 + number + episodeNumber)", runtimeMinutes: 50)
				episode.season = season
				season.episodes.append(episode)
				if number == 1 {
					episode.mark(.watched, at: now.addingTimeInterval(Double(episodeNumber) * 60))
				}
			}
		}
		show.sortedSeasons[0].sortedEpisodes[1].episodeTier = .rewatch

		let film = Film(title: "Sicario", tmdbID: 273481,
		                specs: TechSpecs(runtimeMinutes: 121, releaseDate: "2015-09-18"),
		                rating: .perfection, notes: "Tense")
		film.mark(.watched, at: now)
		let unrated = Film(title: "Arrival")
		let collection = TitleCollection(name: "Comfort", titleIDs: [film.id, show.id], created: now)
		return (show, film, unrated, collection)
	}

	@Test func aFilmRowHasEverythingAboutIt() throws {
		let lib = library()
		let export = LibraryExport(shows: [lib.show], films: [lib.film, lib.unrated],
		                           collections: [lib.collection], now: now)

		#expect(export.films.map(\.title) == ["Arrival", "Sicario"])
		let film = try #require(export.films.last)
		#expect(film.ratings == .init(stars: 5, verdict: "Perfection", note: "Tense"))
		#expect(film.trailer == .init(tmdbID: 273481, videosPath: "/movie/273481/videos"))
		#expect(film.runtimeMinutes == 121)
		#expect(film.releaseDate == "2015-09-18")
		#expect(film.dateWatched == now)
		#expect(film.placesToWatch.isEmpty)
		#expect(film.collections.map(\.name) == ["Comfort"])
		#expect(film.verdictDistribution == ["Perfection": 1, "Go For It": 0, "Timepass": 0, "Skip": 0])
		#expect(film.starDistribution.count == 11)
		#expect(film.starDistribution["5"] == 1)
		#expect(film.starDistribution.values.reduce(0, +) == 1)

		let unrated = try #require(export.films.first)
		#expect(unrated.ratings == .init(stars: nil, verdict: nil, note: nil))
		#expect(unrated.verdictDistribution.values.allSatisfy { $0 == 0 })
		#expect(unrated.starDistribution.values.allSatisfy { $0 == 0 })
		#expect(unrated.images == .init(portrait: nil, landscape: nil))
		#expect(unrated.trailer == nil)
	}

	@Test func aShowSeasonAndEpisodeEachCarryTheirOwn() throws {
		let lib = library()
		let export = LibraryExport(shows: [lib.show], films: [lib.film], collections: [lib.collection], now: now)

		let show = try #require(export.shows.first)
		#expect(show.ratings == .init(stars: 4.5, verdict: "Go For It", note: "Weird and good"))
		#expect(show.images == .init(portrait: "poster.jpg", landscape: "backdrop.jpg"))
		#expect(show.trailer?.videosPath == "/tv/95396/videos")
		#expect(show.nextEpisode?.code == "S2 E1")
		#expect(show.airingDate == "2022-02-12")
		#expect(show.dateFirstEpisodeWatched == now.addingTimeInterval(60))
		#expect(show.numberOfSeasons == 2)
		#expect(show.starDistribution["4.5"] == 1)

		let season = try #require(show.seasons.first)
		#expect(season.ratings == .init(stars: 5, verdict: "Perfection", note: nil))
		#expect(season.images == .init(portrait: "poster.jpg", landscape: "still-1-1.jpg"))
		#expect(season.trailer?.videosPath == "/tv/95396/season/1/videos")
		#expect(season.genre == "Drama, Mystery")
		#expect(season.runtimeMinutes == 100)
		#expect(season.releaseDate == "2022-02-12")
		#expect(season.dateFirstEpisodeWatched == now.addingTimeInterval(60))
		#expect(season.dateLastEpisodeWatched == now.addingTimeInterval(120))
		#expect(season.numberOfEpisodes == 2)
		#expect(season.collections.map(\.name) == ["Comfort"])

		let episode = try #require(season.episodes.last)
		#expect(episode.code == "S1 E2")
		#expect(episode.ratings == .init(stars: nil, verdict: "Rewatch", note: nil))
		#expect(episode.images == .init(portrait: "poster.jpg", landscape: "still-1-2.jpg"))
		#expect(episode.trailer?.videosPath == "/tv/95396/season/1/episode/2/videos")
		#expect(episode.dateWatched == now.addingTimeInterval(120))
		#expect(episode.runtimeMinutes == 50)
		#expect(episode.collections.map(\.name) == ["Comfort"])
		#expect(episode.verdictDistribution == ["Rewatch": 1, "Watch": 0, "Skip": 0])
		#expect(episode.starDistribution.values.allSatisfy { $0 == 0 })
	}

	@Test func theFileReadsBack() throws {
		let lib = library()
		let export = LibraryExport(shows: [lib.show], films: [lib.film], collections: [lib.collection], now: now)
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let readBack = try decoder.decode(LibraryExport.self, from: export.encoded())
		#expect(readBack.formatVersion == 2)
		#expect(readBack.exportedAt == now)
		#expect(readBack.shows.first?.seasons.first?.episodes.count == 2)
		#expect(readBack.collections.first?.titles == ["Sicario", "Severance"])
	}

	@Test func theFileIsNamedForTheDay() throws {
		let noonUTC = Date(timeIntervalSince1970: 1_800_014_400)   // 15 Jan 2027, 12:00 UTC
		let utc = try #require(TimeZone(identifier: "UTC"))
		#expect(LibraryExport.defaultFilename(for: noonUTC, timeZone: utc) == "WatchList Export 2027-01-15")
	}
}
