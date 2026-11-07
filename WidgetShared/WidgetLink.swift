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

nonisolated enum WidgetLink {
	static let appGroup = "group.com.mohsin.WatchList"
	/// The widget's kind, for reloading its timelines.
	static let kind = "UpNext"

	static var folder: URL? {
		FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
	}
}

/// The shows on the widget, as the app last wrote them.
nonisolated struct WidgetSnapshot: Codable, Equatable {
	var shows: [WidgetShow]
	var writtenAt: Date

	static let empty = WidgetSnapshot(shows: [], writtenAt: .distantPast)
}

nonisolated struct WidgetShow: Codable, Equatable, Identifiable {
	let id: UUID
	let title: String
	/// Its picture in the shared folder's Art directory, when there is one.
	var artFile: String?
	/// The next episodes out and not yet watched, in running order.
	var upcoming: [WidgetEpisode]
	var watched: Int
	let total: Int
	/// Said in place of the next episode once caught up with more to air.
	var caughtUpLine: String?

	var next: WidgetEpisode? { upcoming.first }
	var fraction: Double { total == 0 ? 0 : min(Double(watched) / Double(total), 1) }
}

nonisolated struct WidgetEpisode: Codable, Equatable, Identifiable {
	let id: UUID
	/// "S2 · E8".
	let code: String
	let title: String
}

/// One Mark Watched from the widget, waiting for the app.
nonisolated struct WidgetMark: Codable, Equatable, Identifiable {
	var id = UUID()
	let episodeID: UUID
	var madeAt = Date.now
}

/// Reads and writes the shared folder. Built on a directory so tests can use
/// their own; `shared` is the App Group's, nil when the group isn't set up.
nonisolated struct WidgetStore {
	let directory: URL

	static var shared: WidgetStore? { WidgetLink.folder.map(WidgetStore.init) }

	var snapshotURL: URL { directory.appendingPathComponent("UpNext.json") }
	var outboxURL: URL { directory.appendingPathComponent("UpNextMarks.json") }
	var artDirectory: URL { directory.appendingPathComponent("Art", isDirectory: true) }

	// MARK: Snapshot

	func snapshot() -> WidgetSnapshot {
		read(WidgetSnapshot.self, at: snapshotURL) ?? .empty
	}

	func write(_ snapshot: WidgetSnapshot) {
		coordinated(snapshotURL) { write(snapshot, to: $0) }
	}

	// MARK: Outbox

	func outbox() -> [WidgetMark] {
		read([WidgetMark].self, at: outboxURL) ?? []
	}

	/// The widget's Mark Watched: queues the mark for the app and moves the
	/// show on in the snapshot, so the widget redraws with the next episode.
	func mark(episode episodeID: UUID) {
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
	func removeFromOutbox(_ ids: Set<UUID>) {
		guard !ids.isEmpty else { return }
		coordinated(outboxURL) { url in
			let marks = (read([WidgetMark].self, at: url) ?? []).filter { !ids.contains($0.id) }
			write(marks, to: url)
		}
	}

	/// `snapshot` with `episodeID` marked: off its show's list, one more watched.
	static func marking(_ episodeID: UUID, in snapshot: WidgetSnapshot) -> WidgetSnapshot {
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
