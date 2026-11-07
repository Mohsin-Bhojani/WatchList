//
//  SharedCoreTests.swift
//  WatchListTests
//
//  The pieces of WatchListCore the iPhone, the watch and the widget now share
//  instead of each writing their own: how an episode is named, and artwork on
//  disk.
//

import Foundation
import Testing
@testable import WatchList
@testable import WatchListCore
@testable import WatchListLibrary

struct EpisodeCodeTests {

	@Test func oneShortFormEverywhere() {
		#expect(EpisodeCode.short(season: 2, episode: 3) == "S2 E3")
		#expect(EpisodeCode.short(season: 0, episode: 2) == "Special 2")
		let watch = UpNextEpisode(id: UUID(), seasonNumber: 2, episodeNumber: 3, title: "", runtimeMinutes: nil,
		                          status: .toWatch, tier: nil)
		#expect(watch.code == "S2 E3")
		#expect(ShowFacts.code(season: 2, episode: 3) == watch.code)
	}

	@Test func oneLongFormEverywhere() {
		#expect(EpisodeCode.long(season: 2, episode: 8) == "Season 2 · Episode 8")
		#expect(EpisodeCode.long(season: 0, episode: 1) == "Specials · Episode 1")
	}
}

struct ImageFilesTests {

	private func files() throws -> ImageFiles {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return ImageFiles(directory: directory)
	}

	@Test func oneFilePerURLNamedTheSameOnEveryDevice() throws {
		let files = try files()
		let url = URL(string: "https://image.tmdb.org/t/p/w500/a.jpg")!
		#expect(files.file(for: url) == files.file(for: url))
		#expect(files.file(for: url) != files.file(for: URL(string: "https://image.tmdb.org/t/p/w500/b.jpg")!))
		#expect(files.file(for: url).lastPathComponent.count == 64)   // SHA-256, hex
		#expect(files.cached(url) == nil)
	}

	@Test func trimmingDropsWhatWasUsedLongestAgo() throws {
		let files = try files()
		let old = URL(string: "https://example.com/old.jpg")!
		let used = URL(string: "https://example.com/used.jpg")!
		for url in [old, used] {
			try Data(repeating: 1, count: 40_000).write(to: files.file(for: url))
			try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)],
			                                      ofItemAtPath: files.file(for: url).path)
		}
		_ = files.cached(used)                                         // reading it re-dates it
		files.trim(to: 50_000)
		#expect(files.cached(old) == nil)
		#expect(files.cached(used) != nil)
	}
}
