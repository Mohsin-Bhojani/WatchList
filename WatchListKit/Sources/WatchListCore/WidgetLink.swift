//
//  WidgetLink.swift
//  WatchList
//
//  What the iPhone app and its Up Next widget share, through the App Group's
//  folder — compiled into both, and kept free of SwiftData, since the widget
//  never opens the library:
//    - a snapshot the app writes (WidgetSync.swift): the shows set to Watching,
//      each with its next few episodes out, and a small picture of each
//    - an outbox the widget writes: episodes marked watched from its button,
//      which the app applies the next time it's open, through the same code
//      the watch's marks go through (WatchActionApplier)
//  Marking moves the widget's own snapshot on at once, so it shows the next
//  episode without waiting for the app.
//
//  The folder is shared by two processes, so every read-change-write of the
//  outbox goes through a file coordinator.
//

import Foundation

public nonisolated enum WidgetLink {
	public static let appGroup = "group.com.mohsin.WatchList"
	/// The widget's kind, for reloading its timelines.
	public static let kind = "UpNext"

	public static var folder: URL? {
		FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
	}
}

/// The shows on the widget, as the app last wrote them.
public nonisolated struct WidgetSnapshot: Codable, Equatable {
	public init(shows: [WidgetShow], writtenAt: Date) {
		self.shows = shows
		self.writtenAt = writtenAt
	}

	public var shows: [WidgetShow]
	public var writtenAt: Date

	public static let empty = WidgetSnapshot(shows: [], writtenAt: .distantPast)
}

public nonisolated struct WidgetShow: Codable, Equatable, Identifiable {
	public init(id: UUID, title: String, artFile: String? = nil, posterFile: String? = nil, upcoming: [WidgetEpisode],
	            watched: Int, total: Int, caughtUpLine: String? = nil) {
		self.id = id
		self.title = title
		self.artFile = artFile
		self.posterFile = posterFile
		self.upcoming = upcoming
		self.watched = watched
		self.total = total
		self.caughtUpLine = caughtUpLine
	}

	public let id: UUID
	public let title: String
	/// Its landscape picture in the shared folder's Art directory, when there is one.
	public var artFile: String?
	/// Its portrait poster there, for the poster style and the shelf. Optional,
	/// so a snapshot written before posters were still reads.
	public var posterFile: String?
	/// The next episodes out and not yet watched, in running order.
	public var upcoming: [WidgetEpisode]
	public var watched: Int
	public let total: Int
	/// Said in place of the next episode once caught up with more to air.
	public var caughtUpLine: String?

	public var next: WidgetEpisode? { upcoming.first }
	public var fraction: Double { total == 0 ? 0 : min(Double(watched) / Double(total), 1) }
}

public nonisolated struct WidgetEpisode: Codable, Equatable, Identifiable {
	public init(id: UUID, code: String, title: String) {
		self.id = id
		self.code = code
		self.title = title
	}

	public let id: UUID
	/// "S2 · E8".
	public let code: String
	public let title: String
}

/// One Mark Watched from the widget, waiting for the app.
public nonisolated struct WidgetMark: Codable, Equatable, Identifiable {
	public var id = UUID()
	public let episodeID: UUID
	public var madeAt = Date.now

	public init(id: UUID = UUID(), episodeID: UUID, madeAt: Date = .now) {
		self.id = id
		self.episodeID = episodeID
		self.madeAt = madeAt
	}
}

