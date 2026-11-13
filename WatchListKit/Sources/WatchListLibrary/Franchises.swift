//
//  Franchises.swift
//  WatchList
//
//  Film series — Harry Potter, Mission: Impossible — as collections that fill
//  themselves: TMDb says which series a film is in, the film keeps it, and the
//  Collections tab groups your films by it. A series' page lists every film in
//  it in release order, with yours marked.
//
//  Only films: TMDb groups films into series, not shows.
//

import Foundation
import WatchListCore

extension Film {
	/// Keeps the series TMDb puts it in, or that it's in none.
	public func setFranchise(from movie: TMDbMovie, at date: Date = .now) {
		franchiseID = movie.belongs_to_collection?.id
		franchiseName = movie.belongs_to_collection?.name.map(Franchises.displayName)
		franchiseCheckedAt = date
	}

	/// Whether TMDb should be asked which series it's in: it has a TMDb id and
	/// hasn't been looked up yet.
	public var needsFranchiseCheck: Bool { tmdbID != nil && franchiseCheckedAt == nil }
}

public enum Franchises {
	/// A series as the Collections tab shows it: your films in it, oldest first.
	public struct Group: Identifiable {
		public let id: Int
		public let name: String
		public let films: [Film]

		public var watchedCount: Int { films.filter { $0.status == .watched }.count }
	}

	/// A series card's line: "3 films in your library · 2 watched".
	public static func cardLine(_ group: Group) -> String {
		let count = group.films.count
		return "\(count) film\(count == 1 ? "" : "s") in your library · \(group.watchedCount) watched"
	}

	/// "The Matrix Collection" reads as "The Matrix".
	public static func displayName(_ raw: String) -> String {
		let trimmed = raw.trimmingCharacters(in: .whitespaces)
		for suffix in [" Collection", " collection"] where trimmed.hasSuffix(suffix) && trimmed.count > suffix.count {
			return String(trimmed.dropLast(suffix.count))
		}
		return trimmed
	}

	/// Your films grouped by series, the series with the most of yours first,
	/// then A–Z.
	public static func groups(_ films: [Film]) -> [Group] {
		let bySeries = Dictionary(grouping: films.filter { $0.franchiseID != nil }) { $0.franchiseID! }
		return bySeries.map { id, films in
			Group(id: id,
			      name: films.compactMap(\.franchiseName).first ?? "Series",
			      films: films.sorted { ($0.year, $0.title) < ($1.year, $1.title) })
		}
		.sorted { lhs, rhs in
			if lhs.films.count != rhs.films.count { return lhs.films.count > rhs.films.count }
			return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
		}
	}

	/// A series' films in release order; ones without a date yet go last.
	public static func ordered(_ parts: [TMDbCollectionPart]) -> [TMDbCollectionPart] {
		parts.sorted { lhs, rhs in
			switch (lhs.release_date.flatMap(nonEmpty), rhs.release_date.flatMap(nonEmpty)) {
			case let (l?, r?): return l < r
			case (.some, nil): return true
			case (nil, .some): return false
			case (nil, nil):   return (lhs.title ?? "") < (rhs.title ?? "")
			}
		}
	}

	/// "2 of 5 watched", counting only films that are out.
	public static func progress(parts: [TMDbCollectionPart], films: [Film], today: String) -> String {
		let watched = Set(films.filter { $0.status == .watched }.compactMap(\.tmdbID))
		let released = parts.filter { part in
			guard let date = part.release_date.flatMap(nonEmpty) else { return false }
			return date <= today
		}
		let seen = released.filter { watched.contains($0.id) }.count
		return "\(seen) of \(released.count) watched"
	}

	private static func nonEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }
}
