//
//  SimilarTests.swift
//  WatchListTests
//
//  Covers the parts of the Similar feature that are pure logic: the taste
//  profile the app builds from your ratings, the fingerprint that decides
//  when a cached batch is stale, and decoding what the Mac helper returns.
//
//  These ran without an Anthropic API key, which is the point — they pin the
//  behaviour that sits either side of the network call.
//

import Foundation
import Testing
@testable import WatchList

// MARK: - Taste profile

@MainActor
struct TasteProfileTests {

	private func show(_ title: String, rating: Rating?, genre: String = "Drama", year: String = "2020") -> Show {
		let s = Show(title: title, genre: genre, firstAirYear: year)
		s.rating = rating
		return s
	}

	private func film(_ title: String, rating: Rating?, genre: String = "Drama", year: String = "2020") -> Film {
		let f = Film(title: title, genre: genre, year: year)
		f.rating = rating
		return f
	}

	@Test func bucketsTitlesByRating() {
		let profile = SimilarLoader.buildProfile(
			shows: [show("Loved", rating: .perfection), show("Liked", rating: .goForIt)],
			films: [film("Meh", rating: .timepass), film("Hated", rating: .skip), film("Unrated", rating: nil)]
		)

		#expect(profile.dto.perfection.map(\.title) == ["Loved"])
		#expect(profile.dto.goForIt.map(\.title) == ["Liked"])
		#expect(Set(profile.dto.avoid.map(\.title)) == ["Meh", "Hated"])
		#expect(profile.lovedCount == 1)
		#expect(profile.likedCount == 1)
	}

	@Test func unratedTitlesAreExcludedFromEveryBucket() {
		let profile = SimilarLoader.buildProfile(shows: [show("Unrated", rating: nil)], films: [])

		#expect(profile.dto.perfection.isEmpty)
		#expect(profile.dto.goForIt.isEmpty)
		#expect(profile.dto.avoid.isEmpty)
		// ...but it still counts as "already in the library".
		#expect(profile.exclude.contains("Unrated"))
	}

	@Test func everyLibraryTitleIsExcludedRegardlessOfRating() {
		let profile = SimilarLoader.buildProfile(
			shows: [show("A", rating: .perfection), show("B", rating: nil)],
			films: [film("C", rating: .skip)]
		)
		#expect(Set(profile.exclude) == ["A", "B", "C"])
	}

	@Test func genreIsTrimmedToTwoTokens() {
		let profile = SimilarLoader.buildProfile(
			shows: [show("X", rating: .perfection, genre: "Action, Drama, Sci-Fi, Thriller")],
			films: []
		)
		#expect(profile.dto.perfection.first?.genre == "Action/Drama")
	}

	@Test func avoidBucketCarriesNoGenre() {
		// Deliberate: what they disliked is a weaker signal, so it gets fewer
		// tokens in the prompt.
		let profile = SimilarLoader.buildProfile(
			shows: [], films: [film("Bad", rating: .skip, genre: "Comedy, Romance")]
		)
		#expect(profile.dto.avoid.first?.genre == nil)
	}

	@Test func bucketsAreCapped() {
		let loved = (1...40).map { show("Loved \($0)", rating: .perfection) }
		let liked = (1...40).map { show("Liked \($0)", rating: .goForIt) }
		let bad   = (1...40).map { film("Bad \($0)", rating: .skip) }

		let profile = SimilarLoader.buildProfile(shows: loved + liked, films: bad)

		#expect(profile.dto.perfection.count == 25)
		#expect(profile.dto.goForIt.count == 25)
		#expect(profile.dto.avoid.count == 15)
	}

	@Test func excludeIsCappedAtTwoHundred() {
		let many = (1...300).map { show("Title \($0)", rating: nil) }
		let profile = SimilarLoader.buildProfile(shows: many, films: [])
		#expect(profile.exclude.count == 200)
	}

	@Test func showsAndFilmsUseTheirOwnYearFields() {
		// Show stores firstAirYear, Film stores year — easy to cross-wire.
		let profile = SimilarLoader.buildProfile(
			shows: [show("S", rating: .perfection, year: "1999")],
			films: [film("F", rating: .perfection, year: "2015")]
		)
		let byTitle = Dictionary(uniqueKeysWithValues: profile.dto.perfection.map { ($0.title, $0) })
		#expect(byTitle["S"]?.year == "1999")
		#expect(byTitle["S"]?.kind == "show")
		#expect(byTitle["F"]?.year == "2015")
		#expect(byTitle["F"]?.kind == "film")
	}

	// MARK: Fingerprint

	@Test func fingerprintIsStableAcrossCalls() {
		// The whole cache policy rests on this. A per-process hash (hashValue)
		// would pass here but change on the next launch.
		let a = SimilarLoader.buildProfile(shows: [show("X", rating: .perfection)], films: [])
		let b = SimilarLoader.buildProfile(shows: [show("X", rating: .perfection)], films: [])
		#expect(a.fingerprint == b.fingerprint)
		#expect(!a.fingerprint.isEmpty)
	}

