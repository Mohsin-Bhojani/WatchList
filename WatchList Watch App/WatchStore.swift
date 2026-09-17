//
//  WatchStore.swift
//  WatchList Watch App
//
//  Everything the watch app knows, kept on the watch so it works without the
//  iPhone:
//    - the last PhoneSnapshot the iPhone sent — Up Next, and the titles
//      Discover starts from
//    - the actions taken here that the iPhone hasn't applied yet (WatchOutbox),
//      laid over the snapshot so what's shown has already moved on
//    - Discover's filter and rotation, and the suggestions fetched from TMDb
//      here, for this launch
//  Both files live in Application Support. PhoneSync carries actions to the
//  iPhone and snapshots back.
//

import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class WatchStore {
	/// Whether there's an iPhone app to sync with, as WatchConnectivity last said.
	enum Phone: Equatable {
		/// Not heard yet: the session is still starting.
		case unknown
		case notInstalled
		case installed
	}

	private(set) var snapshot: PhoneSnapshot?
	private(set) var outbox = WatchOutbox()
	var phone: Phone = .unknown
	var phoneIsReachable = false

	// Discover, for this launch — as the iPhone's Discover tab keeps them.
	var filter = DiscoverFilter()
	var rotation = DiscoverRotation()
	let loader = DiscoverLoader()

	/// Told each time an action is recorded, to carry it to the iPhone.
	@ObservationIgnored var onRecord: () -> Void = {}

	@ObservationIgnored private let directory: URL
	@ObservationIgnored private let log = Logger(subsystem: "com.mohsin.WatchList.watchkitapp", category: "WatchStore")

	init(directory: URL = .applicationSupportDirectory) {
		self.directory = directory
		snapshot = read(PhoneSnapshot.self, from: Self.snapshotFile)
		outbox = read(WatchOutbox.self, from: Self.outboxFile) ?? WatchOutbox()
	}

	#if DEBUG
	/// A store that reads and writes nothing, holding `snapshot` — for previews.
	init(preview snapshot: PhoneSnapshot?) {
		directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
		self.snapshot = snapshot
	}
	#endif

	// MARK: From the iPhone

	/// A snapshot as it arrives. An older one than what's here is ignored —
	/// the application context and a refresh reply can cross.
	func receive(packed data: Data) {
		guard let fresh = WatchLink.unpack(PhoneSnapshot.self, from: data) else {
			log.error("A snapshot from the iPhone couldn't be read")
			return
		}
		receive(fresh)
	}

	func receive(_ fresh: PhoneSnapshot) {
		if let snapshot, snapshot.sentAt >= fresh.sentAt { return }
		snapshot = fresh
		outbox.confirm(by: fresh)
		write(fresh, to: Self.snapshotFile)
		write(outbox, to: Self.outboxFile)
	}

	// MARK: Done here

	@discardableResult
	func record(_ change: WatchAction.Change) -> WatchAction {
		let action = WatchAction(change: change)
		outbox.add(action)
		write(outbox, to: Self.outboxFile)
		onRecord()
		return action
	}

	func markHandedOver(_ ids: Set<UUID>) {
		outbox.markHandedOver(ids)
		write(outbox, to: Self.outboxFile)
	}

	// MARK: Files

	private static let snapshotFile = "snapshot.json"
	private static let outboxFile = "outbox.json"

	private func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
		guard let data = try? Data(contentsOf: directory.appending(path: name)) else { return nil }
		return try? JSONDecoder().decode(type, from: data)
	}

	private func write<T: Encodable>(_ value: T, to name: String) {
		do {
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			try JSONEncoder().encode(value).write(to: directory.appending(path: name), options: .atomic)
		} catch {
			log.error("Saving \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
		}
	}
}
