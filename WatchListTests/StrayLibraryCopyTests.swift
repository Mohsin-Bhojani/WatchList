//
//  StrayLibraryCopyTests.swift
//  WatchListTests
//
//  The spare library one build left in the widget's folder goes only when
//  nothing of yours goes with it.
//

import Foundation
import SwiftData
import Testing
@testable import WatchList
@testable import WatchListCore
@testable import WatchListLibrary

private final class FixtureToken {}

@MainActor
struct StrayLibraryCopyTests {

	/// A folder with the committed fixture store as `library` and, when asked,
	/// a copy of it as `copy`, changed by `change` first.
	private func stores(copy: Bool = true, library: Bool = true,
	                    change: ((ModelContext) throws -> Void)? = nil) throws -> (copy: URL, library: URL) {
		let fixture = try #require(Bundle(for: FixtureToken.self).url(forResource: "LibraryV1", withExtension: "store"))
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		for name in ["app", "group"] {
			try FileManager.default.createDirectory(at: folder.appendingPathComponent(name), withIntermediateDirectories: true)
		}
		let libraryURL = folder.appendingPathComponent("app/default.store")
		let copyURL = folder.appendingPathComponent("group/default.store")
		if library { try FileManager.default.copyItem(at: fixture, to: libraryURL) }
		if copy {
			try FileManager.default.copyItem(at: fixture, to: copyURL)
			if let change {
				let context = ModelContext(try LibraryStore.open(at: copyURL))
				try change(context)
				try context.save()
			}
		}
		return (copyURL, libraryURL)
	}

	private func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

	@Test func aCopyDifferingOnlyInTMDbDetailsIsRemoved() throws {
		let (copy, library) = try stores { context in
			// What the old build's refresh did: names and air dates filled in.
			for episode in try context.fetch(FetchDescriptor<Episode>()) {
				episode.title = "Named \(episode.episodeNumber)"
				episode.airDate = "2026-10-01"
			}
		}
		#expect(StrayLibraryCopy.removeIfCovered(copyAt: copy, libraryAt: library) == .removed)
		#expect(!exists(copy))
		#expect(!exists(URL(fileURLWithPath: copy.path + "-wal")))
		#expect(!exists(URL(fileURLWithPath: copy.path + "-shm")))
		// The library is untouched.
		try StoreFixture.expectIntact(ModelContext(try LibraryStore.open(at: library)))
	}

	@Test func aCopyWithAWatchedMarkTheLibraryLacksIsKept() throws {
		let (copy, library) = try stores { context in
			let unwatched = try #require(try context.fetch(FetchDescriptor<Episode>()).first { $0.status != .watched })
			unwatched.markWatched()
		}
		#expect(StrayLibraryCopy.removeIfCovered(copyAt: copy, libraryAt: library) == .kept)
		#expect(exists(copy))
	}

	@Test func aCopyWithAChangedVerdictIsKept() throws {
		let (copy, library) = try stores { context in
			try #require(try context.fetch(FetchDescriptor<Film>()).first).rate(.skip, stars: nil)
		}
		#expect(StrayLibraryCopy.removeIfCovered(copyAt: copy, libraryAt: library) == .kept)
		#expect(exists(copy))
	}

	@Test func neverTheOnlyLibrary() throws {
		let (copy, library) = try stores(library: false)
		#expect(StrayLibraryCopy.removeIfCovered(copyAt: copy, libraryAt: library) == .kept)
		#expect(exists(copy))
		#expect(StrayLibraryCopy.removeIfCovered(copyAt: copy, libraryAt: copy) == .kept)
	}

	@Test func nothingToDoWithoutACopy() throws {
		let (copy, library) = try stores(copy: false)
		#expect(StrayLibraryCopy.removeIfCovered(copyAt: copy, libraryAt: library) == .none)
	}
}
