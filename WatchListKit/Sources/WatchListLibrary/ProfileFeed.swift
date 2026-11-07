//
//  ProfileFeed.swift
//  WatchList
//
//  What the profile shows, worked out from the library: how your verdicts add
//  up, and your last seven days of watching — the time each day, and the titles
//  that filled the week and each day of it. Kept apart from the view so it can
//  be tested.
//

import Foundation
import WatchListCore

public enum ProfileFeed {

	// MARK: Verdicts

	public struct VerdictCount: Identifiable {
		public init(rating: Rating, count: Int) {
			self.rating = rating
			self.count = count
		}

		public let rating: Rating
		public let count: Int

		public var id: Rating { rating }
	}

	/// How many shows and films have each verdict, Perfection first — the same
	/// titles the Collections tab's by-verdict cards hold.
	public static func verdictCounts(shows: [Show], films: [Film]) -> [VerdictCount] {
		Rating.allCases.map { rating in
			VerdictCount(rating: rating,
			             count: shows.filter { $0.rating == rating }.count + films.filter { $0.rating == rating }.count)
		}
	}

	// MARK: This week

	/// An episode or film marked Watched: when, and how long it runs.
	public struct Watch {
		public init(titleID: UUID, title: String, posterURL: String, isFilm: Bool, minutes: Int, at: Date) {
			self.titleID = titleID
			self.title = title
			self.posterURL = posterURL
			self.isFilm = isFilm
			self.minutes = minutes
			self.at = at
		}

		/// The show an episode belongs to, or the film.
		public let titleID: UUID
		public let title: String
		public let posterURL: String
		public let isFilm: Bool
		public let minutes: Int
		public let at: Date
	}

	public struct Day: Identifiable {
		public init(start: Date, minutes: Int, titles: [TitleTime]) {
			self.start = start
			self.minutes = minutes
			self.titles = titles
		}

		public let start: Date
		public let minutes: Int
		/// What was watched that day, the most time first.
		public let titles: [TitleTime]

		public var id: Date { start }
	}

	/// One show or film's share of the week.
	public struct TitleTime: Identifiable {
		public init(id: UUID, title: String, posterURL: String, isFilm: Bool, episodes: Int, minutes: Int) {
			self.id = id
			self.title = title
			self.posterURL = posterURL
			self.isFilm = isFilm
			self.episodes = episodes
			self.minutes = minutes
		}

		public let id: UUID
		public let title: String
		public let posterURL: String
		public let isFilm: Bool
		/// Episodes watched; none for a film.
		public var episodes: Int
		public var minutes: Int
	}

	public struct Week {
		public init(days: [Day], titles: [TitleTime]) {
			self.days = days
			self.titles = titles
		}

		/// Seven days, oldest first, today last.
		public let days: [Day]
		/// The most time first.
		public let titles: [TitleTime]

		public var minutes: Int { days.reduce(0) { $0 + $1.minutes } }

		public var dailyAverage: Int {
			days.isEmpty ? 0 : Int((Double(minutes) / Double(days.count)).rounded())
		}
	}

	/// Watched episodes and films as watches: an episode's time from its runtime,
	/// a film's from its details, and no time when neither is known.
	public static func watches(episodes: [Episode], films: [Film]) -> [Watch] {
		var watches: [Watch] = []
		for episode in episodes {
			guard episode.status == .watched, let at = episode.watchedAt, let show = episode.season?.show else { continue }
			watches.append(Watch(titleID: show.id, title: show.title, posterURL: show.posterURL, isFilm: false,
			                     minutes: episode.runtimeMinutes ?? episode.specs?.runtimeMinutes ?? 0, at: at))
		}
		for film in films {
			guard film.status == .watched, let at = film.watchedAt else { continue }
			watches.append(Watch(titleID: film.id, title: film.title, posterURL: film.posterURL, isFilm: true,
			                     minutes: film.specs?.runtimeMinutes ?? 0, at: at))
		}
		return watches
	}

	/// The seven days up to and including `now`'s, each with the minutes watched
	/// that day and the titles behind them, and the week's titles. Anything
	/// outside those days is left out.
	public static func week(_ watches: [Watch], now: Date, calendar: Calendar = .current) -> Week {
		let today = calendar.startOfDay(for: now)
		let starts = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
		guard let first = starts.first, let end = calendar.date(byAdding: .day, value: 1, to: today) else {
			return Week(days: [], titles: [])
		}
		let inWeek = watches.filter { $0.at >= first && $0.at < end }

		let days = starts.map { start in
			let watched = inWeek.filter { calendar.isDate($0.at, inSameDayAs: start) }
			return Day(start: start, minutes: watched.reduce(0) { $0 + $1.minutes }, titles: titleTimes(watched))
		}
		return Week(days: days, titles: titleTimes(inWeek))
	}

	/// Watches added up by show or film, the most time first, then A–Z.
	private static func titleTimes(_ watches: [Watch]) -> [TitleTime] {
		var byTitle: [UUID: TitleTime] = [:]
		for watch in watches {
			var entry = byTitle[watch.titleID]
				?? TitleTime(id: watch.titleID, title: watch.title, posterURL: watch.posterURL,
				             isFilm: watch.isFilm, episodes: 0, minutes: 0)
			if !watch.isFilm { entry.episodes += 1 }
			entry.minutes += watch.minutes
			byTitle[watch.titleID] = entry
		}
		return byTitle.values.sorted { lhs, rhs in
			if lhs.minutes != rhs.minutes { return lhs.minutes > rhs.minutes }
			return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
		}
	}

	/// "Today", or the day's short weekday name: "Mon".
	public static func label(for day: Day, now: Date, calendar: Calendar = .current) -> String {
		calendar.isDate(day.start, inSameDayAs: now) ? "Today" : day.start.formatted(.dateTime.weekday(.abbreviated))
	}

	/// A picked day's name over its titles: "Today", "Yesterday", or the whole
	/// weekday name — "Monday" — which within the week is only ever one day.
	public static func name(for day: Day, now: Date, calendar: Calendar = .current) -> String {
		if calendar.isDate(day.start, inSameDayAs: now) { return "Today" }
		if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
		   calendar.isDate(day.start, inSameDayAs: yesterday) { return "Yesterday" }
		return day.start.formatted(.dateTime.weekday(.wide))
	}

	/// "10 h 43 m", "5 h" or "45 m".
	public static func duration(_ minutes: Int) -> String {
		let hours = minutes / 60, rest = minutes % 60
		if hours == 0 { return "\(rest) m" }
		return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) m"
	}

	/// The chart's top, in minutes: the busiest day's time up to a whole hour, two
	/// at least.
	public static func chartTop(for week: Week) -> Int {
		let busiest = week.days.map(\.minutes).max() ?? 0
		return max(2, Int((Double(busiest) / 60).rounded(.up))) * 60
	}

	/// Minutes between the chart's gridlines: an hour, or more once hourly lines
	/// would crowd.
	public static func gridStep(forTop top: Int) -> Int {
		switch top {
		case ...240: return 60
		case ...480: return 120
		default:     return 240
		}
	}
}
