//
//  AiringTests.swift
//  WatchListTests
//
//  Episodes that haven't aired yet. TMDb lists a weekly show's coming episodes
//  ahead of time, often as "Episode 5" with no still or synopsis, so:
//    - Up Next, on the iPhone and the watch, stops at what's out and says when
//      the next one airs instead of offering one that hasn't
//    - the daily refresh keeps re-reading recent and coming episodes until
//      TMDb has filled them in, without touching anything that's yours
//  And a poster picked from Photos is found again after the app's container
//  moves.
//

import Foundation
import Testing
import UIKit
@testable import WatchList

/// A fixed "now" and calendar, so day boundaries don't depend on the machine.
private enum Clock {
	static var calendar: Calendar = {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(identifier: "UTC")!
		return calendar
	}()
	/// Saturday 7 November 2026, midday UTC.
	static let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 7, hour: 12))!
}

// MARK: - Air dates

@MainActor
struct AirDateTests {

	@Test func aDateIsOutFromItsDay() {
		#expect(AirDate.hasAired("2026-11-07", today: "2026-11-07") == true)
		#expect(AirDate.hasAired("2026-11-06", today: "2026-11-07") == true)
		#expect(AirDate.hasAired("2026-11-08", today: "2026-11-07") == false)
	}

	@Test func anEmptyOrPartialDateIsUndecided() {
		#expect(AirDate.hasAired("", today: "2026-11-07") == nil)
		#expect(AirDate.hasAired("2027", today: "2026-11-07") == nil)
		#expect(AirDate.dayPart(of: "2026-11-14T00:00:00Z") == "2026-11-14")
	}

	@Test func phrasedByHowFarOffItIs() {
		let gb = Locale(identifier: "en_GB")
		func phrase(_ date: String) -> String? {
			AirDate.phrase(date, now: Clock.now, calendar: Clock.calendar, locale: gb)
		}
		#expect(phrase("2026-11-08") == "tomorrow")
		#expect(phrase("2026-11-13") == "Friday")
		#expect(phrase("2026-11-20") == "20 Nov")
		#expect(phrase("2027-01-04") == "4 Jan 2027")
		#expect(phrase("") == nil)
	}

	@Test func theCaughtUpLineWithAndWithoutADate() {
		#expect(AirDate.caughtUpLine(nextAirDate: "2026-11-08", now: Clock.now, calendar: Clock.calendar)
		        == "Caught up · New episode tomorrow")
		#expect(AirDate.caughtUpLine(nextAirDate: "2026-11-08", short: true, now: Clock.now, calendar: Clock.calendar)
		        == "Caught up · Next tomorrow")
		#expect(AirDate.caughtUpLine(nextAirDate: nil) == "Caught up · More to come")
		#expect(AirDate.caughtUpLine(nextAirDate: nil, short: true) == "Caught up")
	}
}

// MARK: - Up Next

/// A Watching show from TMDb with one season, an episode per air date given.
@MainActor
private func airingShow(_ dates: [String], watched: Int = 0, fromTMDb: Bool = true) -> Show {
	let show = Show(title: "Weekly", status: .watching)
	let season = Season(seasonNumber: 1)
	season.show = show
	show.seasons.append(season)
	for (index, date) in dates.enumerated() {
		let episode = Episode(episodeNumber: index + 1, seasonNumber: 1, title: "E\(index + 1)",
		                      airDate: date, tmdbShowID: fromTMDb ? 1399 : nil)
		if index < watched { episode.status = .watched }
		episode.season = season
		season.episodes.append(episode)
	}
	return show
}

@MainActor
struct UpNextAiringTests {

	@Test func stopsAtWhatsOut() {
		let show = airingShow(["2026-10-24", "2026-10-31", "2026-11-14"], watched: 1)
		#expect(HomeFeed.nextEpisode(of: show, asOf: Clock.now)?.episodeNumber == 2)
		#expect(!HomeFeed.isCaughtUp(show, asOf: Clock.now))
	}

	@Test func caughtUpWhenOnlyUnairedAreLeft() {
		let show = airingShow(["2026-10-24", "2026-10-31", "2026-11-14"], watched: 2)
		#expect(HomeFeed.nextEpisode(of: show, asOf: Clock.now) == nil)
		#expect(HomeFeed.nextToAir(of: show, asOf: Clock.now)?.episodeNumber == 3)
		#expect(HomeFeed.isCaughtUp(show, asOf: Clock.now))
		#expect(HomeFeed.progressLine(for: show, next: nil, asOf: Clock.now).hasPrefix("Caught up · New episode"))
	}

	@Test func anEpisodeAiringTodayIsOut() {
		let show = airingShow(["2026-10-31", "2026-11-07"], watched: 1)
		#expect(HomeFeed.nextEpisode(of: show, asOf: Clock.now)?.episodeNumber == 2)
	}

