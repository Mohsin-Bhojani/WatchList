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

public enum WatchLink {
	/// The application-context and reply key a snapshot travels under.
	public nonisolated static let snapshotKey = "snapshot"
	/// The user-info and message key an action travels under.
	public nonisolated static let actionKey = "action"
	/// The user-info key naming the action, for a transfer that comes back failed.
	public nonisolated static let actionIDKey = "actionID"
	/// The message key that asks for a snapshot straight away.
	public nonisolated static let refreshKey = "refresh"
	/// WatchConnectivity turns away payloads much past 65 KB; a snapshot is
	/// trimmed to stay under this.
	public static let payloadBudget = 50_000

	public static func pack<T: Encodable>(_ value: T) -> Data? {
		guard let json = try? JSONEncoder().encode(value) else { return nil }
		return try? (json as NSData).compressed(using: .lzfse) as Data
	}

	public static func unpack<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
		guard let json = try? (data as NSData).decompressed(using: .lzfse) as Data else { return nil }
		return try? JSONDecoder().decode(type, from: json)
	}
}

// MARK: - iPhone to watch

/// The library as the watch needs it, as of `sentAt`.
public struct PhoneSnapshot: Codable, Equatable {
	public init(upNext: [UpNextShow], seeds: [DiscoverSeed], library: Set<String>, notInterested: Set<String>, putOff: [String: Date], applied: Set<UUID>, sentAt: Date) {
		self.upNext = upNext
		self.seeds = seeds
		self.library = library
		self.notInterested = notInterested
		self.putOff = putOff
		self.applied = applied
		self.sentAt = sentAt
	}

	/// The shows set to Watching, in Home's order.
	public var upNext: [UpNextShow]
	/// The library titles Discover's suggestions start from, in seed order.
	public var seeds: [DiscoverSeed]
	/// Every library title TMDb knows, by MediaKind key: never suggested.
	public var library: Set<String>
	/// Suggestions turned down, by key.
	public var notInterested: Set<String>
	/// Suggestions put off for later, by key, and when.
	public var putOff: [String: Date]
	/// The watch's actions applied so far — the last few days of them.
	public var applied: Set<UUID>
	public var sentAt: Date
}

/// A show set to Watching, and the episodes it's up to.
public struct UpNextShow: Codable, Equatable, Identifiable {
	public init(id: UUID, title: String, artworkURL: String, upcoming: [UpNextEpisode], remaining: Int, episodeCount: Int, toAir: Int? = nil, nextAirDate: String? = nil) {
		self.id = id
		self.title = title
		self.artworkURL = artworkURL
		self.upcoming = upcoming
		self.remaining = remaining
		self.episodeCount = episodeCount
		self.toAir = toAir
		self.nextAirDate = nextAirDate
	}

	public let id: UUID
	public let title: String
	/// Its backdrop, or its poster when it has none; empty with neither.
	public let artworkURL: String
	/// The first episodes not yet watched, in running order with specials last,
	/// so the watch can move on by itself.
	public let upcoming: [UpNextEpisode]
	/// How many episodes that are out aren't watched — more than `upcoming`
	/// holds, at times.
	public let remaining: Int
	public let episodeCount: Int
	/// How many episodes not yet watched are still to air. Optional, so a
	/// snapshot from an iPhone that doesn't send it — the watch keeps the last
	/// one it was sent — still reads.
	public var toAir: Int? = nil
	/// The air date of the first of those, as TMDb writes it; nil without one.
	public var nextAirDate: String? = nil
}

public struct UpNextEpisode: Codable, Equatable, Identifiable {
	public init(id: UUID, seasonNumber: Int, episodeNumber: Int, title: String, runtimeMinutes: Int? = nil, status: WatchStatus, tier: EpisodeTier? = nil) {
		self.id = id
		self.seasonNumber = seasonNumber
		self.episodeNumber = episodeNumber
		self.title = title
		self.runtimeMinutes = runtimeMinutes
		self.status = status
		self.tier = tier
	}

	public let id: UUID
	public let seasonNumber: Int
	public let episodeNumber: Int
	public let title: String
	public let runtimeMinutes: Int?
	/// As it was before the watch touched it, for Undo.
	public let status: WatchStatus
	public let tier: EpisodeTier?

	/// "S2 E8", or "Special 1" for season 0 (EpisodeCode).
	public var code: String { EpisodeCode.short(season: seasonNumber, episode: episodeNumber) }

