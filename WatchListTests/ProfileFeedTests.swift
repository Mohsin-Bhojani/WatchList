//
//  ProfileFeedTests.swift
//  WatchListTests
//
//  The profile's numbers: verdicts added up, the week's time by day and by
//  title, each day's titles, what counts as watching, and how days, times and
//  the chart's scale read.
//

import Foundation
import Testing
@testable import WatchList
@testable import WatchListCore
@testable import WatchListLibrary

@MainActor
struct ProfileFeedTests {

	private static let calendar: Calendar = {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "UTC")!
		return calendar
	}()

	/// Tuesday 15 September 2026, noon UTC.
	private let now = Date(timeIntervalSince1970: 1_789_473_600)

	private let severance = UUID()
	private let chicago = UUID()
	private let thar = UUID()

	/// A watch `daysAgo` days before today, at `hour` o'clock.
	private func watch(_ id: UUID, _ title: String, film: Bool = false, minutes: Int,
	                   daysAgo: Int, hour: Double = 9, second: TimeInterval = 0) -> ProfileFeed.Watch {
		let today = Self.calendar.startOfDay(for: now)
		let day = Self.calendar.date(byAdding: .day, value: -daysAgo, to: today)!
		return ProfileFeed.Watch(titleID: id, title: title, posterURL: "", isFilm: film, minutes: minutes,
		                         at: day.addingTimeInterval(hour * 3600 + second))
	}

	@Test func verdictsAddUpAcrossShowsAndFilms() {
		let counts = ProfileFeed.verdictCounts(
			shows: [Show(title: "A", rating: .perfection), Show(title: "B", rating: .goForIt), Show(title: "C")],
			films: [Film(title: "D", rating: .perfection), Film(title: "E", rating: .skip)])
		#expect(counts.map(\.rating) == [.perfection, .goForIt, .timepass, .skip])
		#expect(counts.map(\.count) == [2, 1, 0, 1])
	}

	@Test func theWeekRunsSevenDaysToTodayAddingUpEachDay() {
		let week = ProfileFeed.week([
			watch(chicago, "Chicago P.D.", minutes: 43, daysAgo: 6, hour: 20),
			watch(thar, "Thar", film: true, minutes: 128, daysAgo: 3, hour: 21),
			watch(severance, "Severance", minutes: 50, daysAgo: 2, hour: 22),
			watch(severance, "Severance", minutes: 50, daysAgo: 0),
			watch(severance, "Severance", minutes: 50, daysAgo: 7, hour: 23),   // a day too early
		], now: now, calendar: Self.calendar)

		#expect(week.days.count == 7)
		#expect(week.days.map(\.minutes) == [43, 0, 0, 128, 50, 0, 50])
		#expect(Self.calendar.isDate(week.days[6].start, inSameDayAs: now))
		#expect(week.minutes == 271)
		#expect(week.dailyAverage == 39)
		#expect(ProfileFeed.label(for: week.days[6], now: now, calendar: Self.calendar) == "Today")
		#expect(ProfileFeed.label(for: week.days[0], now: now, calendar: Self.calendar) != "Today")
		#expect(ProfileFeed.name(for: week.days[6], now: now, calendar: Self.calendar) == "Today")
		#expect(ProfileFeed.name(for: week.days[5], now: now, calendar: Self.calendar) == "Yesterday")
		#expect(!["Today", "Yesterday"].contains(ProfileFeed.name(for: week.days[4], now: now, calendar: Self.calendar)))
	}

	@Test func titlesRankByTimeAndCountTheirEpisodes() {
		let week = ProfileFeed.week([
			watch(severance, "Severance", minutes: 50, daysAgo: 1),
			watch(severance, "Severance", minutes: 50, daysAgo: 2),
			watch(thar, "Thar", film: true, minutes: 128, daysAgo: 3),
			watch(chicago, "Chicago P.D.", minutes: 43, daysAgo: 1, hour: 11),
		], now: now, calendar: Self.calendar)

		#expect(week.titles.map(\.title) == ["Thar", "Severance", "Chicago P.D."])
		#expect(week.titles.map(\.minutes) == [128, 100, 43])
		#expect(week.titles.map(\.episodes) == [0, 2, 1])
	}

	@Test func eachDayListsWhatFilledIt() {
		let week = ProfileFeed.week([
			watch(severance, "Severance", minutes: 50, daysAgo: 1),
			watch(severance, "Severance", minutes: 50, daysAgo: 1, hour: 10),
			watch(chicago, "Chicago P.D.", minutes: 43, daysAgo: 1, hour: 11),
			watch(severance, "Severance", minutes: 50, daysAgo: 2),
			watch(thar, "Thar", film: true, minutes: 128, daysAgo: 0),
		], now: now, calendar: Self.calendar)

		let yesterday = week.days[5]
		#expect(yesterday.titles.map(\.title) == ["Severance", "Chicago P.D."])
		#expect(yesterday.titles.map(\.minutes) == [100, 43])
		#expect(yesterday.titles.map(\.episodes) == [2, 1])
		#expect(yesterday.minutes == 143)
		#expect(week.days[6].titles.map(\.title) == ["Thar"])
		#expect(week.days[3].titles.isEmpty)
	}

	@Test func onlyWatchedEpisodesAndFilmsCountWithTheirRuntimes() {
		let show = Show(title: "Severance", status: .watching)
		let season = Season(seasonNumber: 1)
		season.show = show
		show.seasons.append(season)
		let watched = Episode(episodeNumber: 1, seasonNumber: 1, title: "E1", runtimeMinutes: 57)
		let unwatched = Episode(episodeNumber: 2, seasonNumber: 1, title: "E2", runtimeMinutes: 53)
		for episode in [watched, unwatched] {
			episode.season = season
			season.episodes.append(episode)
		}
		watched.mark(.watched, at: now)
		let film = Film(title: "Thar", specs: TechSpecs(runtimeMinutes: 128))
		film.mark(.watched, at: now)
		let unwatchedFilm = Film(title: "Kill")

		let watches = ProfileFeed.watches(episodes: [watched, unwatched], films: [film, unwatchedFilm])
		#expect(watches.count == 2)
		#expect(watches.first { !$0.isFilm }?.titleID == show.id)
		#expect(watches.first { !$0.isFilm }?.minutes == 57)
		#expect(watches.first { $0.isFilm }?.minutes == 128)
	}

	@Test func timesAndTheChartScaleRead() {
		#expect(ProfileFeed.duration(643) == "10 h 43 m")
		#expect(ProfileFeed.duration(300) == "5 h")
		#expect(ProfileFeed.duration(45) == "45 m")
		#expect(ProfileFeed.duration(0) == "0 m")

		func top(_ busiest: Int) -> Int {
			ProfileFeed.chartTop(for: ProfileFeed.Week(days: [ProfileFeed.Day(start: now, minutes: busiest, titles: [])],
			                                           titles: []))
		}
		#expect(top(0) == 120)
		#expect(top(143) == 180)
		#expect(top(600) == 600)
		#expect(top(601) == 660)
		#expect(ProfileFeed.gridStep(forTop: 180) == 60)
		#expect(ProfileFeed.gridStep(forTop: 360) == 120)
		#expect(ProfileFeed.gridStep(forTop: 720) == 240)
	}

	// MARK: Earlier weeks

	@Test func earlierWeeksRunSevenDaysEndingAWeekApart() {
		let lastWeekEnd = ProfileFeed.weekEnd(weeksBack: 1, now: now, calendar: Self.calendar)
		let week = ProfileFeed.week([
			watch(chicago, "Chicago P.D.", minutes: 43, daysAgo: 7),    // last week's last day
			watch(thar, "Thar", film: true, minutes: 128, daysAgo: 13),  // its first
			watch(severance, "Severance", minutes: 50, daysAgo: 6),     // this week's first
			watch(severance, "Severance", minutes: 50, daysAgo: 14),    // the week before
		], now: lastWeekEnd, calendar: Self.calendar)
		#expect(week.days.map(\.minutes) == [128, 0, 0, 0, 0, 0, 43])
		#expect(week.titles.map(\.id) == [thar, chicago])
		#expect(ProfileFeed.weekEnd(weeksBack: 0, now: now, calendar: Self.calendar)
			== Self.calendar.startOfDay(for: now))
	}

	@Test func weeksAreNamedThisWeekLastWeekThenByTheirDays() {
		#expect(ProfileFeed.weekTitle(weeksBack: 0, now: now, calendar: Self.calendar) == "This week")
		#expect(ProfileFeed.weekTitle(weeksBack: 1, now: now, calendar: Self.calendar) == "Last week")
		let older = ProfileFeed.weekTitle(weeksBack: 2, now: now, calendar: Self.calendar)
		// 26 Aug – 1 Sep, however the locale lays it out.
		#expect(older.contains("26") && older.contains("1"))
		#expect(older != "Last week")
	}

	@Test func theArrowsGoBackAsFarAsTheEarliestWatch() {
		let day: TimeInterval = 86_400
		#expect(ProfileFeed.weeksBackLimit(earliest: nil, now: now, calendar: Self.calendar) == 0)
		#expect(ProfileFeed.weeksBackLimit(earliest: now - 6 * day, now: now, calendar: Self.calendar) == 0)
		#expect(ProfileFeed.weeksBackLimit(earliest: now - 7 * day, now: now, calendar: Self.calendar) == 1)
		#expect(ProfileFeed.weeksBackLimit(earliest: now - 20 * day, now: now, calendar: Self.calendar) == 2)
	}

	@Test func anOlderDayIsNamedWithItsDate() {
		let older = ProfileFeed.Day(start: Self.calendar.date(byAdding: .day, value: -9,
		                                                      to: Self.calendar.startOfDay(for: now))!,
		                            minutes: 0, titles: [])
		let name = ProfileFeed.name(for: older, now: now, calendar: Self.calendar)
		#expect(name.contains("6"))   // Sunday 6 September
	}

	// MARK: Watched dates

	@Test func aWatchedDateMovesOnlyWhileWatchedAndNeverAhead() {
		let film = Film(title: "Thar")
		film.setWatchedDate(now - 3600, now: now)
		#expect(film.watchedAt == nil)

		film.mark(.watched, at: now)
		let lastMonth = WatchedWhen.monthAgo.date(now: now, calendar: Self.calendar)
		film.setWatchedDate(lastMonth, now: now)
		#expect(film.watchedAt == lastMonth)
		film.setWatchedDate(now + 86_400, now: now)
		#expect(film.watchedAt == now)

		film.mark(.toWatch)
		#expect(film.watchedAt == nil)
	}

	@Test func markingAnEpisodeWatchedEarlierDatesItThen() {
		let show = Show(title: "Severance")
		let season = Season(seasonNumber: 1)
		season.show = show
		let episode = Episode(episodeNumber: 1, seasonNumber: 1, title: "Good News About Hell")
		episode.season = season
		let yesterday = WatchedWhen.yesterday.date(now: now, calendar: Self.calendar)
		episode.markWatched(at: yesterday)
		#expect(episode.watchedAt == yesterday)
		#expect(episode.status == .watched)
	}

	@Test func watchedWhenReadsAsPeopleSayIt() {
		#expect(WatchedWhen.today.date(now: now, calendar: Self.calendar) == now)
		#expect(WatchedWhen.weekAgo.date(now: now, calendar: Self.calendar) == now - 7 * 86_400)
		#expect(WatchedWhen.label(for: now, now: now, calendar: Self.calendar) == "Watched today")
		#expect(WatchedWhen.label(for: now - 86_400, now: now, calendar: Self.calendar) == "Watched yesterday")
		let older = WatchedWhen.label(for: now - 30 * 86_400, now: now, calendar: Self.calendar)
		#expect(older.hasPrefix("Watched ") && older.contains("16"))   // 16 August
	}
}