	@Test func fingerprintIgnoresLibraryOrder() {
		let a = SimilarLoader.buildProfile(
			shows: [show("A", rating: .perfection), show("B", rating: .goForIt)], films: [])
		let b = SimilarLoader.buildProfile(
			shows: [show("B", rating: .goForIt), show("A", rating: .perfection)], films: [])
		#expect(a.fingerprint == b.fingerprint)
	}

	@Test func fingerprintChangesWhenARatingChanges() {
		let before = SimilarLoader.buildProfile(shows: [show("X", rating: .goForIt)], films: [])
		let after  = SimilarLoader.buildProfile(shows: [show("X", rating: .perfection)], films: [])
		#expect(before.fingerprint != after.fingerprint)
	}

	@Test func fingerprintIgnoresUnratedAdditions() {
		// Adding something you haven't rated shouldn't invalidate a batch it
		// played no part in producing.
		let a = SimilarLoader.buildProfile(shows: [show("Rated", rating: .perfection)], films: [])
		let b = SimilarLoader.buildProfile(
			shows: [show("Rated", rating: .perfection), show("New", rating: nil)], films: [])
		#expect(a.fingerprint == b.fingerprint)
	}
}

// MARK: - Wire decoding

struct SuggestionDecodingTests {

	@Test func decodesTheHelperResponse() throws {
		let json = """
		{"version":1,"model":"claude-opus-5","suggestions":[
		  {"title":"The Leftovers","year":"2014","kind":"show","reason":"Same interior dread."},
		  {"title":"Arrival","year":"2016","kind":"film","reason":"Patient and strange."}]}
		""".data(using: .utf8)!

		struct Envelope: Decodable { let suggestions: [SuggestionDTO] }
		let decoded = try JSONDecoder().decode(Envelope.self, from: json)

		#expect(decoded.suggestions.count == 2)
		#expect(decoded.suggestions[0].title == "The Leftovers")
		#expect(decoded.suggestions[0].mediaKind == .show)
		#expect(decoded.suggestions[1].mediaKind == .film)
	}

	@Test func unknownKindFallsBackToFilm() {
		// MediaKind.rawValue is capitalised ("Show"), the wire is lowercase —
		// anything unexpected must not crash.
		let dto = SuggestionDTO(title: "X", year: "2020", kind: "documentary", reason: "")
		#expect(dto.mediaKind == .film)
	}

	@Test func profilePayloadEncodesLowercaseKinds() throws {
		let dto = TasteProfileDTO(
			perfection: [TasteTitleDTO(title: "S", year: "2022", kind: "show", genre: "Drama")],
			goForIt: [], avoid: [])
		let data = try JSONEncoder().encode(dto)
		let text = String(decoding: data, as: UTF8.self)

		#expect(text.contains("\"kind\":\"show\""))
		#expect(!text.contains("\"Show\""))
	}
}

// MARK: - Config

/// Serialized: these all read and write the same UserDefaults keys, and Swift
/// Testing runs tests in parallel by default — left concurrent they clobber
/// each other's host value.
@Suite(.serialized)
struct SimilarConfigTests {

	@Test(arguments: ["127.0.0.1", "localhost", "::1", "LOCALHOST"])
	func recognisesLoopback(_ host: String) {
		UserDefaults.standard.set(host, forKey: "similarProxyHost")
		defer { UserDefaults.standard.removeObject(forKey: "similarProxyHost") }
		#expect(SimilarConfig.isLoopback)
	}

	@Test func lanAddressIsNotLoopback() {
		UserDefaults.standard.set("192.168.0.198", forKey: "similarProxyHost")
		defer { UserDefaults.standard.removeObject(forKey: "similarProxyHost") }
		#expect(!SimilarConfig.isLoopback)
	}

	@Test func buildsAUsableURL() {
		UserDefaults.standard.set("192.168.0.198", forKey: "similarProxyHost")
		UserDefaults.standard.set(8787, forKey: "similarProxyPort")
		defer {
			UserDefaults.standard.removeObject(forKey: "similarProxyHost")
			UserDefaults.standard.removeObject(forKey: "similarProxyPort")
		}
		#expect(SimilarConfig.url(path: "/health")?.absoluteString == "http://192.168.0.198:8787/health")
	}
}

// MARK: - Model

struct SuggestionModelTests {

	@Test func isAddableOnlyOnceTMDbMatched() {
		let s = Suggestion(title: "X", year: "2020", kind: .film, reason: "", rank: 0, profileFingerprint: "fp")
		#expect(!s.isAddable)
		s.tmdbID = 550
		#expect(s.isAddable)
	}

	@Test func subtitleReadsWellWithAndWithoutAYear() {
		let withYear = Suggestion(title: "X", year: "2020", kind: .show, reason: "", rank: 0, profileFingerprint: "fp")
		#expect(withYear.subtitle == "2020 · TV Series")

		let noYear = Suggestion(title: "X", year: "", kind: .film, reason: "", rank: 0, profileFingerprint: "fp")
		#expect(noYear.subtitle == "Film")
	}
}
