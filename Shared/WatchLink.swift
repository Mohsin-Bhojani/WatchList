//
//  WatchLink.swift
//  WatchList
//
//  What the iPhone app and the watch app say to each other over
//  WatchConnectivity. Compiled into both, so the two agree on every shape:
//    - PhoneSnapshot, from the iPhone: Up Next — the shows set to Watching and
//      the episodes each is up to — the library titles Discover starts from,
//      and what Discover leaves out. Sent as the application context: only the
//      latest one matters, and the watch keeps it for when the iPhone's away.
//    - WatchAction, from the watch: an episode marked watched or put back, and
//      a suggestion added, turned down or put off. Queued with transferUserInfo,
//      so each one arrives, in order, whenever the iPhone is next there — and,
//      while the iPhone is reachable, sent as a message too, so it shows there
//      straight away. The iPhone applies each action once, by its id.
//    - a refresh: a message the watch sends while the iPhone is reachable,
//      answered there and then with a snapshot.
//  Each travels as LZFSE-compressed JSON.
//
//  The watch doesn't wait for the iPhone. What it shows is the last snapshot
//  with its own actions laid over it (WatchOutbox) until a snapshot names them
//  as applied.
//

import Foundation

enum WatchLink {
	/// The application-context and reply key a snapshot travels under.
	nonisolated static let snapshotKey = "snapshot"
	/// The user-info and message key an action travels under.
	nonisolated static let actionKey = "action"
	/// The user-info key naming the action, for a transfer that comes back failed.
	nonisolated static let actionIDKey = "actionID"
	/// The message key that asks for a snapshot straight away.
	nonisolated static let refreshKey = "refresh"
	/// WatchConnectivity turns away payloads much past 65 KB; a snapshot is
	/// trimmed to stay under this.
	static let payloadBudget = 50_000

	static func pack<T: Encodable>(_ value: T) -> Data? {
		guard let json = try? JSONEncoder().encode(value) else { return nil }
		return try? (json as NSData).compressed(using: .lzfse) as Data
	}

	static func unpack<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
		guard let json = try? (data as NSData).decompressed(using: .lzfse) as Data else { return nil }
		return try? JSONDecoder().decode(type, from: json)
	}
}

// MARK: - iPhone to watch

/// The library as the watch needs it, as of `sentAt`.
struct PhoneSnapshot: Codable, Equatable {
	/// The shows set to Watching, in Home's order.
	var upNext: [UpNextShow]
	/// The library titles Discover's suggestions start from, in seed order.
	var seeds: [DiscoverSeed]
	/// Every library title TMDb knows, by MediaKind key: never suggested.
	var library: Set<String>
	/// Suggestions turned down, by key.
	var notInterested: Set<String>
	/// Suggestions put off for later, by key, and when.
	var putOff: [String: Date]
	/// The watch's actions applied so far — the last few days of them.
	var applied: Set<UUID>
	var sentAt: Date
}

/// A show set to Watching, and the episodes it's up to.
struct UpNextShow: Codable, Equatable, Identifiable {
	let id: UUID
	let title: String
	/// Its backdrop, or its poster when it has none; empty with neither.
	let artworkURL: String
	/// The first episodes not yet watched, in running order with specials last,
	/// so the watch can move on by itself.
	let upcoming: [UpNextEpisode]
	/// How many episodes aren't watched — more than `upcoming` holds, at times.
	let remaining: Int
	let episodeCount: Int
}

struct UpNextEpisode: Codable, Equatable, Identifiable {
	let id: UUID
	let seasonNumber: Int
	let episodeNumber: Int
	let title: String
	let runtimeMinutes: Int?
	/// As it was before the watch touched it, for Undo.
	let status: WatchStatus
	let tier: EpisodeTier?

	/// "S2 · E8", or "Special · E1" for season 0.
	var code: String {
		seasonNumber == 0 ? "Special · E\(episodeNumber)" : "S\(seasonNumber) · E\(episodeNumber)"
	}
}

/// A library title Discover starts from, as the watch is sent it.
struct DiscoverSeed: Codable, Equatable, Identifiable, SuggestionSeed {
	let id: UUID
	let kind: MediaKind
	let tmdbID: Int?
	let title: String
}

// MARK: - Watch to iPhone

struct WatchAction: Codable, Equatable, Identifiable {
	enum Change: Codable, Equatable {
		/// Marked watched, rated or not — as the iPhone's rating sheet marks it.
		case markWatched(episode: UUID, tier: EpisodeTier?)
		/// Undo: back to the status and rating it had.
		case putBack(episode: UUID, status: WatchStatus, tier: EpisodeTier?)
		/// Swiped right: added to the library as To Watch.
		case add(kind: MediaKind, tmdbID: Int)
		/// Swiped left.
		case notInterested(key: String)
		/// Swiped up.
		case later(key: String)
	}

