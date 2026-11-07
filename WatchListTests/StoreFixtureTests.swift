//
//  StoreFixtureTests.swift
//  WatchListTests
//
//  A real library store, as people's phones hold it, opened by today's code.
//
//  Fixtures/LibraryV1.store was written by the app's code as of format 1 of
//  the schema (LibrarySchemaV1), with a show part-watched and rated, its
//  seasons and episodes, a film with tech specs, a collection and a Discover
//  decision. If a change to the models — or moving them, as into the
//  WatchListKit package — stopped that store opening or lost anything in it,
//  this fails before the change reaches anyone's library.
//
//  To write a new fixture (only when the schema gains a version), run the
//  tests with TEST_RUNNER_WRITE_STORE_FIXTURE set to a folder, then fold the
//  store's WAL into it: sqlite3 LibraryV1.store "PRAGMA journal_mode=DELETE;"
//

import Foundation
import SwiftData
import Testing
@testable import WatchList
@testable import WatchListCore
@testable import WatchListLibrary

/// Everything the fixture holds, with fixed dates so the check is exact.
@MainActor
enum StoreFixture {
	static let showID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
	static let filmID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
	static let collectionID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
	static let added = Date(timeIntervalSince1970: 1_780_000_000)
	static let watched = Date(timeIntervalSince1970: 1_780_100_000)
	static let rated = Date(timeIntervalSince1970: 1_780_200_000)

	static func populate(_ context: ModelContext) throws {
		let show = Show(title: "Severance", overview: "Work and life, severed.", genre: "Drama, Mystery",
		                firstAirYear: "2022", posterURL: "https://image.tmdb.org/t/p/w500/p.jpg",
		                backdropURL: "https://image.tmdb.org/t/p/w780/b.jpg", imdbID: "tt11280740",
		                tmdbID: 95396, status: .watching, rating: .goForIt, notes: "Odd and good")
		show.id = showID
		show.dateAdded = added
		show.stars = 4.5
		show.ratedAt = rated
		show.likedAspects = ["Story", "Acting"]
		show.dislikedAspects = ["Pacing"]
		context.insert(show)
		for number in 1...2 {
			let season = Season(seasonNumber: number, name: "Season \(number)", overview: "S\(number)",
			                    posterURL: number == 1 ? "https://image.tmdb.org/t/p/w500/s1.jpg" : "",
			                    airYear: "202\(number + 1)", status: number == 1 ? .watched : .watching,
			                    rating: number == 1 ? .perfection : nil)
			season.dateAdded = added
			if number == 1 { season.ratedAt = rated }
			season.show = show
			context.insert(season)
			for n in 1...3 {
				let episode = Episode(episodeNumber: n, seasonNumber: number, title: "S\(number)E\(n)",
				                      synopsis: "Episode \(n).", stillURL: "https://image.tmdb.org/t/p/w300/e\(n).jpg",
				                      airDate: "202\(number + 1)-02-1\(n)", runtimeMinutes: 50 + n,
				                      specs: TechSpecs(runtimeMinutes: 50 + n, releaseDate: "202\(number + 1)-02-1\(n)",
				                                       voteAverage: 8.5, tmdbID: 1000 + n),
				                      imdbID: "tt99\(number)\(n)", tmdbShowID: 95396)
				if number == 1 || n == 1 {
					episode.status = .watched
					episode.watchedAt = watched
				}
				if number == 1 && n == 2 { episode.episodeTier = .rewatch }
				episode.season = season
				context.insert(episode)
			}
		}

		let film = Film(title: "Sicario", synopsis: "Across the border.", genre: "Thriller", year: "2015",
		                posterURL: "https://image.tmdb.org/t/p/w500/f.jpg", imdbID: "tt3397884", tmdbID: 273481,
		                specs: TechSpecs(runtimeMinutes: 121, releaseDate: "2015-09-18", status: "Released",
		                                 originalLanguage: "en", spokenLanguages: ["English", "Spanish"],
		                                 productionCompanies: ["Lionsgate"], budget: 30_000_000, revenue: 84_900_000),
		                status: .watched, rating: .perfection, notes: "Tense")
		film.id = filmID
		film.dateAdded = added
		film.watchedAt = watched
		film.ratedAt = rated
		context.insert(film)

		let collection = TitleCollection(name: "Comfort", titleIDs: [filmID, showID], created: added)
		collection.id = collectionID
		context.insert(collection)
		context.insert(SuggestionDecision(key: "film-603", choice: .notInterested, decidedAt: added))
		try context.save()
	}

	/// Checks everything `populate` wrote came back, field by field.
	static func expectIntact(_ context: ModelContext) throws {
		let show = try #require(try context.fetch(FetchDescriptor<Show>()).first)
		#expect(show.id == showID)
		#expect(show.title == "Severance")
		#expect(show.status == .watching)
		#expect(show.rating == .goForIt)
		#expect(show.stars == 4.5)
		#expect(show.ratedAt == rated)
		#expect(show.notes == "Odd and good")
		#expect(show.likedAspects == ["Story", "Acting"])
		#expect(show.dislikedAspects == ["Pacing"])
		#expect(show.tmdbID == 95396)
		#expect(show.dateAdded == added)
		#expect(show.seasons.count == 2)
		#expect(show.episodeCount == 6)
		#expect(show.watchedEpisodeCount == 4)

		let s1 = show.sortedSeasons[0]
		#expect(s1.status == .watched)
		#expect(s1.rating == .perfection)
		#expect(s1.posterURL.hasSuffix("s1.jpg"))
		let e2 = s1.sortedEpisodes[1]
		#expect(e2.episodeTier == .rewatch)
		#expect(e2.watchedAt == watched)
		#expect(e2.specs?.voteAverage == 8.5)
		#expect(e2.tmdbShowID == 95396)
		#expect(show.sortedSeasons[1].sortedEpisodes[1].status == .toWatch)

		let film = try #require(try context.fetch(FetchDescriptor<Film>()).first)
		#expect(film.id == filmID)
		#expect(film.status == .watched)
		#expect(film.rating == .perfection)
		#expect(film.specs?.budget == 30_000_000)
		#expect(film.specs?.spokenLanguages == ["English", "Spanish"])
		#expect(film.watchedAt == watched)

		let collection = try #require(try context.fetch(FetchDescriptor<TitleCollection>()).first)
		#expect(collection.id == collectionID)
		#expect(collection.titleIDs == [filmID, showID])

		let decision = try #require(try context.fetch(FetchDescriptor<SuggestionDecision>()).first)
		#expect(decision.key == "film-603")
		#expect(decision.choice == .notInterested)
	}
}

private final class BundleToken {}

@MainActor
struct StoreFixtureTests {

	@Test func theCommittedStoreOpensWithEverythingInIt() throws {
		let fixture = try #require(Bundle(for: BundleToken.self).url(forResource: "LibraryV1", withExtension: "store"))
		// A copy, so opening it never changes the committed file.
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let copy = directory.appendingPathComponent("default.store")
		try FileManager.default.copyItem(at: fixture, to: copy)

		try StoreFixture.expectIntact(ModelContext(try LibraryStore.open(at: copy)))
	}

	/// Writes the fixture; does nothing unless asked to (see the top of the file).
	@Test func writeFixtureWhenAsked() throws {
		guard let folder = ProcessInfo.processInfo.environment["WRITE_STORE_FIXTURE"] else { return }
		let url = URL(fileURLWithPath: folder).appendingPathComponent("LibraryV1.store")
		for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
		let container = try LibraryStore.open(at: url)
		try StoreFixture.populate(ModelContext(container))
	}
}
