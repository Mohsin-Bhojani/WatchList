//
//  WidgetTests.swift
//  WatchListTests
//
//  The Up Next widget's two halves: what the app writes for it, and what the
//  widget's Mark Watched does with it before the app applies the mark.
//

import Foundation
import SwiftData
import Testing
@testable import WatchList
@testable import WatchListCore
@testable import WatchListLibrary

@MainActor
struct WidgetSnapshotTests {

	private var now: Date {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = .current
		return calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 12))!
	}

	private func show(_ title: String, status: WatchStatus, dates: [String], watched: Int) -> Show {
		let show = Show(title: title, status: status)
		let season = Season(seasonNumber: 1)
		season.show = show
		show.seasons.append(season)
		for (index, date) in dates.enumerated() {
			let episode = Episode(episodeNumber: index + 1, seasonNumber: 1, title: "E\(index + 1)",
			                      airDate: date, tmdbShowID: 1)
			if index < watched { episode.status = .watched }
			episode.season = season
			season.episodes.append(episode)
		}
		return show
	}

	@Test func onlyWatchingShowsWithTheirNextEpisodesOut() {
		let watching = show("Watching", status: .watching, dates: ["2026-10-01", "2026-10-08", "2026-10-15", "2026-12-01"], watched: 1)
		let waiting = show("Waiting", status: .toWatch, dates: ["2026-10-01"], watched: 0)
		let snapshot = WidgetSync.snapshot(of: [waiting, watching], upcoming: 4, asOf: now)

		#expect(snapshot.shows.map(\.title) == ["Watching"])
		let row = snapshot.shows[0]
		#expect(row.upcoming.map(\.code) == ["S1 E2", "S1 E3"])   // not the one in December
		#expect(row.watched == 1)
		#expect(row.total == 4)
		#expect(row.caughtUpLine == nil)
	}

	@Test func caughtUpSaysWhenTheNextAirs() {
		let caughtUp = show("Weekly", status: .watching, dates: ["2026-10-31", "2026-11-14"], watched: 1)
		let row = WidgetSync.snapshot(of: [caughtUp], asOf: now).shows[0]
		#expect(row.upcoming.isEmpty)
		#expect(row.caughtUpLine?.hasPrefix("Caught up") == true)
	}
}

struct WidgetStoreTests {

	private func store() throws -> WidgetStore {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return WidgetStore(directory: directory)
	}

	private func snapshot(_ episodes: [WidgetEpisode]) -> WidgetSnapshot {
		WidgetSnapshot(shows: [WidgetShow(id: UUID(), title: "Show", artFile: nil, upcoming: episodes,
		                                  watched: 3, total: 10, caughtUpLine: nil)], writtenAt: .now)
	}

	@Test func markingQueuesItAndMovesTheShowOn() throws {
		let store = try store()
		let first = WidgetEpisode(id: UUID(), code: "S1 E4", title: "Four")
		let second = WidgetEpisode(id: UUID(), code: "S1 E5", title: "Five")
		store.write(snapshot([first, second]))

		store.mark(episode: first.id)

		#expect(store.outbox().map(\.episodeID) == [first.id])
		let after = store.snapshot().shows[0]
		#expect(after.next == second)
		#expect(after.watched == 4)
	}

	@Test func aDoubleTapIsMarkedOnce() throws {
		let store = try store()
		let episode = WidgetEpisode(id: UUID(), code: "S1 E1", title: "One")
		store.write(snapshot([episode]))
		store.mark(episode: episode.id)
		store.mark(episode: episode.id)
		#expect(store.outbox().count == 1)
		#expect(store.snapshot().shows[0].watched == 4)
	}

	@Test func removingAppliedMarksKeepsNewerOnes() throws {
		let store = try store()
		let a = UUID(), b = UUID()
		store.mark(episode: a)
		let applied = Set(store.outbox().map(\.id))
		store.mark(episode: b)                        // tapped while the app was applying
		store.removeFromOutbox(applied)
		#expect(store.outbox().map(\.episodeID) == [b])
	}

	@Test func nothingWrittenReadsAsEmpty() throws {
		let store = try store()
		#expect(store.snapshot() == .empty)
		#expect(store.outbox().isEmpty)
	}
}

@MainActor
struct WidgetMarkApplyTests {

	@Test func aWidgetMarkIsAppliedLikeTheWatchs() throws {
		let container = try ModelContainer(for: Schema(versionedSchema: LibrarySchemaV1.self),
		                                   configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
		let context = ModelContext(container)
		let show = Show(title: "Show", status: .toWatch)
		context.insert(show)
		let season = Season(seasonNumber: 1)
		season.show = show
		context.insert(season)
		let episode = Episode(episodeNumber: 1, seasonNumber: 1, title: "One")
		episode.season = season
		context.insert(episode)

		let mark = WidgetMark(episodeID: episode.id)
		WatchActionApplier.apply(WatchAction(id: mark.id, madeAt: mark.madeAt,
		                                     change: .markWatched(episode: mark.episodeID, tier: nil)), in: context)
		#expect(episode.status == .watched)
		#expect(episode.episodeTier == nil)
		#expect(show.status == .watching)
	}
}

struct WidgetPagingTests {

	private func store() throws -> WidgetStore {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		return WidgetStore(directory: directory)
	}

	private func snapshot(_ titles: [String]) -> WidgetSnapshot {
		WidgetSnapshot(shows: titles.map { WidgetShow(id: UUID(), title: $0, upcoming: [], watched: 0, total: 1) },
		               writtenAt: .now)
	}

	@Test func theArrowsWrapRoundBothWays() throws {
		let store = try store()
		#expect(store.page() == 0)
		store.turnPage(by: -1, of: 3)
		#expect(store.page() == 2)
		store.turnPage(by: 1, of: 3)
		store.turnPage(by: 1, of: 3)
		#expect(store.page() == 1)
	}

	@Test func aChosenShowWinsWhileItsStillBeingWatched() {
		let shows = snapshot(["One", "Two", "Three"])
		let two = shows.shows[1].id
		#expect(WidgetStore.show(in: shows, chosen: two, page: 0)?.title == "Two")
		// Finished or no longer Watching: back to the paged one.
		#expect(WidgetStore.show(in: shows, chosen: UUID(), page: 2)?.title == "Three")
		#expect(WidgetStore.show(in: shows, chosen: nil, page: 4)?.title == "Two")   // wraps
		#expect(WidgetStore.show(in: snapshot([]), chosen: nil, page: 0) == nil)
	}

	@Test func aSnapshotFromBeforePostersStillReads() throws {
		let json = #"{"shows":[{"id":"\#(UUID().uuidString)","title":"Old","upcoming":[],"watched":1,"total":2}],"writtenAt":"2026-11-07T10:00:00Z"}"#
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let snapshot = try decoder.decode(WidgetSnapshot.self, from: Data(json.utf8))
		#expect(snapshot.shows[0].posterFile == nil)
	}
}