	var id = UUID()
	var madeAt = Date.now
	let change: Change
}

// MARK: - The watch's actions until they're applied

/// The actions taken on the watch that no snapshot has named as applied yet,
/// and what they change about the snapshot in the meantime.
struct WatchOutbox: Codable, Equatable {
	struct Entry: Codable, Equatable {
		let action: WatchAction
		/// Given to WatchConnectivity, which delivers it from here on.
		var handedOver = false
	}

	/// An action handed over this long before a snapshot that still doesn't name
	/// it is taken as lost, so it can't hide a title for good.
	static let patience: TimeInterval = 3 * 24 * 60 * 60

	private(set) var entries: [Entry] = []

	var isEmpty: Bool { entries.isEmpty }

	/// Not yet given to WatchConnectivity — waiting for the session, or for the
	/// iPhone app to be installed.
	var unsent: [WatchAction] { entries.filter { !$0.handedOver }.map(\.action) }

	mutating func add(_ action: WatchAction) {
		entries.append(Entry(action: action))
	}

	mutating func markHandedOver(_ ids: Set<UUID>) {
		for index in entries.indices where ids.contains(entries[index].action.id) {
			entries[index].handedOver = true
		}
	}

	/// A transfer that failed: to be handed over again.
	mutating func markUnsent(_ id: UUID) {
		for index in entries.indices where entries[index].action.id == id {
			entries[index].handedOver = false
		}
	}

	/// Forgets what `snapshot` has applied, and anything handed over so long
	/// before it that it's not coming.
	mutating func confirm(by snapshot: PhoneSnapshot) {
		entries.removeAll { entry in
			snapshot.applied.contains(entry.action.id)
				|| (entry.handedOver && entry.action.madeAt < snapshot.sentAt.addingTimeInterval(-Self.patience))
		}
	}

	/// Episodes marked watched here, and not put back since.
	var watched: Set<UUID> {
		var episodes = Set<UUID>()
		for entry in entries {
			switch entry.action.change {
			case .markWatched(let episode, _): episodes.insert(episode)
			case .putBack(let episode, _, _):  episodes.remove(episode)
			default:                           break
			}
		}
		return episodes
	}

	/// A suggestion decided here, and when.
	struct Decision: Equatable {
		enum Choice: Equatable {
			case added, notInterested, later
		}

		let choice: Choice
		let at: Date
	}

	/// Suggestions decided here, by key — the latest decision on each.
	var decisions: [String: Decision] {
		var latest: [String: Decision] = [:]
		for entry in entries {
			let at = entry.action.madeAt
			switch entry.action.change {
			case .add(let kind, let tmdbID):  latest[kind.key(tmdbID: tmdbID)] = Decision(choice: .added, at: at)
			case .notInterested(let key):     latest[key] = Decision(choice: .notInterested, at: at)
			case .later(let key):             latest[key] = Decision(choice: .later, at: at)
			default:                          break
			}
		}
		return latest
	}
}

// MARK: - What the watch shows

/// A show on the watch's Up Next, and the episode it's up to once the watch's
/// own marks are counted.
struct UpNextItem: Identifiable, Equatable {
	let show: UpNextShow
	let next: UpNextEpisode?

	var id: UUID { show.id }
}

extension PhoneSnapshot {
	/// Up Next with the episodes marked on the watch moved past.
	func upNext(markedOnWatch watched: Set<UUID>) -> [UpNextItem] {
		upNext.map { show in
			UpNextItem(show: show, next: show.upcoming.first { !watched.contains($0.id) })
		}
	}

	/// What Discover leaves out: the library and what's turned down, with what the
	/// watch has added or turned down since. Put off on the watch, a title turned
	/// down on the iPhone comes back — but never one in the library.
	func excluded(with outbox: WatchOutbox) -> Set<String> {
		var turnedDown = notInterested
		var decidedOnWatch = Set<String>()
		for (key, decision) in outbox.decisions {
			switch decision.choice {
			case .added, .notInterested: decidedOnWatch.insert(key)
			case .later:                 turnedDown.remove(key)
			}
		}
		return library.union(turnedDown).union(decidedOnWatch)
	}

	/// When each put-off suggestion was put off, counting the watch's.
	func putOff(with outbox: WatchOutbox) -> [String: Date] {
		var dates = putOff
		for (key, decision) in outbox.decisions {
			switch decision.choice {
			case .later:                 dates[key] = max(dates[key] ?? .distantPast, decision.at)
			case .added, .notInterested: dates[key] = nil
			}
		}
		return dates
	}
}
