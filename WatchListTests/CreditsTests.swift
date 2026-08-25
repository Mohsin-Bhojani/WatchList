//
//  CreditsTests.swift
//  WatchListTests
//
//  Covers the parts of the Cast, Similar and Images tabs that are pure logic:
//  decoding what TMDb's credits, similar and images endpoints actually return,
//  and the mapping that turns them into rows — sort order, the guest-star and
//  multi-role cases, which genres two titles share, and how artwork is grouped.
//  Both the TV and the film shapes, since the two pages share the mapping.
//
//  These need no API key, which is the point: they pin the behaviour either
//  side of the network call.
//

import Foundation
import Testing
@testable import WatchList

private func decode<T: Decodable>(_ json: String) throws -> T {
	try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

// MARK: - Series / season cast

@MainActor
struct AggregateCreditsTests {

	/// Deliberately out of order, and with a tie, so the sort has something to do.
	private let json = """
	{"cast":[
	  {"id":3,"name":"Brijendra Kala","profile_path":"/c.jpg","total_episode_count":9,"order":2,
	   "roles":[{"character":"Munshi ji","episode_count":9}]},
	  {"id":1,"name":"Ravi Kishan","profile_path":"/a.jpg","total_episode_count":16,"order":0,
	   "roles":[{"character":"V.D. Tyagi","episode_count":16}]},
	  {"id":2,"name":"Naila Grrewal","profile_path":null,"total_episode_count":16,"order":1,
	   "roles":[{"character":"Ananya Shroff","episode_count":16}]}
	]}
	"""

	@Test func sortsByEpisodeCountDescending() throws {
		let credits: TMDbAggregateCredits = try decode(json)
		let entries = CreditsLoader.castEntries(from: credits)

		#expect(entries.map(\.name) == ["Ravi Kishan", "Naila Grrewal", "Brijendra Kala"])
		#expect(entries.map(\.episodeCount) == [16, 16, 9])
	}

	@Test func tiesKeepBillingOrder() throws {
		let credits: TMDbAggregateCredits = try decode(json)
		let entries = CreditsLoader.castEntries(from: credits)

		// Both have 16 episodes; TMDb bills Ravi Kishan first, so he stays first.
		#expect(entries[0].id == 1)
		#expect(entries[1].id == 2)
	}

	@Test func buildsProfileURLOnlyWhenTMDbHasOne() throws {
		let credits: TMDbAggregateCredits = try decode(json)
		let entries = CreditsLoader.castEntries(from: credits)

		#expect(entries[0].profileURL.hasSuffix("/w185/a.jpg"))
		#expect(entries[1].profileURL.isEmpty)
	}

	@Test func joinsEveryCharacterAPersonPlayed() throws {
		let credits: TMDbAggregateCredits = try decode("""
		{"cast":[{"id":7,"name":"Tanvi Azmi","total_episode_count":6,
		 "roles":[{"character":"Judge Sharma","episode_count":4},{"character":"Narrator","episode_count":2}]}]}
		""")
		let entries = CreditsLoader.castEntries(from: credits)

		#expect(entries.first?.character == "Judge Sharma, Narrator")
	}

	@Test func survivesMissingFields() throws {
		let credits: TMDbAggregateCredits = try decode("""
		{"cast":[{"id":7,"name":"Nameless"}]}
		""")
		let entries = CreditsLoader.castEntries(from: credits)

		#expect(entries.count == 1)
		#expect(entries[0].character.isEmpty)
		#expect(entries[0].episodeCount == nil)
	}

	@Test func noCastAtAllMapsToNothing() throws {
		let credits: TMDbAggregateCredits = try decode("{}")
		#expect(CreditsLoader.castEntries(from: credits).isEmpty)
	}
}

// MARK: - Episode credits

@MainActor
struct EpisodeCreditsTests {

	private let json = """
	{"cast":[
	  {"id":1,"name":"Ravi Kishan","character":"V.D. Tyagi","profile_path":"/a.jpg","order":0}
	 ],
	 "crew":[
	  {"id":9,"name":"Rahul Pandey","job":"Director","department":"Directing"},
	  {"id":10,"name":"Kunal Aneja","job":"Writer","department":"Writing"},
	  {"id":11,"name":"Someone Else","job":"Editor","department":"Editing"}
	 ],
	 "guest_stars":[
	  {"id":5,"name":"Yashpal Sharma","character":"Advocate","profile_path":null,"order":0},
	  {"id":1,"name":"Ravi Kishan","character":"V.D. Tyagi","profile_path":"/a.jpg","order":0}
	 ]}
	"""

	@Test func pullsDirectorAndWriterFromCrew() throws {
		let credits: TMDbCredits = try decode(json)
		let built = CreditsLoader.titleCredits(from: credits)

		#expect(built.directedBy == "Rahul Pandey")
		#expect(built.writtenBy == "Kunal Aneja")
	}

	@Test func flagsGuestStarsAndLeavesRegularsPlain() throws {
		let credits: TMDbCredits = try decode(json)
		let built = CreditsLoader.titleCredits(from: credits)

		#expect(built.people.map(\.name) == ["Ravi Kishan", "Yashpal Sharma"])
		#expect(built.people[0].flag == .none)
		#expect(built.people[1].flag == .guestStar)
	}

	@Test func doesNotListSomeoneTwice() throws {
		let credits: TMDbCredits = try decode(json)
		let built = CreditsLoader.titleCredits(from: credits)

		// Ravi Kishan appears in both arrays; the regular billing wins.
		#expect(built.people.filter { $0.id == 1 }.count == 1)
	}

	@Test func joinsSeveralWritersAndTakesAlternateWritingJobs() throws {
		let credits: TMDbCredits = try decode("""
		{"crew":[{"id":1,"name":"A","job":"Teleplay"},{"id":2,"name":"B","job":"Story"},
		         {"id":3,"name":"A","job":"Writer"}]}
		""")
		let built = CreditsLoader.titleCredits(from: credits)

		// "A" is credited twice under different jobs but is named once.
		#expect(built.writtenBy == "A, B")
	}

	@Test func anUnairedEpisodeIsEmpty() throws {
		let credits: TMDbCredits = try decode("{\"cast\":[],\"crew\":[],\"guest_stars\":[]}")
		#expect(CreditsLoader.titleCredits(from: credits).isEmpty)
	}
}

// MARK: - Similar

@MainActor
struct SimilarEntryTests {

	private let genreNames = [35: "Comedy", 18: "Drama", 10759: "Action & Adventure"]

	private let json = """
	{"results":[
	  {"id":100,"name":"Panchayat","first_air_date":"2020-04-03","vote_average":8.6,
	   "poster_path":"/p.jpg","genre_ids":[35,18]},
	  {"id":101,"name":"Kota Factory","first_air_date":"2019-04-16","vote_average":8.1,
	   "poster_path":null,"genre_ids":[10759]}
	]}
	"""

	@Test func mapsYearAndVoteAverage() throws {
		let response: TMDbSimilarResponse = try decode(json)
		let entries = CreditsLoader.similarEntries(from: response.results,
		                                           parentGenres: "Comedy, Drama",
		                                           genreNames: genreNames)

		#expect(entries[0].title == "Panchayat")
		#expect(entries[0].year == "2020")
		#expect(entries[0].voteAverage == 8.6)
		#expect(entries[1].posterURL.isEmpty)
	}

	@Test func namesOnlyTheGenresBothTitlesHave() throws {
		let response: TMDbSimilarResponse = try decode(json)
		let entries = CreditsLoader.similarEntries(from: response.results,
		                                           parentGenres: "Comedy, Drama",
		                                           genreNames: genreNames)

		#expect(entries[0].sharedGenres == ["Comedy", "Drama"])
		#expect(entries[1].sharedGenres.isEmpty)
	}

	@Test func sharedGenresFollowTheParentTitlesOrder() throws {
		let response: TMDbSimilarResponse = try decode(json)
		let entries = CreditsLoader.similarEntries(from: response.results,
		                                           parentGenres: "Drama, Comedy",
		                                           genreNames: genreNames)

		#expect(entries[0].sharedGenres == ["Drama", "Comedy"])
	}

	@Test func genreIDsWeCannotNameAreIgnored() throws {
		let response: TMDbSimilarResponse = try decode(json)
		let entries = CreditsLoader.similarEntries(from: response.results,
		                                           parentGenres: "Comedy, Drama",
		                                           genreNames: [:])

		#expect(entries[0].sharedGenres.isEmpty)
	}

	@Test func splitsTheStoredGenreString() {
		#expect(CreditsLoader.splitGenres("Comedy, Drama") == ["Comedy", "Drama"])
		#expect(CreditsLoader.splitGenres("Comedy,Drama ,") == ["Comedy", "Drama"])
		#expect(CreditsLoader.splitGenres("").isEmpty)
	}
}

// MARK: - Similar (films)

/// `/movie/{id}/similar` differs from its TV counterpart only in the two field
/// names, and in resolving genre ids against TMDb's separate movie table.
@MainActor
struct SimilarMovieEntryTests {

	private let genreNames = [28: "Action", 878: "Science Fiction", 12: "Adventure"]

	private let json = """
	{"results":[
	  {"id":200,"title":"Sicario","release_date":"2015-09-17","vote_average":7.4,
	   "poster_path":"/s.jpg","genre_ids":[28]},
	  {"id":201,"title":"The Man from Earth","release_date":"2007-11-13","vote_average":7.6,
	   "poster_path":null,"genre_ids":[878]}
	]}
	"""

	@Test func readsTitleAndReleaseDateRatherThanTheTVFields() throws {
		let response: TMDbSimilarMovieResponse = try decode(json)
		let entries = CreditsLoader.similarEntries(from: response.results,
		                                           parentGenres: "Action, Science Fiction",
		                                           genreNames: genreNames)

		#expect(entries[0].title == "Sicario")
		#expect(entries[0].year == "2015")
		#expect(entries[0].voteAverage == 7.4)
		#expect(entries[1].posterURL.isEmpty)
	}

	@Test func namesOnlyTheGenresBothFilmsHave() throws {
		let response: TMDbSimilarMovieResponse = try decode(json)
		let entries = CreditsLoader.similarEntries(from: response.results,
		                                           parentGenres: "Action, Science Fiction",
		                                           genreNames: genreNames)

		#expect(entries[0].sharedGenres == ["Action"])
		#expect(entries[1].sharedGenres == ["Science Fiction"])
	}

	/// A missing release date must not crash the year prefix.
	@Test func survivesAMissingReleaseDate() throws {
		let response: TMDbSimilarMovieResponse = try decode("""
		{"results":[{"id":202,"title":"Unreleased","release_date":null,"vote_average":null,
		  "poster_path":null,"genre_ids":null}]}
		""")
		let entries = CreditsLoader.similarEntries(from: response.results,
		                                           parentGenres: "Action",
		                                           genreNames: genreNames)

		#expect(entries[0].year.isEmpty)
		#expect(entries[0].voteAverage == 0)
		#expect(entries[0].sharedGenres.isEmpty)
	}
}

// MARK: - Cast (films)

/// A film comes back from the plain `/credits` endpoint: a crew pair, a billed
/// cast in `order`, and no guest stars.
@MainActor
struct MovieCreditsTests {

	private let json = """
	{"cast":[
	  {"id":1,"name":"Leonardo DiCaprio","character":"Dom Cobb","profile_path":"/l.jpg","order":0},
	  {"id":2,"name":"Joseph Gordon-Levitt","character":"Arthur","profile_path":null,"order":1}
	],
	 "crew":[
	  {"id":9,"name":"Christopher Nolan","job":"Director","department":"Directing"},
	  {"id":9,"name":"Christopher Nolan","job":"Screenplay","department":"Writing"},
	  {"id":10,"name":"Emma Thomas","job":"Producer","department":"Production"}
	]}
	"""

	@Test func readsTheDirectorAndWriter() throws {
		let credits: TMDbCredits = try decode(json)
		let built = CreditsLoader.titleCredits(from: credits)

		#expect(built.directedBy == "Christopher Nolan")
		#expect(built.writtenBy == "Christopher Nolan")
	}

	@Test func keepsBillingOrderAndCarriesNoEpisodeCounts() throws {
		let credits: TMDbCredits = try decode(json)
		let built = CreditsLoader.titleCredits(from: credits)

		#expect(built.people.map(\.name) == ["Leonardo DiCaprio", "Joseph Gordon-Levitt"])
		#expect(built.people.allSatisfy { $0.episodeCount == nil })
	}

	/// No `guest_stars` key at all, which is what a film payload looks like.
	@Test func flagsNobodyWhenThereAreNoGuestStars() throws {
		let credits: TMDbCredits = try decode(json)
		let built = CreditsLoader.titleCredits(from: credits)

		#expect(built.people.allSatisfy { $0.flag == .none })
	}
}

// MARK: - Images

@MainActor
struct ImageGalleryTests {

	/// A series payload: posters out of rating order, a backdrop, a logo, and a
	/// poster with no file path — TMDb does return those.
	private let json = """
	{"backdrops":[
	  {"file_path":"/b.jpg","width":1920,"height":1080,"aspect_ratio":1.778,
	   "vote_average":5.3,"iso_639_1":null}
	 ],
	 "logos":[
	  {"file_path":"/l.svg","width":800,"height":310,"vote_average":9,"iso_639_1":"en"},
	  {"file_path":"/l.png","width":800,"height":310,"vote_average":0,"iso_639_1":"en"}
	 ],
	 "posters":[
	  {"file_path":"/low.jpg","width":1000,"height":1500,"vote_average":1.2,"iso_639_1":"hi"},
	  {"file_path":"/best.jpg","width":2000,"height":3000,"vote_average":8.4,"iso_639_1":null},
	  {"file_path":"/wide-tie.jpg","width":1400,"height":2100,"vote_average":1.2,"iso_639_1":""},
	  {"width":500,"height":750,"vote_average":9.9,"iso_639_1":"en"}
	 ]}
	"""

	@Test func groupsRunPostersThenBackdropsThenLogos() throws {
		let set: TMDbImageSet = try decode(json)
		let gallery = CreditsLoader.gallery(from: set)

		#expect(gallery.groups.map(\.kind) == [.poster, .backdrop, .logo])
		#expect(gallery.count == 5)
	}

	@Test func dropsKindsTMDbHasNothingFor() throws {
		// A season payload: posters only, so no empty headings for the rest.
		let set: TMDbImageSet = try decode("""
		{"posters":[{"file_path":"/s.jpg","width":1000,"height":1500,"vote_average":5}]}
		""")
		let gallery = CreditsLoader.gallery(from: set)

		#expect(gallery.groups.map(\.kind) == [.poster])
		#expect(!gallery.isEmpty)
	}

	@Test func anEmptyPayloadIsAnEmptyGallery() throws {
		#expect(CreditsLoader.gallery(from: try decode("{}")).isEmpty)
		#expect(CreditsLoader.gallery(from: try decode("{\"stills\":[]}")).isEmpty)
	}

	@Test func bestRatedFirstWithTheWiderFileBreakingTies() throws {
		let set: TMDbImageSet = try decode(json)
		let posters = CreditsLoader.gallery(from: set).groups[0].entries

		// 8.4 first; the two 1.2s are split by width, widest first.
		#expect(posters.map(\.id) == ["/best.jpg", "/wide-tie.jpg", "/low.jpg"])
	}

	@Test func skipsAnImageWithNoFilePath() throws {
		let set: TMDbImageSet = try decode(json)
		let posters = CreditsLoader.gallery(from: set).groups[0].entries

		// The 9.9-rated entry has no path, so it would otherwise lead the group.
		#expect(posters.count == 3)
	}

	@Test func buildsAThumbnailAndAFullSizeURL() throws {
		let set: TMDbImageSet = try decode(json)
		let best = CreditsLoader.gallery(from: set).groups[0].entries[0]

		#expect(best.thumbURL.hasSuffix("/w342/best.jpg"))
		#expect(best.fullURL.hasSuffix("/original/best.jpg"))
	}

	/// TMDb serves SVG logos as markup at every size, "original" included, so
	/// UIImage can never decode them — they'd be tiles that only ever fail.
	@Test func dropsSVGLogosNothingCanDecode() throws {
		let set: TMDbImageSet = try decode(json)
		let logos = try #require(CreditsLoader.gallery(from: set).groups.last)

		#expect(logos.kind == .logo)
		// The SVG is the better-rated of the two, so it would otherwise lead.
		#expect(logos.entries.map(\.id) == ["/l.png"])
	}

	@Test func aMissingOrEmptyLanguageMeansTextless() throws {
		let set: TMDbImageSet = try decode(json)
		let posters = CreditsLoader.gallery(from: set).groups[0].entries
		let backdrop = try #require(CreditsLoader.gallery(from: set).groups[1].entries.first)

		#expect(posters[0].language == nil)          // null
		#expect(posters[1].language == nil)          // ""
		#expect(posters[2].language == "hi")
		#expect(backdrop.languageLabel == "No text")
	}

	@Test func aspectRatioComesFromTheFileAndFallsBackToTheKind() throws {
		let set: TMDbImageSet = try decode(json)
		let poster = CreditsLoader.gallery(from: set).groups[0].entries[0]
		#expect(abs(poster.aspectRatio - 2.0 / 3.0) < 0.001)
		#expect(poster.dimensions == "2000 × 3000")

		// No width/height at all: the tile still needs a shape to draw.
		let sizeless: TMDbImageSet = try decode("{\"stills\":[{\"file_path\":\"/x.jpg\"}]}")
		let still = try #require(CreditsLoader.gallery(from: sizeless).groups.first?.entries.first)
		#expect(abs(still.aspectRatio - 16.0 / 9.0) < 0.001)
		#expect(still.dimensions.isEmpty)
		#expect(still.voteAverage == 0)
	}

	@Test func theViewerPagesThroughEveryGroupInDisplayOrder() throws {
		let set: TMDbImageSet = try decode(json)
		let gallery = CreditsLoader.gallery(from: set)

		#expect(gallery.all.map(\.kind) == [.poster, .poster, .poster, .backdrop, .logo])
		#expect(gallery.all.count == gallery.count)
	}
}
