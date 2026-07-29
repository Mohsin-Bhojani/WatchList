//
//  Suggestion.swift
//  WatchList
//
//  A cached recommendation for the Similar tab. Claude proposes titles from
//  your Perfection / Go For It ratings; each one is then resolved against TMDb
//  so it carries a real poster and tmdbID and can be adopted into the library
//  through the normal import path.
//
//  Cached rather than fetched every time: the tab opens instantly, still shows
//  something when the Mac helper is unreachable, and only spends a Claude call
//  when the ratings behind it actually changed (see SimilarLoader).
//

import Foundation
import SwiftData

@Model
final class Suggestion {
	var id: UUID
	var title: String
	var year: String
	var kind: MediaKind
	/// One line from Claude on why this fits — shown under the title.
	var reason: String

	/// Filled in by TMDb resolution; nil means "no TMDb match".
	var tmdbID: Int?
	var imdbID: String?
	var posterURL: String

	/// TMDb lookup has run — whether it matched or definitively didn't.
	/// Keeps a miss from being retried on every appearance.
	var resolved: Bool

	/// Claude's ordering, so the list has a stable sort.
	var rank: Int
	var generatedAt: Date

	/// Identifies the ratings that produced this batch; when it stops matching
	/// the library, the batch is stale. See SimilarLoader.fingerprint.
	var profileFingerprint: String

	init(title: String,
	     year: String,
	     kind: MediaKind,
	     reason: String,
	     rank: Int,
	     profileFingerprint: String) {
		self.id = UUID()
		self.title = title
		self.year = year
		self.kind = kind
		self.reason = reason
		self.tmdbID = nil
		self.imdbID = nil
		self.posterURL = ""
		self.resolved = false
		self.rank = rank
		self.generatedAt = Date()
		self.profileFingerprint = profileFingerprint
	}

	/// Resolved with a TMDb match — the only state where "Add to my list" works.
	var isAddable: Bool { tmdbID != nil }

	var subtitle: String {
		let type = kind == .show ? "TV Series" : "Film"
		return year.isEmpty ? type : "\(year) · \(type)"
	}
}
