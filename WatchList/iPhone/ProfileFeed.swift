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

enum ProfileFeed {

	// MARK: Verdicts

	struct VerdictCount: Identifiable {
		let rating: Rating
		let count: Int

		var id: Rating { rating }
	}

	/// How many shows and films have each verdict, Perfection first — the same
	/// titles the Collections tab's by-verdict cards hold.
	static func verdictCounts(shows: [Show], films: [Film]) -> [VerdictCount] {
		Rating.allCases.map { rating in
			VerdictCount(rating: rating,
			             count: shows.filter { $0.rating == rating }.count + films.filter { $0.rating == rating }.count)
		}
	}

	// MARK: This week

	/// An episode or film marked Watched: when, and how long it runs.
	struct Watch {
		/// The show an episode belongs to, or the film.
		let titleID: UUID
		let title: String
		let posterURL: String
		let isFilm: Bool
		let minutes: Int
		let at: Date
	}

	struct Day: Identifiable {
		let start: Date
		let minutes: Int
		/// What was watched that day, the most time first.
		let titles: [TitleTime]

		var id: Date { start }
	}

	/// One show or film's share of the week.
	struct TitleTime: Identifiable {
		let id: UUID
		let title: String
		let posterURL: String
		let isFilm: Bool
		/// Episodes watched; none for a film.
		var episodes: Int
		var minutes: Int
	}

	struct Week {
		/// Seven days, oldest first, today last.
		let days: [Day]
		/// The most time first.
		let titles: [TitleTime]

		var minutes: Int { days.reduce(0) { $0 + $1.minutes } }

		var dailyAverage: Int {
			days.isEmpty ? 0 : Int((Double(minutes) / Double(days.count)).rounded())
		}
	}

	/// Watched episodes and films as watches: an episode's time from its runtime,
	/// a film's from its details, and no time when neither is known.
	static func watches(episodes: [Episode], films: [Film]) -> [Watch] {
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

	/// Episodes marked this close together were marked in one go.
	static let markedTogether: TimeInterval = 2

	/// Leaves out a show's episodes marked Watched in one go — setting a season or
	/// show to Watched marks all of them in the same instant — since that's the
	/// library catching up, not an evening's watching. Films always count.
	static func watchedOneByOne(_ watches: [Watch]) -> [Watch] {
		var kept = watches.filter(\.isFilm)
		let byShow = Dictionary(grouping: watches.filter { !$0.isFilm }, by: \.titleID)
		for marks in byShow.values {
			let sorted = marks.sorted { $0.at < $1.at }
			var first = 0
			while first < sorted.count {
				var last = first
				while last + 1 < sorted.count,
				      sorted[last + 1].at.timeIntervalSince(sorted[last].at) < markedTogether {
					last += 1
				}
				if last == first { kept.append(sorted[first]) }
				first = last + 1
			}
		}
		return kept
	}

	/// The seven days up to and including `now`'s, each with the minutes watched
	/// that day and the titles behind them, and the week's titles. Anything
	/// outside those days is left out.
	static func week(_ watches: [Watch], now: Date, calendar: Calendar = .current) -> Week {
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
	static func label(for day: Day, now: Date, calendar: Calendar = .current) -> String {
		calendar.isDate(day.start, inSameDayAs: now) ? "Today" : day.start.formatted(.dateTime.weekday(.abbreviated))
	}

	/// A picked day's name over its titles: "Today", "Yesterday", or the whole
	/// weekday name — "Monday" — which within the week is only ever one day.
	static func name(for day: Day, now: Date, calendar: Calendar = .current) -> String {
		if calendar.isDate(day.start, inSameDayAs: now) { return "Today" }
		if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
		   calendar.isDate(day.start, inSameDayAs: yesterday) { return "Yesterday" }
		return day.start.formatted(.dateTime.weekday(.wide))
	}

	/// "10 h 43 m", "5 h" or "45 m".
	static func duration(_ minutes: Int) -> String {
		let hours = minutes / 60, rest = minutes % 60
		if hours == 0 { return "\(rest) m" }
		return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) m"
	}

	/// The chart's top, in minutes: the busiest day's time up to a whole hour, two
	/// at least.
	static func chartTop(for week: Week) -> Int {
		let busiest = week.days.map(\.minutes).max() ?? 0
		return max(2, Int((Double(busiest) / 60).rounded(.up))) * 60
	}

	/// Minutes between the chart's gridlines: an hour, or more once hourly lines
	/// would crowd.
	static func gridStep(forTop top: Int) -> Int {
		switch top {
		case ...240: return 60
		case ...480: return 120
		default:     return 240
		}
	}
}
