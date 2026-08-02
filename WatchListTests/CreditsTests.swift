//
//  CreditsTests.swift
//  WatchListTests
//
//  Covers the parts of the Cast and Similar tabs that are pure logic: decoding
//  what TMDb's credits and similar endpoints actually return, and the mapping
//  that turns them into rows — sort order, the guest-star and multi-role cases,
//  and which genres two titles share.
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
		let built = CreditsLoader.episodeCredits(from: credits)

		#expect(built.directedBy == "Rahul Pandey")
		#expect(built.writtenBy == "Kunal Aneja")
	}

	@Test func flagsGuestStarsAndLeavesRegularsPlain() throws {
		let credits: TMDbCredits = try decode(json)
		let built = CreditsLoader.episodeCredits(from: credits)

		#expect(built.people.map(\.name) == ["Ravi Kishan", "Yashpal Sharma"])
		#expect(built.people[0].flag == .none)
		#expect(built.people[1].flag == .guestStar)
	}

	@Test func doesNotListSomeoneTwice() throws {
		let credits: TMDbCredits = try decode(json)
		let built = CreditsLoader.episodeCredits(from: credits)

		// Ravi Kishan appears in both arrays; the regular billing wins.
		#expect(built.people.filter { $0.id == 1 }.count == 1)
	}

	@Test func joinsSeveralWritersAndTakesAlternateWritingJobs() throws {
		let credits: TMDbCredits = try decode("""
		{"crew":[{"id":1,"name":"A","job":"Teleplay"},{"id":2,"name":"B","job":"Story"},
		         {"id":3,"name":"A","job":"Writer"}]}
		""")
		let built = CreditsLoader.episodeCredits(from: credits)

		// "A" is credited twice under different jobs but is named once.
		#expect(built.writtenBy == "A, B")
	}

	@Test func anUnairedEpisodeIsEmpty() throws {
		let credits: TMDbCredits = try decode("{\"cast\":[],\"crew\":[],\"guest_stars\":[]}")
		#expect(CreditsLoader.episodeCredits(from: credits).isEmpty)
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
