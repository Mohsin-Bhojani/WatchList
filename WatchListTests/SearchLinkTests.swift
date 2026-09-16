//
//  SearchLinkTests.swift
//  WatchListTests
//
//  What the iPhone Search tab's field treats as a title link to import, and
//  what it leaves to the TMDb text search. Getting this wrong either way is
//  visible: a link searched as text finds nothing, and a title mistaken for a
//  link never gets searched at all.
//

import Testing
@testable import WatchList

@MainActor
struct SearchLinkTests {

	@Test func imdbTitleLink() {
		#expect(SearchLink.parse("https://www.imdb.com/title/tt0468569/") == .imdb("tt0468569"))
	}

	@Test func imdbMobileLinkWithTrackingQuery() {
		#expect(SearchLink.parse("https://m.imdb.com/title/tt0903747/?ref_=nv_sr_srsg_0") == .imdb("tt0903747"))
	}

	@Test func imdbLinkInsideShareText() {
		let shared = "Breaking Bad (TV Series 2008–2013) - IMDb https://www.imdb.com/title/tt0903747/"
		#expect(SearchLink.parse(shared) == .imdb("tt0903747"))
	}

	@Test func bareIMDbIDWithStraySpaces() {
		#expect(SearchLink.parse("  tt0468569 \n") == .imdb("tt0468569"))
	}

	@Test func tmdbFilmAndShowLinks() {
		#expect(SearchLink.parse("https://www.themoviedb.org/movie/155-the-dark-knight") == .tmdb(.film, 155))
		#expect(SearchLink.parse("https://www.themoviedb.org/tv/1396-breaking-bad/season/1") == .tmdb(.show, 1396))
	}

	@Test func plainTitlesAreNotLinks() {
		#expect(SearchLink.parse("The Dark Knight") == nil)
		#expect(SearchLink.parse("Se7en") == nil)
		#expect(SearchLink.parse("tt") == nil)
		#expect(!SearchLink.looksLikeLink("The Dark Knight"))
	}

	@Test func linkToAPageThatIsNotATitle() {
		let person = "https://www.imdb.com/name/nm0000288/"
		#expect(SearchLink.parse(person) == nil)
		#expect(SearchLink.looksLikeLink(person))
	}

	@Test func onlyIMDbLinksCarryAnIMDbIDIntoTheManualForm() {
		#expect(SearchLink.imdb("tt0468569").imdbID == "tt0468569")
		#expect(SearchLink.tmdb(.film, 155).imdbID == nil)
	}
}
