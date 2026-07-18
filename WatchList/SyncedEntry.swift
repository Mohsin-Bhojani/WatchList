//
//  SyncedEntry.swift
//  WatchList
//
//  The one model that mirrors to iCloud (CloudKit). It is deliberately lean: it
//  carries only the user's personal state (watch status, rating, notes) plus a
//  seed id (IMDb / TMDb) that each device uses to re-fetch the full details from
//  TMDb. Manual entries — which have no id to refetch from — also carry their
//  basic fields and picked poster so they still appear on other devices.
//
//  CloudKit requirements honoured here: every attribute is optional or has a
//  default value, there are no `@Attribute(.unique)` constraints, and there are
//  no relationships. Enums are stored as their raw `String` values for a trivial
//  CloudKit mapping.
//

import Foundation
import SwiftData

@Model
final class SyncedEntry {
	/// Stable identity both devices converge on, e.g. "tmdb:show:1399",
	/// "imdb:film:tt0468569" or "manual:<uuid>". Not a unique constraint
	/// (CloudKit forbids those) — uniqueness is reconciled in `LibrarySync`.
	var key: String = ""

	/// `MediaKind.rawValue` — "Show" or "Film".
	var mediaKind: String = ""

	// Seed ids used to re-fetch full details on each device.
	var imdbID: String?
	var tmdbID: Int?

	// Personal state (the part worth syncing). Enums as raw values.
	var status: String = WatchStatus.toWatch.rawValue
	var rating: String?
	var notes: String = ""

	var dateAdded: Date = Date.now
	/// Last-writer-wins clock, bumped whenever personal state changes.
	var updatedAt: Date = Date.now

	// Manual entries (no seed id) carry enough to show without a refetch.
	var isManual: Bool = false
	var manualTitle: String = ""
	var manualYear: String = ""
	var manualGenre: String = ""
	@Attribute(.externalStorage) var manualPosterData: Data?

	init(key: String,
	     mediaKind: MediaKind,
	     imdbID: String? = nil,
	     tmdbID: Int? = nil,
	     status: WatchStatus = .toWatch,
	     rating: Rating? = nil,
	     notes: String = "",
	     dateAdded: Date = .now,
	     isManual: Bool = false,
	     manualTitle: String = "",
	     manualYear: String = "",
	     manualGenre: String = "",
	     manualPosterData: Data? = nil) {
		self.key = key
		self.mediaKind = mediaKind.rawValue
		self.imdbID = imdbID
		self.tmdbID = tmdbID
		self.status = status.rawValue
		self.rating = rating?.rawValue
		self.notes = notes
		self.dateAdded = dateAdded
		self.updatedAt = .now
		self.isManual = isManual
		self.manualTitle = manualTitle
		self.manualYear = manualYear
		self.manualGenre = manualGenre
		self.manualPosterData = manualPosterData
	}

	// MARK: - Typed accessors

	var kind: MediaKind { MediaKind(rawValue: mediaKind) ?? .show }
	var watchStatus: WatchStatus { WatchStatus(rawValue: status) ?? .toWatch }
	var ratingValue: Rating? { rating.flatMap(Rating.init(rawValue:)) }
}
