//
//  JellyfinTests.swift
//  WatchListTests
//
//  Finding a title on your Jellyfin server and playing it: the typed address,
//  matching a page to the server's copy by id and an episode by its numbers,
//  the URL the player gets, and when a playback resumes or counts as watched.
//  A wrong match plays the wrong thing; a wrong URL plays nothing.
//

import Foundation
import Testing
@testable import WatchList

@MainActor
struct JellyfinTests {

	private func item(_ id: String, _ type: String, tmdb: String? = nil, imdb: String? = nil,
	                  season: Int? = nil, number: Int? = nil, end: Int? = nil) -> JellyfinItem {
		var ids: [String: String] = [:]
		ids["Tmdb"] = tmdb
		ids["Imdb"] = imdb
		return JellyfinItem(id: id, name: id, type: type, providerIDs: ids, indexNumber: number,
		                    indexNumberEnd: end, parentIndexNumber: season)
	}

	// MARK: Server address

	@Test func addressGetsASchemeAndLosesItsTrailingSlash() {
		#expect(JellyfinServer.normalized(" 192.168.1.20:8096/ ")?.absoluteString == "http://192.168.1.20:8096")
		#expect(JellyfinServer.normalized("https://media.example.com")?.absoluteString == "https://media.example.com")
	}

	@Test func basePathIsKept() {
		let server = JellyfinServer.normalized("http://nas.local:8096/jellyfin/")
		#expect(server?.absoluteString == "http://nas.local:8096/jellyfin")
		#expect(server?.appending(path: "Items").absoluteString == "http://nas.local:8096/jellyfin/Items")
	}

	@Test func nonsenseIsNoAddress() {
		#expect(JellyfinServer.normalized("") == nil)
		#expect(JellyfinServer.normalized("my server") == nil)
	}

	// MARK: Matching

	@Test func filmsAndShowsAreFoundByTMDbThenIMDb() {
		let index = JellyfinIndex(items: [item("m1", "Movie", tmdb: "27205", imdb: "tt1375666"),
		                                  item("m2", "Movie", imdb: "tt0468569"),
		                                  item("s1", "Series", tmdb: "1396")])
		#expect(index.movie(tmdbID: 27205, imdbID: nil)?.id == "m1")
		#expect(index.movie(tmdbID: 155, imdbID: "TT0468569")?.id == "m2")
		#expect(index.series(tmdbID: 1396, imdbID: nil)?.id == "s1")
		#expect(index.movieCount == 2 && index.seriesCount == 1)
	}

	@Test func aFilmIsNeverTakenForAShow() {
		let index = JellyfinIndex(items: [item("m1", "Movie", tmdb: "1396")])
		#expect(index.series(tmdbID: 1396, imdbID: nil) == nil)
		#expect(index.movie(tmdbID: 1, imdbID: nil) == nil)
	}

	@Test func providerNamesInAnyCase() {
		let found = JellyfinItem(id: "x", providerIDs: ["tmdb": "42"])
		#expect(found.providerID("Tmdb") == "42")
	}

	@Test func episodesMatchBySeasonAndNumberIncludingDoubles() {
		let episodes = [item("e1", "Episode", season: 1, number: 1),
		                item("e2", "Episode", season: 1, number: 2, end: 3),
		                item("e21", "Episode", season: 2, number: 1)]
		#expect(JellyfinEpisodes.match(episodes, season: 1, episode: 1)?.id == "e1")
		#expect(JellyfinEpisodes.match(episodes, season: 1, episode: 3)?.id == "e2")
		#expect(JellyfinEpisodes.match(episodes, season: 2, episode: 1)?.id == "e21")
		#expect(JellyfinEpisodes.match(episodes, season: 2, episode: 2) == nil)
	}

	// MARK: Streams

	private let server = URL(string: "http://nas.local:8096/jellyfin")!

	@Test func aFileTheIPhonePlaysIsStreamedAsItIs() throws {
		let source = JellyfinPlaybackInfo.Source(id: "src", supportsDirectPlay: true, transcodingURL: "/ignored")
		let chosen = try #require(JellyfinStreams.url(server: server, token: "tok", itemID: "item",
		                                              source: source, playSessionID: "ps"))
		#expect(chosen.method == "DirectPlay")
		let components = try #require(URLComponents(url: chosen.url, resolvingAgainstBaseURL: false))
		#expect(components.path == "/jellyfin/Videos/item/stream")
		#expect(components.queryItems?.contains(URLQueryItem(name: "api_key", value: "tok")) == true)
		#expect(components.queryItems?.contains(URLQueryItem(name: "static", value: "true")) == true)
	}

	@Test func anythingElseIsTheServersHLSWithTheTokenAddedOnce() throws {
		let bare = JellyfinPlaybackInfo.Source(id: "src", supportsDirectPlay: false,
		                                       transcodingURL: "/videos/item/master.m3u8?MediaSourceId=src")
		let chosen = try #require(JellyfinStreams.url(server: server, token: "tok", itemID: "item",
		                                              source: bare, playSessionID: nil))
		#expect(chosen.method == "Transcode")
		#expect(chosen.url.absoluteString
			== "http://nas.local:8096/jellyfin/videos/item/master.m3u8?MediaSourceId=src&api_key=tok")

		let signed = JellyfinPlaybackInfo.Source(id: "src", supportsDirectPlay: false,
		                                         transcodingURL: "/videos/item/master.m3u8?ApiKey=abc")
		let again = try #require(JellyfinStreams.url(server: server, token: "tok", itemID: "item",
		                                             source: signed, playSessionID: nil))
		#expect(!again.url.absoluteString.contains("api_key=tok"))
	}

	@Test func noWayToPlayIsNoURL() {
		let source = JellyfinPlaybackInfo.Source(id: "src", supportsDirectPlay: false, transcodingURL: nil)
		#expect(JellyfinStreams.url(server: server, token: "t", itemID: "i", source: source, playSessionID: nil) == nil)
	}

	// MARK: Resuming and watched

	@Test func ticksAreTenMillionASecond() {
		#expect(JellyfinTicks.seconds(36_000_000_000) == 3600)
		#expect(JellyfinTicks.ticks(1.5) == 15_000_000)
	}

	@Test func ninetyPercentCountsAsWatched() {
		#expect(MediaPlayback.countsAsWatched(position: 5400, duration: 6000))
		#expect(!MediaPlayback.countsAsWatched(position: 5300, duration: 6000))
		#expect(!MediaPlayback.countsAsWatched(position: 5400, duration: nil))
	}

	@Test func resumesOnlyFromTheMiddle() {
		#expect(MediaPlayback.resumePoint(position: 12, duration: 6000) == nil)
		#expect(MediaPlayback.resumePoint(position: 1450, duration: 6000) == 1450)
		#expect(MediaPlayback.resumePoint(position: 5900, duration: 6000) == nil)
		let started = JellyfinItem(id: "x", runTimeTicks: JellyfinTicks.ticks(6000),
		                           userData: .init(playbackPositionTicks: JellyfinTicks.ticks(1450)))
		#expect(started.resumeSeconds == 1450)
	}

	@Test func resumeClock() {
		#expect(MediaPlayback.clock(750) == "12:30")
		#expect(MediaPlayback.clock(3852) == "1:04:12")
	}
}
