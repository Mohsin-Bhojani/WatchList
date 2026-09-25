//
//  TrailersTests.swift
//  WatchListTests
//
//  Which of TMDb's videos a title page offers, and which one the trailer card
//  plays. The first is what anyone tapping the card sees, so a teaser or a
//  fan upload winning over the studio's trailer is a visible mistake — and the
//  key goes into the player's page, so nothing but a YouTube id may pass.
//

import Testing
@testable import WatchList

@MainActor
struct TrailersTests {

	private func video(_ key: String?, _ type: String = "Trailer", site: String = "YouTube",
	                   official: Bool? = true, published: String? = "2021-09-02T00:00:00.000Z",
	                   name: String? = nil) -> TMDbVideo {
		TMDbVideo(key: key, name: name ?? key, site: site, type: type, official: official,
		          published_at: published, iso_639_1: "en")
	}

	@Test func trailerBeatsAnEarlierTeaser() {
		let ranked = Trailers.ranked([video("teaser", "Teaser", published: "2021-08-01T00:00:00.000Z"),
		                              video("trailer", published: "2021-09-01T00:00:00.000Z")])
		#expect(ranked.map(\.key) == ["trailer", "teaser"])
		#expect(ranked.last?.isTeaser == true)
	}

	@Test func officialBeatsUnofficial() {
		let ranked = Trailers.ranked([video("fan", official: false, published: "2020-01-01T00:00:00.000Z"),
		                              video("studio")])
		#expect(ranked.first?.key == "studio")
	}

	@Test func earliestFirstAndUndatedLast() {
		let ranked = Trailers.ranked([video("s2", published: "2023-05-01T00:00:00.000Z"),
		                              video("undated", published: nil),
		                              video("s1", published: "2021-09-02T00:00:00.000Z")])
		#expect(ranked.map(\.key) == ["s1", "s2", "undated"])
	}

	@Test func leavesOutClipsOtherSitesAndDuplicates() {
		let ranked = Trailers.ranked([video("clip", "Clip"), video("featurette", "Featurette"),
		                              video("vimeo", site: "Vimeo"), video("once"), video("once")])
		#expect(ranked.map(\.key) == ["once"])
	}

	@Test func keysThatArentYouTubeIDsAreDropped() {
		let ranked = Trailers.ranked([video("x\"><script>"), video(""), video(nil), video("dQw4w9WgXcQ"),
		                              video("a-b_C9")])
		#expect(ranked.map(\.key) == ["dQw4w9WgXcQ", "a-b_C9"])
	}

	@Test func namelessVideoTakesItsType() {
		let ranked = Trailers.ranked([TMDbVideo(key: "abc", name: "  ", site: "YouTube", type: "Teaser",
		                                        official: true, published_at: nil, iso_639_1: nil)])
		#expect(ranked.first?.name == "Teaser")
	}
}
