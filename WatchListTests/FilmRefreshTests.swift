//
//  FilmRefreshTests.swift
//  WatchListTests
//
//  Refresh metadata on a film: it takes what TMDb has changed and names it,
//  and leaves alone everything that's yours — the rating, the note, and
//  artwork picked by hand.
//

import Foundation
import Testing
@testable import WatchList

@MainActor
struct FilmRefreshTests {

	private func movie(_ json: String) throws -> TMDbMovie {
		try JSONDecoder().decode(TMDbMovie.self, from: Data(json.utf8))
	}

	private let fresh = """
	{"id": 27205, "title": "Inception", "overview": "A thief who steals secrets.",
	 "release_date": "2010-07-15", "poster_path": "/new.jpg", "backdrop_path": "/wide.jpg",
	 "runtime": 148, "vote_average": 8.4, "vote_count": 38000,
	 "genres": [{"name": "Action"}, {"name": "Science Fiction"}],
	 "external_ids": {"imdb_id": "tt1375666"}}
	"""

	@Test func takesWhatChangedAndLeavesYoursAlone() throws {
		let film = Film(title: "Inception", synopsis: "Old synopsis.", genre: "Action, Science Fiction",
		                year: "2010", posterURL: TMDbConfig.poster("/old.jpg"),
		                backdropURL: TMDbConfig.backdrop("/wide.jpg"), tmdbID: 27205,
		                status: .watched, rating: .perfection, notes: "Watch it again")
		let changes = FilmRefresh.apply(try movie(fresh), to: film, keepPoster: false, keepLandscape: false)

		#expect(changes == ["synopsis", "poster", "IMDb link", "runtime", "release date", "TMDb rating"])
		#expect(film.synopsis == "A thief who steals secrets.")
		#expect(film.posterURL == TMDbConfig.poster("/new.jpg"))
		#expect(film.specs?.runtimeMinutes == 148)
		#expect(film.rating == .perfection && film.status == .watched && film.notes == "Watch it again")
	}

	@Test func aHandPickedPosterStays() throws {
		let film = Film(title: "Inception", posterURL: "https://example.com/mine.jpg", tmdbID: 27205)
		let changes = FilmRefresh.apply(try movie(fresh), to: film, keepPoster: true, keepLandscape: true)
		#expect(film.posterURL == "https://example.com/mine.jpg")
		#expect(!changes.contains("poster") && !changes.contains("landscape artwork"))
	}

	@Test func aSecondRefreshFindsNothingAndBlanksDontWipe() throws {
		let film = Film(title: "Inception", tmdbID: 27205)
		FilmRefresh.apply(try movie(fresh), to: film, keepPoster: false, keepLandscape: false)
		#expect(FilmRefresh.apply(try movie(fresh), to: film, keepPoster: false, keepLandscape: false).isEmpty)

		let blank = try movie(#"{"id": 27205, "title": "", "overview": ""}"#)
		FilmRefresh.apply(blank, to: film, keepPoster: false, keepLandscape: false)
		#expect(film.title == "Inception" && film.synopsis == "A thief who steals secrets.")
		#expect(film.specs?.runtimeMinutes == 148 && film.specs?.releaseDate == "2010-07-15")
		#expect(film.specs?.voteAverage == 8.4)
	}
}