	@Test func anUndatedEpisodeAfterTheLastAiredIsStillToAir() {
		// TMDb lists the rest of a season before it dates them.
		let show = airingShow(["2026-10-31", ""], watched: 1)
		#expect(HomeFeed.nextEpisode(of: show, asOf: Clock.now) == nil)
		#expect(HomeFeed.isCaughtUp(show, asOf: Clock.now))
	}

	@Test func anUndatedEpisodeBeforeAnAiredOneIsOut() {
		// The odd old episode TMDb has no date for mustn't block the rest.
		let show = airingShow(["", "2019-04-14"])
		#expect(HomeFeed.nextEpisode(of: show, asOf: Clock.now)?.episodeNumber == 1)
	}

	@Test func anUndatedEpisodeAddedByHandIsOut() {
		let show = airingShow(["", ""], fromTMDb: false)
		#expect(HomeFeed.nextEpisode(of: show, asOf: Clock.now)?.episodeNumber == 1)
	}

	@Test func markWatchedLeavesACaughtUpShowWatching() {
		let show = airingShow(["2026-10-31", "2026-11-14"], watched: 1)
		#expect(HomeFeed.markNextWatched(in: show, cascade: true, asOf: Clock.now) == nil)
		#expect(show.status == .watching)
		#expect(show.sortedSeasons[0].sortedEpisodes[1].status == .toWatch)
	}

	@Test func theWatchIsSentOnlyWhatsOutAndWhenTheNextAirs() {
		let show = airingShow(["2026-10-24", "2026-10-31", "2026-11-14", ""], watched: 1)
		let upNext = WatchSnapshotBuilder.upNext([show], upcoming: 5, asOf: Clock.now)
		#expect(upNext[0].upcoming.map(\.episodeNumber) == [2])
		#expect(upNext[0].remaining == 1)
		#expect(upNext[0].toAir == 2)
		#expect(upNext[0].nextAirDate == "2026-11-14")
	}

	@Test func aSnapshotWithoutTheAiringFieldsStillDecodes() throws {
		let json = #"{"id":"\#(UUID().uuidString)","title":"Old","artworkURL":"","upcoming":[],"remaining":0,"episodeCount":3}"#
		let show = try JSONDecoder().decode(UpNextShow.self, from: Data(json.utf8))
		#expect(show.toAir == nil)
		#expect(show.nextAirDate == nil)
	}
}

// MARK: - Refreshing episode details

@MainActor
struct EpisodeDetailRefreshTests {

