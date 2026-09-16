//
//  FilmFacts.swift
//  WatchList
//
//  How the iPhone film page words a film's facts: runtime, release date, the
//  TMDb average as stars, vote counts, genres and the watched date.
//

import Foundation

enum FilmFacts {
	enum Star: Equatable { case full, half, empty }

	/// "2h 04m", or just "58m" under an hour.
	static func runtime(_ minutes: Int?) -> String? {
		guard let minutes, minutes > 0 else { return nil }
		let hours = minutes / 60
		let rest = minutes % 60
		return hours == 0 ? "\(rest)m" : "\(hours)h " + String(format: "%02dm", rest)
	}

	/// TMDb's "2015-06-24" spelled out — "24 June 2015" — in the locale's order.
	static func releaseDate(_ iso: String?, locale: Locale = .current) -> String? {
		guard let iso, !iso.isEmpty else { return nil }
		let parser = DateFormatter()
		parser.locale = Locale(identifier: "en_US_POSIX")
		parser.timeZone = TimeZone(identifier: "UTC")
		parser.dateFormat = "yyyy-MM-dd"
		guard let date = parser.date(from: iso) else { return nil }
		let formatter = DateFormatter()
		formatter.locale = locale
		formatter.timeZone = TimeZone(identifier: "UTC")
		formatter.setLocalizedDateFormatFromTemplate("dMMMMyyyy")
		return formatter.string(from: date)
	}

	/// Five stars for TMDb's 0–10 average, to the nearest half: each point of
	/// the average is half a star.
	static func stars(outOf10 average: Double) -> [Star] {
		let halves = Int(min(max(average, 0), 10).rounded())
		return (0..<5).map { index in
			switch halves - index * 2 {
			case 2...:  return .full
			case 1:     return .half
			default:    return .empty
			}
		}
	}

	/// "3,072", grouped for the locale; nil for nothing to count.
	static func count(_ value: Int?, locale: Locale = .current) -> String? {
		guard let value, value > 0 else { return nil }
		return value.formatted(.number.locale(locale))
	}

	/// "Drama, Thriller" as "Drama · Thriller".
	static func genres(_ list: String) -> String {
		list.split(separator: ",")
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
			.joined(separator: " · ")
	}

	/// "2 Aug 2026", for when something was marked watched.
	static func shortDate(_ date: Date, locale: Locale = .current) -> String {
		date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
	}
}