	/// "Season 2 · Episode 8".
	public var line: String { EpisodeCode.long(season: seasonNumber, episode: episodeNumber) }
}

/// A library title Discover starts from, as the watch is sent it.
public struct DiscoverSeed: Codable, Equatable, Identifiable, SuggestionSeed {
	public init(id: UUID, kind: MediaKind, tmdbID: Int? = nil, title: String, rating: Rating? = nil) {
		self.id = id
		self.kind = kind
		self.tmdbID = tmdbID
		self.title = title
		self.rating = rating
	}

	public let id: UUID
	public let kind: MediaKind
	public let tmdbID: Int?
	public let title: String
	/// Its verdict, for "Because you rated …"; nil when it has none — and from an
	/// iPhone that sent none.
	public var rating: Rating? = nil
}

// MARK: - Watch to iPhone

public struct WatchAction: Codable, Equatable, Identifiable {
	public enum Change: Codable, Equatable {
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

	public var id = UUID()
	public var madeAt = Date.now
	public let change: Change

	public init(id: UUID = UUID(), madeAt: Date = .now, change: Change) {
		self.id = id
		self.madeAt = madeAt
		self.change = change
	}
}

// MARK: - The watch's actions until they're applied

/// The actions taken on the watch that no snapshot has named as applied yet,
/// and what they change about the snapshot in the meantime.
public struct WatchOutbox: Codable, Equatable {
	public init() {}

	public struct Entry: Codable, Equatable {
		public let action: WatchAction
		/// Given to WatchConnectivity, which delivers it from here on.
		public var handedOver = false
	}

	/// An action handed over this long before a snapshot that still doesn't name
	/// it is taken as lost, so it can't hide a title for good.
	public static let patience: TimeInterval = 3 * 24 * 60 * 60

	public private(set) var entries: [Entry] = []

	public var isEmpty: Bool { entries.isEmpty }

	/// Not yet given to WatchConnectivity — waiting for the session, or for the
	/// iPhone app to be installed.
	public var unsent: [WatchAction] { entries.filter { !$0.handedOver }.map(\.action) }

	public mutating func add(_ action: WatchAction) {
		entries.append(Entry(action: action))
	}

	public mutating func markHandedOver(_ ids: Set<UUID>) {
		for index in entries.indices where ids.contains(entries[index].action.id) {
			entries[index].handedOver = true
		}
	}

	/// A transfer that failed: to be handed over again.
	public mutating func markUnsent(_ id: UUID) {
		for index in entries.indices where entries[index].action.id == id {
			entries[index].handedOver = false
		}
	}

	/// Forgets what `snapshot` has applied, and anything handed over so long
	/// before it that it's not coming.
	public mutating func confirm(by snapshot: PhoneSnapshot) {
		entries.removeAll { entry in
			snapshot.applied.contains(entry.action.id)
				|| (entry.handedOver && entry.action.madeAt < snapshot.sentAt.addingTimeInterval(-Self.patience))
		}
	}

	/// Episodes marked watched here, and not put back since.
	public var watched: Set<UUID> {
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
	public struct Decision: Equatable {
		public init(choice: Choice, at: Date) {
			self.choice = choice
			self.at = at
		}

		public enum Choice: Equatable {
			case added, notInterested, later
		}

		public let choice: Choice
		public let at: Date
	}

	/// Suggestions decided here, by key — the latest decision on each.
	public var decisions: [String: Decision] {
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
public struct UpNextItem: Identifiable, Equatable {
	public init(show: UpNextShow, next: UpNextEpisode? = nil) {
		self.show = show
		self.next = next
	}

	public let show: UpNextShow
	public let next: UpNextEpisode?

	public var id: UUID { show.id }
}

extension PhoneSnapshot {
	/// Up Next with the episodes marked on the watch moved past.
	public func upNext(markedOnWatch watched: Set<UUID>) -> [UpNextItem] {
		upNext.map { show in
			UpNextItem(show: show, next: show.upcoming.first { !watched.contains($0.id) })
		}
	}

	/// What Discover leaves out: the library and what's turned down, with what the
	/// watch has added or turned down since. Put off on the watch, a title turned
	/// down on the iPhone comes back — but never one in the library.
	public func excluded(with outbox: WatchOutbox) -> Set<String> {
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
	public func putOff(with outbox: WatchOutbox) -> [String: Date] {
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
