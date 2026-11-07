//
//  LibraryRestoreTests.swift
//  WatchListTests
//
//  Restore puts back what Export wrote, and only ever adds: a title already in
//  the library comes through untouched. And the versioned schema opens a store
//  written the way the app opened it before there was one.
//

import Foundation
import SwiftData
import Testing
@testable import WatchList

@MainActor
struct LibraryRestoreTests {

	private func memoryContext() throws -> ModelContext {
		let schema = Schema(versionedSchema: LibrarySchemaV1.self)
		let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
		return ModelContext(container)
	}

	/// A library with a rated show (two seasons, a picked still), a film with
	/// aspects and specs, a collection of both and a Discover decision.
	private func populate(_ context: ModelContext) -> (show: Show, film: Film) {
		let show = Show(title: "Severance", tmdbID: 95396, status: .watching, rating: .goForIt, notes: "Odd")
		show.posterURL = "poster.jpg"
		show.backdropURL = "backdrop.jpg"
		show.stars = 4.5
		show.likedAspects = ["Story"]
		context.insert(show)
		for number in [1, 2] {
			let season = Season(seasonNumber: number, airYear: "2022", rating: number == 1 ? .perfection : nil)
			season.show = show
			context.insert(season)
			for n in 1...2 {
				let episode = Episode(episodeNumber: n, seasonNumber: number, title: "S\(number)E\(n)",
				                      stillURL: n == 1 ? "still.jpg" : "", airDate: "2022-02-1\(n)",
				                      runtimeMinutes: 50, tmdbShowID: 95396)
				episode.season = season
				context.insert(episode)
				if number == 1 { episode.mark(.watched) }
			}
		}
		show.sortedSeasons[0].sortedEpisodes[1].episodeTier = .rewatch

		let film = Film(title: "Sicario", year: "2015", tmdbID: 273481,
		                specs: TechSpecs(runtimeMinutes: 121, releaseDate: "2015-09-18", budget: 30_000_000),
		                rating: .perfection, notes: "Tense")
		film.mark(.watched)
		film.dislikedAspects = ["Pacing"]
		context.insert(film)
		context.insert(TitleCollection(name: "Comfort", titleIDs: [film.id, show.id]))
		context.insert(SuggestionDecision(key: "film-1", choice: .notInterested))
		return (show, film)
	}

	private func exported(_ context: ModelContext) throws -> Data {
		try LibraryExport(shows: context.fetch(FetchDescriptor<Show>()),
		                  films: context.fetch(FetchDescriptor<Film>()),
		                  collections: context.fetch(FetchDescriptor<TitleCollection>()),
		                  decisions: context.fetch(FetchDescriptor<SuggestionDecision>())).encoded()
	}

	@Test func aRoundTripIntoAnEmptyLibraryPutsEverythingBack() throws {
		let source = try memoryContext()
		let original = populate(source)
		let data = try exported(source)

		let target = try memoryContext()
		let report = try LibraryRestore.restore(try LibraryRestore.read(data), into: target)
		#expect(report.showsAdded == 1)
		#expect(report.filmsAdded == 1)
		#expect(report.collectionsAdded == 1)
		#expect(report.decisionsAdded == 1)

		let show = try #require(try target.fetch(FetchDescriptor<Show>()).first)
		#expect(show.id == original.show.id)
		#expect(show.rating == .goForIt)
		#expect(show.stars == 4.5)
		#expect(show.likedAspects == ["Story"])
		#expect(show.notes == "Odd")
		#expect(show.seasons.count == 2)
		#expect(show.episodeCount == 4)
		#expect(show.watchedEpisodeCount == 2)
		let s1 = show.sortedSeasons[0]
		#expect(s1.rating == .perfection)
		#expect(s1.posterURL == "")                                 // its own, not the show's
		#expect(s1.sortedEpisodes[0].stillURL == "still.jpg")
		#expect(s1.sortedEpisodes[1].stillURL == "")                // not the show's backdrop
		#expect(s1.sortedEpisodes[1].episodeTier == .rewatch)
		#expect(s1.sortedEpisodes[0].tmdbShowID == 95396)

		let film = try #require(try target.fetch(FetchDescriptor<Film>()).first)
		#expect(film.status == .watched)
		#expect(film.watchedAt != nil)
		#expect(film.specs?.budget == 30_000_000)
		#expect(film.dislikedAspects == ["Pacing"])
		#expect(film.stars == nil)                                  // the verdict's own, not picked

		let collection = try #require(try target.fetch(FetchDescriptor<TitleCollection>()).first)
		#expect(Set(collection.titleIDs) == [original.film.id, original.show.id])
	}

