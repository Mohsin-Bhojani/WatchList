//
//  AirDate.swift
//  WatchList
//
//  Air dates as TMDb writes them — "2026-11-14" — and the few questions asked
//  of them: has it aired by today, and how to say when the next one airs.
//  Compiled into both the iPhone app and the watch app, so both phrase a
//  caught-up show the same way.
//
//  Dates are compared as day strings in the device's own calendar. TMDb gives a
//  day, not a time, so an episode counts as out from the start of its air date
//  wherever you are.
//

import Foundation

public enum AirDate {

	/// `date` as a day string, "yyyy-MM-dd", in `calendar`'s time zone.
	public static func day(_ date: Date, calendar: Calendar = .current) -> String {
		let parts = calendar.dateComponents([.year, .month, .day], from: date)
		return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
	}

	/// The day part of an air date, when it is a full date; nil for an empty or
	/// partial one ("2026", "TBA").
	public static func dayPart(of airDate: String) -> String? {
		let trimmed = airDate.trimmingCharacters(in: .whitespacesAndNewlines)
		guard trimmed.count >= 10 else { return nil }
		let day = String(trimmed.prefix(10))
		guard day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
		return day
	}

	/// True when a dated air date is on or before `today` (a `day(_:)` string).
	/// Nil when the air date isn't a full date, so the caller decides.
	public static func hasAired(_ airDate: String, today: String) -> Bool? {
		dayPart(of: airDate).map { $0 <= today }
	}

	/// When the next one airs, said the way it reads after "New episode":
	/// "tomorrow", "Friday" within the week, "14 Nov" this year, "14 Nov 2027"
	/// after. Nil when it isn't a full date.
	public static func phrase(_ airDate: String, now: Date = .now, calendar: Calendar = .current,
	                   locale: Locale = .current) -> String? {
		guard let day = dayPart(of: airDate), let date = parse(day, calendar: calendar) else { return nil }
		let start = calendar.startOfDay(for: now)
		let days = calendar.dateComponents([.day], from: start, to: date).day ?? 0
		if days == 1 { return "tomorrow" }
		let formatter = DateFormatter()
		formatter.calendar = calendar
		formatter.timeZone = calendar.timeZone
		formatter.locale = locale
		if (2...6).contains(days) {
			formatter.setLocalizedDateFormatFromTemplate("EEEE")
		} else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
			formatter.setLocalizedDateFormatFromTemplate("d MMM")
		} else {
			formatter.setLocalizedDateFormatFromTemplate("d MMM y")
		}
		return formatter.string(from: date)
	}

	/// The line a caught-up show shows in place of the episode it's up to.
	/// `short` drops "New episode" for the watch's narrower line.
	public static func caughtUpLine(nextAirDate: String?, short: Bool = false, now: Date = .now,
	                         calendar: Calendar = .current) -> String {
		guard let nextAirDate, let when = phrase(nextAirDate, now: now, calendar: calendar) else {
			return short ? "Caught up" : "Caught up · More to come"
		}
		return short ? "Caught up · Next \(when)" : "Caught up · New episode \(when)"
	}

	private static func parse(_ day: String, calendar: Calendar) -> Date? {
		let parts = day.split(separator: "-").compactMap { Int($0) }
		guard parts.count == 3 else { return nil }
		return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
	}
}
