//
//  TitleSitesTests.swift
//  WatchListTests
//
//  Which sites "Open in…" offers for each kind of page, and where they go. A
//  site offered where it has no page — Letterboxd for a show — or a search
//  that breaks on a title's punctuation is a link that leads nowhere.
//

import Foundation
import Testing
@testable import WatchList

@MainActor
struct TitleSitesTests {

	private func names(_ sites: [TitleSite]) -> [String] { sites.map(\.name) }
	private func url(_ name: String, in sites: [TitleSite]) -> String? {
		sites.first { $0.name == name }?.url?.absoluteString
	}

	private func trakt(in sites: [TitleSite]) -> TraktLookup? {
		guard case .trakt(let lookup) = sites.first(where: { $0.name == "Trakt" })?.destination else { return nil }
		return lookup
	}

	@Test func filmGetsEverySite() {
		let sites = TitleSites.film(imdbID: "tt1375666", tmdbID: 27205, title: "Inception", region: "AE", trakt: true)
		#expect(names(sites) == ["IMDb", "TMDb", "Letterboxd", "Trakt", "Rotten Tomatoes", "Metacritic", "JustWatch"])
		#expect(url("Letterboxd", in: sites) == "https://letterboxd.com/tmdb/27205/")
		#expect(trakt(in: sites)?.kind == .movie && trakt(in: sites)?.tmdbID == 27205)
		#expect(url("JustWatch", in: sites) == "https://www.justwatch.com/ae/search?q=Inception")
	}

	@Test func showHasNoLetterboxd() {
		let sites = TitleSites.show(imdbID: nil, tmdbID: 95396, title: "Severance", region: "US", trakt: true)
		#expect(names(sites) == ["TMDb", "Trakt", "Rotten Tomatoes", "Metacritic", "JustWatch"])
		#expect(trakt(in: sites)?.kind == .show)
	}

	@Test func filmWithOnlyAnIMDbIDStillReachesLetterboxdAndTrakt() {
		let sites = TitleSites.film(imdbID: "tt1375666", tmdbID: nil, title: "Inception", region: "US", trakt: true)
		#expect(url("Letterboxd", in: sites) == "https://letterboxd.com/imdb/tt1375666/")
		#expect(trakt(in: sites)?.imdbID == "tt1375666")
	}

	@Test func noTraktWithoutAClientID() {
		let sites = TitleSites.film(imdbID: "tt1375666", tmdbID: 27205, title: "Inception", region: "US", trakt: false)
		#expect(!names(sites).contains("Trakt"))
	}

	@Test func searchesSurvivePunctuation() {
		let sites = TitleSites.film(imdbID: nil, tmdbID: nil, title: "Face/Off & More?", region: "US")
		#expect(url("Rotten Tomatoes", in: sites) == "https://www.rottentomatoes.com/search?search=Face/Off%20%26%20More%3F")
		#expect(url("Metacritic", in: sites) == "https://www.metacritic.com/search/Face%2FOff%20&%20More%3F/")
	}

	@Test func justWatchFilesTheUKAsUK() {
		let sites = TitleSites.film(imdbID: nil, tmdbID: 1, title: "Heat", region: "GB")
		#expect(url("JustWatch", in: sites) == "https://www.justwatch.com/uk/search?q=Heat")
	}

	@Test func seasonAndEpisodeGetOnlyWhatReachesThem() {
		let season = TitleSites.season(showIMDbID: "tt11280740", showTMDbID: 95396, season: 2, trakt: true)
		#expect(names(season) == ["IMDb", "TMDb", "Trakt"])
		#expect(trakt(in: season)?.season == 2)
		let episode = TitleSites.episode(imdbID: nil, showTMDbID: 95396, showIMDbID: nil, season: 2, episode: 3,
		                                 trakt: true)
		#expect(names(episode) == ["TMDb", "Trakt"])
		#expect(trakt(in: episode)?.episode == 3)
		#expect(TitleSites.episode(imdbID: nil, showTMDbID: nil, showIMDbID: nil, season: 2, episode: 3,
		                           trakt: true).isEmpty)
	}

	// MARK: Trakt

	@Test func traktPagesHangOffTheSlug() {
		let film = TraktLookup(.movie, tmdbID: 27205, imdbID: nil)
		#expect(film?.pageURL(slug: "inception-2010")?.absoluteString == "https://trakt.tv/movies/inception-2010")
		let episode = TraktLookup(.show, tmdbID: 95396, imdbID: nil, season: 2, episode: 3)
		#expect(episode?.pageURL(slug: "severance")?.absoluteString
		        == "https://trakt.tv/shows/severance/seasons/2/episodes/3")
		#expect(episode?.pageURL(slug: "../evil") == nil)
		#expect(TraktLookup(.show, tmdbID: nil, imdbID: "") == nil)
	}

	@Test func slugComesFromTheMatchingKind() throws {
		let json = """
		[{"type":"show","score":1000,"show":{"title":"Dark Matter","year":2024,
		  "ids":{"trakt":1,"slug":"dark-matter-2024","tmdb":203744}}}]
		"""
		#expect(Trakt.slug(in: Data(json.utf8), kind: .show) == "dark-matter-2024")
		#expect(Trakt.slug(in: Data(json.utf8), kind: .movie) == nil)
		#expect(Trakt.slug(in: Data("[]".utf8), kind: .show) == nil)
	}

	@Test func untitledGetsNoSearches() {
		#expect(names(TitleSites.film(imdbID: nil, tmdbID: nil, title: "  ", region: "US")).isEmpty)
	}
}