/// Reads and writes the shared folder. Built on a directory so tests can use
/// their own; `shared` is the App Group's, nil when the group isn't set up.
public nonisolated struct WidgetStore {
	public init(directory: URL) {
		self.directory = directory
	}

	public let directory: URL

	public static var shared: WidgetStore? { WidgetLink.folder.map(WidgetStore.init) }

	public var snapshotURL: URL { directory.appendingPathComponent("UpNext.json") }
	public var outboxURL: URL { directory.appendingPathComponent("UpNextMarks.json") }
	public var artDirectory: URL { directory.appendingPathComponent("Art", isDirectory: true) }
	public var pageURL: URL { directory.appendingPathComponent("UpNextPage.json") }

	// MARK: Paging

	/// Which of the shows a widget set to all of them is on: the arrows turn it.
	/// One for every such widget, so they move together.
	public func page() -> Int {
		read(Int.self, at: pageURL) ?? 0
	}

	/// Moves the page on by `step` (back when negative), wrapping round `count`.
	public func turnPage(by step: Int, of count: Int) {
		guard count > 0 else { return }
		coordinated(pageURL) { url in
			let current = read(Int.self, at: url) ?? 0
			write(((current + step) % count + count) % count, to: url)
		}
	}

	/// The show a widget shows: the one it was set to when that's still being
	/// watched, otherwise the paged one of all of them.
	public static func show(in snapshot: WidgetSnapshot, chosen: UUID?, page: Int) -> WidgetShow? {
		if let chosen, let show = snapshot.shows.first(where: { $0.id == chosen }) { return show }
		guard !snapshot.shows.isEmpty else { return nil }
		return snapshot.shows[(page % snapshot.shows.count + snapshot.shows.count) % snapshot.shows.count]
	}

	// MARK: Snapshot

	public func snapshot() -> WidgetSnapshot {
		read(WidgetSnapshot.self, at: snapshotURL) ?? .empty
	}

	public func write(_ snapshot: WidgetSnapshot) {
		coordinated(snapshotURL) { write(snapshot, to: $0) }
	}

	// MARK: Outbox

	public func outbox() -> [WidgetMark] {
		read([WidgetMark].self, at: outboxURL) ?? []
	}

	/// The widget's Mark Watched: queues the mark for the app and moves the
	/// show on in the snapshot, so the widget redraws with the next episode.
	public func mark(episode episodeID: UUID) {
		coordinated(outboxURL) { url in
			var marks = read([WidgetMark].self, at: url) ?? []
			guard !marks.contains(where: { $0.episodeID == episodeID }) else { return }
			marks.append(WidgetMark(episodeID: episodeID))
			write(marks, to: url)
		}
		coordinated(snapshotURL) { url in
			let current = read(WidgetSnapshot.self, at: url) ?? .empty
			write(Self.marking(episodeID, in: current), to: url)
		}
	}

	/// Drops marks the app has applied, keeping any the widget added since.
	public func removeFromOutbox(_ ids: Set<UUID>) {
		guard !ids.isEmpty else { return }
		coordinated(outboxURL) { url in
			let marks = (read([WidgetMark].self, at: url) ?? []).filter { !ids.contains($0.id) }
			write(marks, to: url)
		}
	}

	/// `snapshot` with `episodeID` marked: off its show's list, one more watched.
	public static func marking(_ episodeID: UUID, in snapshot: WidgetSnapshot) -> WidgetSnapshot {
		var snapshot = snapshot
		for index in snapshot.shows.indices where snapshot.shows[index].upcoming.contains(where: { $0.id == episodeID }) {
			snapshot.shows[index].upcoming.removeAll { $0.id == episodeID }
			snapshot.shows[index].watched += 1
		}
		return snapshot
	}

	// MARK: Files

	private func read<T: Decodable>(_ type: T.Type, at url: URL) -> T? {
		guard let data = try? Data(contentsOf: url) else { return nil }
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		return try? decoder.decode(T.self, from: data)
	}

	private func write<T: Encodable>(_ value: T, to url: URL) {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		guard let data = try? encoder.encode(value) else { return }
		try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		try? data.write(to: url, options: .atomic)
	}

	/// Runs `body` with `url` held against the other process's writes.
	private func coordinated(_ url: URL, _ body: (URL) -> Void) {
		var error: NSError?
		NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &error, byAccessor: body)
	}
}