	private func remote(_ fields: String) throws -> TMDbEpisode {
		try JSONDecoder().decode(TMDbEpisode.self, from: Data(#"{"episode_number":3,\#(fields)}"#.utf8))
	}

	private func placeholder(airDate: String = "2026-11-14") -> Episode {
		Episode(episodeNumber: 3, seasonNumber: 1, title: "Episode 3", airDate: airDate, tmdbShowID: 1399)
	}

	@Test func recentComingAndUndatedEpisodesAreProvisional() {
		func provisional(_ date: String) -> Bool {
			LibraryRefresher.isProvisional(placeholder(airDate: date), asOf: Clock.now, calendar: Clock.calendar)
		}
		#expect(provisional("2026-11-14"))
		#expect(provisional("2026-11-01"))
		#expect(provisional(""))
		#expect(!provisional("2026-10-01"))
	}

	@Test func anEpisodeAddedByHandNeverIs() {
		let episode = Episode(episodeNumber: 1, seasonNumber: 1, title: "Mine")
		#expect(!LibraryRefresher.isProvisional(episode, asOf: Clock.now))
	}

	@Test func aSeasonWithAComingEpisodeIsFetchedThoughItsCountMatches() {
		let season = Season(seasonNumber: 1)
		let episode = placeholder()
		episode.season = season
		season.episodes.append(episode)
		let plan = LibraryRefresher.seasonsNeedingFetch(
			summaries: [TMDbSeasonSummary(season_number: 1, episode_count: 1, name: nil)],
			existing: [season], asOf: Clock.now)
		#expect(plan == [1])
	}

	@Test func fillsInWhatTMDbHasSinceAdded() throws {
		let episode = placeholder()
		let changed = LibraryRefresher.update(episode, from: try remote(
			#""name":"The Long Night","overview":"Winter.","still_path":"/s.jpg","air_date":"2026-11-15","runtime":58"#),
			keepingStill: false)
		#expect(changed)
		#expect(episode.title == "The Long Night")
		#expect(episode.synopsis == "Winter.")
		#expect(episode.stillURL == TMDbConfig.still("/s.jpg"))
		#expect(episode.airDate == "2026-11-15")
		#expect(episode.runtimeMinutes == 58)
	}

	@Test func neverBlanksAField() throws {
		let episode = placeholder()
		episode.synopsis = "Kept"
		LibraryRefresher.update(episode, from: try remote(#""name":"","overview":null,"air_date":"""#),
		                        keepingStill: false)
		#expect(episode.title == "Episode 3")
		#expect(episode.synopsis == "Kept")
		#expect(episode.airDate == "2026-11-14")
	}

	@Test func keepsAStillPickedByHandAndEverythingYours() throws {
		let episode = placeholder()
		episode.stillURL = "https://image.tmdb.org/t/p/w300/mine.jpg"
		episode.mark(.watched)
		episode.episodeTier = .rewatch
		let watchedAt = episode.watchedAt
		LibraryRefresher.update(episode, from: try remote(#""name":"Named","still_path":"/theirs.jpg""#),
		                        keepingStill: true)
		#expect(episode.title == "Named")
		#expect(episode.stillURL == "https://image.tmdb.org/t/p/w300/mine.jpg")
		#expect(episode.status == .watched)
		#expect(episode.episodeTier == .rewatch)
		#expect(episode.watchedAt == watchedAt)
	}

	@Test func nothingNewIsNoChange() throws {
		let episode = placeholder()
		#expect(!LibraryRefresher.update(episode, from: try remote(#""name":"Episode 3""#), keepingStill: false))
	}

	@Test func theSummaryMentionsUpdates() {
		#expect(LibraryRefresher.Report(showsChecked: 1, episodesUpdated: 2).summary == "Updated 2 episodes.")
		#expect(LibraryRefresher.Report(showsChecked: 1, episodesAdded: 1, episodesUpdated: 1).summary
		        == "Added 1 new episode. Updated 1 episode.")
	}
}

// MARK: - Manual posters

struct ManualPosterTests {

	@Test func aPosterSavedInAnEarlierContainerIsFoundInThisOne() {
		let old = URL(string: "file:///var/mobile/Containers/Data/Application/OLD-UUID/Documents/ManualPosters/abc.jpg")!
		let resolved = ManualPosterStore.resolve(old)
		#expect(resolved == ManualPosterStore.directory.appendingPathComponent("abc.jpg"))
	}

	@Test func otherURLsAreLeftAsTheyAre() {
		let tmdb = URL(string: "https://image.tmdb.org/t/p/w500/x.jpg")!
		let elsewhere = URL(string: "file:///tmp/other/x.jpg")!
		#expect(ManualPosterStore.resolve(tmdb) == tmdb)
		#expect(ManualPosterStore.resolve(elsewhere) == elsewhere)
	}

	@Test func removingDeletesOnlyOurFile() throws {
		let saved = try #require(ManualPosterStore.save(pngData()))
		let file = ManualPosterStore.resolve(URL(string: saved)!)
		#expect(FileManager.default.fileExists(atPath: file.path))
		ManualPosterStore.remove("https://image.tmdb.org/t/p/w500/x.jpg")
		#expect(FileManager.default.fileExists(atPath: file.path))
		ManualPosterStore.remove(saved)
		#expect(!FileManager.default.fileExists(atPath: file.path))
	}

	private func pngData() -> Data {
		UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
			UIColor.red.setFill()
			context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
		}
	}
}

// MARK: - New-episode alerts

@MainActor
struct EpisodeAlertTests {

	@Test func justAiredUnwatchedEpisodesOfWatchingShowsAreDue() {
		let show = airingShow(["2026-10-20", "2026-11-06", "2026-11-07", "2026-11-14"], watched: 0)
		let due = EpisodeAlerts.due(in: [show], notified: [], asOf: Clock.now, calendar: Clock.calendar)
		#expect(due.map(\.episodeNumber) == [2, 3])               // not the old one, not the coming one
	}

	@Test func nothingTwiceAndNothingWatched() {
		let show = airingShow(["2026-11-06", "2026-11-07"], watched: 1)
		let second = show.sortedSeasons[0].sortedEpisodes[1]
		#expect(EpisodeAlerts.due(in: [show], notified: [second.id], asOf: Clock.now, calendar: Clock.calendar).isEmpty)
	}

	@Test func onlyShowsBeingWatched() {
		let show = airingShow(["2026-11-07"])
		show.status = .toWatch
		#expect(EpisodeAlerts.due(in: [show], notified: [], asOf: Clock.now, calendar: Clock.calendar).isEmpty)
	}

	@Test func oneAlertAShow() {
		let show = airingShow(["2026-11-06", "2026-11-07"])
		let second = show.sortedSeasons[0].sortedEpisodes[1]
		let one = EpisodeAlerts.alerts(for: [second])
		#expect(one == [EpisodeAlerts.Alert(id: "new-episodes-\(show.id.uuidString)", title: "Weekly",
		                                    body: "\(ShowFacts.code(second)) · E2 is out now.")])
		let both = EpisodeAlerts.alerts(for: show.sortedSeasons[0].sortedEpisodes)
		#expect(both.count == 1)
		#expect(both[0].body == "2 new episodes are out.")
	}
}
