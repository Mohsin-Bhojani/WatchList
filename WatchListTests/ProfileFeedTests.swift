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

	@Test func episodesMarkedInOneGoAreLeftOut() {
		// A season set to Watched marks every episode within the same instant.
		let season = (0..<8).map {
			watch(chicago, "Chicago P.D.", minutes: 43, daysAgo: 0, second: Double($0) * 0.01)
		}
		let evening = [
			watch(severance, "Severance", minutes: 50, daysAgo: 0),
			watch(severance, "Severance", minutes: 50, daysAgo: 0, hour: 10),
		]
		// Marked in the same instant as the season, but a film always counts.
		let film = watch(thar, "Thar", film: true, minutes: 128, daysAgo: 0)

		let kept = ProfileFeed.watchedOneByOne(season + evening + [film])
		#expect(!kept.contains { $0.titleID == chicago })
		#expect(kept.filter { $0.titleID == severance }.count == 2)
		#expect(kept.contains { $0.titleID == thar })
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
}
