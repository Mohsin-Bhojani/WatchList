//
//  WhereToWatchTests.swift
//  WatchListTests
//
//  Which of a title's videos plays as its trailer, and how where-to-watch
//  offers are grouped for one region.
//

import Foundation
import Testing
@testable import WatchList
@testable import WatchListCore
@testable import WatchListLibrary

@MainActor
struct WhereToWatchTests {

	private func video(_ key: String, type: String = "Trailer", site: String = "YouTube", official: Bool = true,
	                   language: String = "en", published: String = "2024-01-01") -> TMDbVideo {
		TMDbVideo(key: key, site: site, type: type, official: official, iso_639_1: language,
		          published_at: published, name: key)
	}

	@Test func anOfficialEnglishTrailerWins() {
		let picked = TitleExtras.trailer(from: [
			video("teaser", type: "Teaser"),
			video("fan", official: false),
			video("french", language: "fr"),
			video("clip", type: "Clip"),
			video("vimeo", site: "Vimeo"),
			video("official"),
		])
		#expect(picked?.key == "official")
	}

	@Test func theNewestOfEquallyGoodTrailers() {
		let picked = TitleExtras.trailer(from: [video("old", published: "2023-01-01"), video("new", published: "2025-06-01")])
		#expect(picked?.key == "new")
	}

	@Test func aTeaserWhenThereIsNoTrailerAndNothingForClipsOnly() {
		#expect(TitleExtras.trailer(from: [video("teaser", type: "Teaser"), video("clip", type: "Clip")])?.key == "teaser")
		#expect(TitleExtras.trailer(from: [video("clip", type: "Clip")]) == nil)
	}

	private func providers(_ json: String) throws -> TMDbWatchProviders {
		try JSONDecoder().decode(TMDbWatchProviders.self, from: Data(json.utf8))
	}

	@Test func offersAreGroupedAndOrderedForTheRegion() throws {
		let all = try providers(#"""
		{"results":{
		  "GB":{"link":"https://www.themoviedb.org/movie/1/watch?locale=GB",
		        "flatrate":[{"provider_id":2,"provider_name":"Later","display_priority":5},
		                    {"provider_id":1,"provider_name":"First","logo_path":"/a.png","display_priority":1}],
		        "free":[{"provider_id":9,"provider_name":"Free TV","display_priority":1}],
		        "ads":[{"provider_id":9,"provider_name":"Free TV","display_priority":1},
		               {"provider_id":8,"provider_name":"Ad TV","display_priority":2}],
		        "buy":[{"provider_id":3,"provider_name":"Shop","display_priority":1}]},
		  "US":{"flatrate":[{"provider_id":4,"provider_name":"Elsewhere"}]}}}
		"""#)
		let gb = try #require(TitleExtras.availability(all, region: "GB"))
		#expect(gb.offers.map(\.kind) == [.stream, .free, .buy])          // no rent offers, no Rent row
		#expect(gb.offers[0].services.map(\.name) == ["First", "Later"])
		#expect(gb.offers[0].services[0].logoURL == TMDbConfig.logo("/a.png"))
		#expect(gb.offers[1].services.map(\.name) == ["Free TV", "Ad TV"]) // once each
		#expect(gb.link?.absoluteString.hasSuffix("locale=GB") == true)
	}

	@Test func nothingForARegionWithoutOffers() throws {
		let all = try providers(#"{"results":{"US":{"flatrate":[{"provider_id":4}]},"FR":{"flatrate":[]}}}"#)
		#expect(TitleExtras.availability(all, region: "GB") == nil)
		#expect(TitleExtras.availability(all, region: "FR") == nil)
	}
}