	@Test func aTitleAlreadyHereIsLeftAlone() throws {
		let source = try memoryContext()
		populate(source)
		let data = try exported(source)

		// The same film added again since, and rated differently.
		let target = try memoryContext()
		let mine = Film(title: "Sicario", tmdbID: 273481, status: .toWatch, rating: .skip)
		target.insert(mine)
		let report = try LibraryRestore.restore(try LibraryRestore.read(data), into: target)

		#expect(report.filmsAdded == 0)
		#expect(report.alreadyHere == 1)
		let films = try target.fetch(FetchDescriptor<Film>())
		#expect(films.count == 1)
		#expect(films[0].rating == .skip)
		// The collection points at the film that's here.
		let collection = try #require(try target.fetch(FetchDescriptor<TitleCollection>()).first)
		#expect(collection.titleIDs.contains(mine.id))
	}

	@Test func restoringTwiceAddsNothingTheSecondTime() throws {
		let source = try memoryContext()
		populate(source)
		let export = try LibraryRestore.read(try exported(source))
		let target = try memoryContext()
		try LibraryRestore.restore(export, into: target)
		let again = try LibraryRestore.restore(export, into: target)
		#expect(!again.addedSomething)
		#expect(again.summary == "Nothing new to add. 2 titles already here were left as they were.")
		#expect(try target.fetch(FetchDescriptor<Show>()).count == 1)
	}

	@Test func aFormat2FileStillRestores() throws {
		let source = try memoryContext()
		populate(source)
		// Strip what format 3 added, as a file from before it would be.
		var json = try #require(try JSONSerialization.jsonObject(with: exported(source)) as? [String: Any])
		json["formatVersion"] = 2
		json["suggestionDecisions"] = nil
		let v3Film = ["handPickedStars", "ratedAt", "likedAspects", "dislikedAspects", "specs", "year"]
		json["films"] = (json["films"] as! [[String: Any]]).map { $0.filter { !v3Film.contains($0.key) } }
		let v2 = try JSONSerialization.data(withJSONObject: json)

		let target = try memoryContext()
		let report = try LibraryRestore.restore(try LibraryRestore.read(v2), into: target)
		#expect(report.filmsAdded == 1)
		let film = try #require(try target.fetch(FetchDescriptor<Film>()).first)
		#expect(film.year == "2015")                                // from the release date
		#expect(film.specs?.runtimeMinutes == 121)
	}

	@Test func somethingElseIsTurnedAway() {
		#expect(throws: LibraryRestore.RestoreError.self) {
			try LibraryRestore.read(Data(#"{"hello":"world"}"#.utf8))
		}
	}

	@Test func theSummaryReadsWell() {
		#expect(LibraryRestore.Report(showsAdded: 2, filmsAdded: 1).summary == "Restored 2 shows and 1 film.")
		#expect(LibraryRestore.Report(showsAdded: 1, filmsAdded: 3, collectionsAdded: 2).summary
		        == "Restored 1 show, 3 films and 2 collections.")
	}
}

// MARK: - The versioned store

@MainActor
struct LibrarySchemaTests {

	@Test func aStoreFromBeforeTheSchemaWasVersionedOpensWithEverythingInIt() throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let url = directory.appendingPathComponent("default.store")

		// Written the way WatchListApp opened the store until now.
		do {
			let old = try ModelContainer(for: Show.self, Season.self, Episode.self, Film.self, TitleCollection.self,
			                             SuggestionDecision.self, configurations: ModelConfiguration(url: url))
			let context = ModelContext(old)
			let show = Show(title: "Kept", status: .watching)
			context.insert(show)
			let season = Season(seasonNumber: 1)
			season.show = show
			context.insert(season)
			context.insert(Film(title: "Also kept", rating: .goForIt))
			try context.save()
		}

		let reopened = ModelContext(try LibraryStore.open(at: url))
		#expect(try reopened.fetch(FetchDescriptor<Show>()).map(\.title) == ["Kept"])
		#expect(try reopened.fetch(FetchDescriptor<Show>()).first?.seasons.count == 1)
		#expect(try reopened.fetch(FetchDescriptor<Film>()).first?.rating == .goForIt)
	}
}
