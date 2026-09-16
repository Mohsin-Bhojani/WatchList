//
//  HomeFeedTests.swift
//  WatchListTests
//
//  The iPhone Home screen's bookkeeping: which episode a show is up to, what
//  Mark Watched touches, the order of Recently watched, how a status change
//  becomes a watched date, which artwork the hero picks and the colour band it
//  fades into.
//

import Foundation
import Testing
import UIKit
@testable import WatchList

@MainActor
struct NextEpisodeTests {

	/// A Watching show whose seasons each hold `episodes` To Watch episodes.
	private func show(_ seasons: [(number: Int, episodes: Int)]) -> Show {
		let show = Show(title: "Test", status: .watching)
		for spec in seasons {
			let season = Season(seasonNumber: spec.number)
			season.show = show
			show.seasons.append(season)
			for n in 0..<spec.episodes {
				let episode = Episode(episodeNumber: n + 1, seasonNumber: spec.number, title: "E\(n + 1)")
				episode.season = season
				season.episodes.append(episode)
			}
		}
		return show
	}

	private func markWatched(_ show: Show, season: Int, through last: Int) {
		for episode in show.seasons.first(where: { $0.seasonNumber == season })!.episodes
		where episode.episodeNumber <= last {
			episode.status = .watched
		}
	}

	@Test func upToTheFirstUnwatchedEpisodeInOrder() {
		let s = show([(2, 3), (1, 2)])   // stored out of order on purpose
		markWatched(s, season: 1, through: 2)
		markWatched(s, season: 2, through: 1)
		let next = HomeFeed.nextEpisode(of: s)
		#expect(next?.seasonNumber == 2)
		#expect(next?.episodeNumber == 2)
		#expect(HomeFeed.progressLine(for: s, next: next) == "Season 2 · Episode 2")
	}

	@Test func specialsWaitUntilTheMainRunIsDone() {
		let s = show([(0, 2), (1, 1)])
		#expect(HomeFeed.nextEpisode(of: s)?.seasonNumber == 1)
		markWatched(s, season: 1, through: 1)
		let next = HomeFeed.nextEpisode(of: s)
		#expect(next?.seasonNumber == 0)
		#expect(HomeFeed.progressLine(for: s, next: next) == "Specials · Episode 1")
	}

	@Test func nothingNextOnceEverythingIsWatched() {
		let s = show([(1, 2)])
		markWatched(s, season: 1, through: 2)
		#expect(HomeFeed.nextEpisode(of: s) == nil)
		#expect(HomeFeed.progressLine(for: s, next: nil) == "All 2 episodes watched")
		#expect(HomeFeed.progressLine(for: show([]), next: nil) == "No episodes tracked")
	}

	@Test func markWatchedTakesOneEpisodeAtATime() {
		let s = show([(1, 2)])
		let marked = HomeFeed.markNextWatched(in: s, cascade: true)
		#expect(marked?.episodeNumber == 1)
		#expect(marked?.status == .watched)
		#expect(s.status == .watching)
		#expect(HomeFeed.nextEpisode(of: s)?.episodeNumber == 2)
	}

	@Test func markWatchedFinishesTheShowOnlyWhenNothingIsLeft() {
		let s = show([(1, 1)])
		HomeFeed.markNextWatched(in: s, cascade: true)
		#expect(s.status == .watching)

		#expect(HomeFeed.markNextWatched(in: s, cascade: true) == nil)
		#expect(s.status == .watched)
		#expect(s.seasons.allSatisfy { $0.status == .watched })
	}

	@Test func ratingAnEpisodeMarksItWatchedWithThatRating() {
		let s = show([(1, 2)])
		let first = HomeFeed.nextEpisode(of: s)!
		#expect(HomeFeed.episodeLine(first) == "Season 1 · Episode 1")

		HomeFeed.markWatched(first, tier: .rewatch)
		#expect(first.status == .watched)
		#expect(first.episodeTier == .rewatch)
		#expect(HomeFeed.nextEpisode(of: s)?.episodeNumber == 2)
	}

	@Test func markingWithoutARatingKeepsAnEarlierOne() {
		let s = show([(1, 1)])
		let episode = HomeFeed.nextEpisode(of: s)!
		episode.episodeTier = .watch
		HomeFeed.markWatched(episode, tier: nil)
		#expect(episode.status == .watched)
		#expect(episode.episodeTier == .watch)
	}

	@Test func finishingWithTheSettingOffLeavesSeasonsAlone() {
		let s = show([(1, 1)])
		HomeFeed.markNextWatched(in: s, cascade: false)
		HomeFeed.markNextWatched(in: s, cascade: false)
		#expect(s.status == .watched)
		#expect(s.seasons.allSatisfy { $0.status == .toWatch })
	}
}

@MainActor
struct RecentlyWatchedOrderTests {

	@Test func mostRecentlyMarkedFirstThenUndatedByDateAdded() {
		let now = Date(timeIntervalSince1970: 1_800_000_000)
		let marked10sAgo = Show(title: "Marked 10s ago", status: .watched)
		marked10sAgo.watchedAt = now.addingTimeInterval(-10)
		let marked1hAgo = Show(title: "Marked 1h ago", status: .watched)
		marked1hAgo.watchedAt = now.addingTimeInterval(-3_600)
		let film = Film(title: "Film marked 1m ago", status: .watched)
		film.watchedAt = now.addingTimeInterval(-60)
		let addedEarly = Show(title: "Undated, added early", status: .watched)
		addedEarly.watchedAt = nil
		addedEarly.dateAdded = now.addingTimeInterval(-5_000)
		let addedLate = Film(title: "Undated, added late", status: .watched)
		addedLate.watchedAt = nil
		addedLate.dateAdded = now.addingTimeInterval(-10)
		let stillWatching = Show(title: "Still watching", status: .watching)
		stillWatching.watchedAt = now   // a stale date must not sneak it in

		let order = HomeFeed.recentlyWatched(shows: [marked1hAgo, addedEarly, marked10sAgo, stillWatching],
		                                     films: [addedLate, film]).map(\.title)
		#expect(order == ["Marked 10s ago", "Film marked 1m ago", "Marked 1h ago",
		                  "Undated, added late", "Undated, added early"])
	}
}

@MainActor
struct ToWatchRowTests {

	@Test func toWatchTitlesNewestAddedFirstLeavingOutSkip() {
		let now = Date(timeIntervalSince1970: 1_800_000_000)
		let showAddedEarly = Show(title: "Show added early", status: .toWatch)
		showAddedEarly.dateAdded = now.addingTimeInterval(-5_000)
		let filmAddedLate = Film(title: "Film added late", status: .toWatch, rating: .goForIt)
		filmAddedLate.dateAdded = now.addingTimeInterval(-10)
		let filmAddedMid = Film(title: "Film added mid", status: .toWatch)
		filmAddedMid.dateAdded = now.addingTimeInterval(-600)
		let ratedSkip = Show(title: "Rated Skip", status: .toWatch, rating: .skip)
		ratedSkip.dateAdded = now
		let watching = Show(title: "Watching", status: .watching)
		watching.dateAdded = now
		let watched = Film(title: "Watched", status: .watched)
		watched.dateAdded = now

		let order = HomeFeed.toWatch(shows: [showAddedEarly, ratedSkip, watching],
		                             films: [filmAddedMid, watched, filmAddedLate]).map(\.title)
		#expect(order == ["Film added late", "Film added mid", "Show added early"])
	}
}

@MainActor
struct WatchTrackingTests {
	private let then = Date(timeIntervalSince1970: 1_700_000_000)
	private let now = Date(timeIntervalSince1970: 1_800_000_000)

	@Test func becomingWatchedIsDated() {
		let film = Film(title: "Film", status: .watching)
		film.mark(.watched, at: now)
		#expect(film.watchedAt == now)
	}

	@Test func stayingWatchedKeepsTheOriginalDate() {
		let episode = Episode(episodeNumber: 1, seasonNumber: 1, title: "E1")
		episode.mark(.watched, at: then)
		episode.mark(.watched, at: now)
		#expect(episode.watchedAt == then)
	}

	@Test func unwatchingForgetsTheDate() {
		let show = Show(title: "Show")
		show.mark(.watched, at: then)
		show.mark(.watching, at: now)
		#expect(show.status == .watching)
		#expect(show.watchedAt == nil)
	}

	@Test func arrivingAlreadyWatchedIsDated() {
		#expect(Film(title: "Film", status: .watched).watchedAt != nil)
		#expect(Film(title: "Film").watchedAt == nil)
	}

	@Test func aVerdictIsDatedWhenItsGivenOrChanged() {
		let film = Film(title: "Film")
		#expect(film.ratedAt == nil)
		film.setVerdict(.goForIt, at: then)
		#expect(film.ratedAt == then)
		film.rate(.goForIt, stars: 4.5, at: now)       // new stars, same verdict
		#expect(film.ratedAt == then)
		film.setVerdict(.perfection, at: now)
		#expect(film.ratedAt == now)
		film.setVerdict(nil, at: now)
		#expect(film.ratedAt == nil)
		#expect(Show(title: "Rated on arrival", rating: .skip).ratedAt != nil)
	}
}

@MainActor
struct HeroArtTests {

	private func savedShow() -> Show {
		Show(title: "Test",
		     posterURL: "https://image.tmdb.org/t/p/w500/saved.jpg",
		     backdropURL: "https://image.tmdb.org/t/p/w780/saved-backdrop.jpg")
	}

	private func entry(_ path: String, _ kind: ImageEntry.Kind, language: String?, width: Int = 1920) -> ImageEntry {
		ImageEntry(id: path, kind: kind, thumbURL: "", fullURL: "", width: width, height: 0,
		           language: language, voteAverage: 0)
	}

	@Test func prefersATextlessBackdropAtFullSize() {
		let gallery = ImageGallery(groups: [
			ImageGroup(kind: .poster, entries: [entry("/clean-poster.jpg", .poster, language: nil)]),
			ImageGroup(kind: .backdrop, entries: [entry("/titled.jpg", .backdrop, language: "en"),
			                                      entry("/wide.jpg", .backdrop, language: nil)]),
		])
		#expect(HomeFeed.heroArtURL(for: savedShow(), gallery: gallery) == "https://image.tmdb.org/t/p/original/wide.jpg")
	}

	@Test func anOversizedBackdropComesDownAt1280() {
		let gallery = ImageGallery(groups: [
			ImageGroup(kind: .backdrop, entries: [entry("/4k.jpg", .backdrop, language: nil, width: 3840)]),
		])
		#expect(HomeFeed.heroArtURL(for: savedShow(), gallery: gallery) == "https://image.tmdb.org/t/p/w1280/4k.jpg")
	}

	@Test func thenATextlessPoster() {
		let gallery = ImageGallery(groups: [
			ImageGroup(kind: .poster, entries: [entry("/clean-poster.jpg", .poster, language: nil)]),
			ImageGroup(kind: .backdrop, entries: [entry("/titled.jpg", .backdrop, language: "en")]),
		])
		#expect(HomeFeed.heroArtURL(for: savedShow(), gallery: gallery) == "https://image.tmdb.org/t/p/w780/clean-poster.jpg")
	}

	@Test func thenTheSavedBackdropAtHeroSize() {
		#expect(HomeFeed.heroArtURL(for: savedShow(), gallery: ImageGallery())
		        == "https://image.tmdb.org/t/p/w1280/saved-backdrop.jpg")
	}

	@Test func aPosterPickedFromPhotosIsUsedAsIs() {
		let manual = Show(title: "Mine", posterURL: "file:///var/mobile/ManualPosters/mine.jpg")
		#expect(HomeFeed.heroArtURL(for: manual, gallery: nil) == "file:///var/mobile/ManualPosters/mine.jpg")
	}
}

@MainActor
struct ArtworkBandTests {

	/// The hero art box on an iPhone 17 Pro.
	private let box = CGSize(width: 402, height: 452)

	private func solidImage(_ color: UIColor) -> UIImage {
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		format.preferredRange = .standard
		return UIGraphicsImageRenderer(size: CGSize(width: 64, height: 36), format: format).image { context in
			color.setFill()
			context.fill(CGRect(x: 0, y: 0, width: 64, height: 36))
		}
	}

	@Test func aWideImageShowsItsMiddle() {
		let visible = ArtworkBand.visibleRect(imageSize: CGSize(width: 1920, height: 1080), in: box)
		#expect(abs(visible.height - 1080) < 0.5)
		#expect(abs(visible.width - 960.5) < 1)
		#expect(abs(visible.midX - 960) < 0.5)
	}

	@Test func aTallImageShowsItsMiddleBand() {
		let visible = ArtworkBand.visibleRect(imageSize: CGSize(width: 780, height: 1170), in: box)
		#expect(abs(visible.width - 780) < 0.5)
		#expect(abs(visible.height - 877) < 1)
		#expect(abs(visible.midY - 585) < 0.5)
	}

	@Test func theBandIsSampledFromTheTopOfWhatsVisible() {
		let strip = ArtworkBand.topStrip(of: CGRect(x: 480, y: 0, width: 960, height: 1080))
		#expect(strip.minX == 480 && strip.minY == 0 && strip.width == 960)
		#expect(abs(strip.height - 86.4) < 0.01)
	}

	@Test func theDesignBlueComesBackUnchanged() throws {
		let sampled = try #require(ArtworkBand.color(for: solidImage(ArtworkBand.fallback), in: box))
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		sampled.getRed(&r, green: &g, blue: &b, alpha: &a)
		#expect(abs(r * 255 - 31) < 3)
		#expect(abs(g * 255 - 126) < 3)
		#expect(abs(b * 255 - 217) < 3)
	}

	@Test func aBrightSampleIsDimmedForWhiteText() throws {
		let yellow = UIColor(red: 1, green: 0.84, blue: 0, alpha: 1)
		let sampled = try #require(ArtworkBand.color(for: solidImage(yellow), in: box))
		#expect(abs(ArtworkBand.relativeLuminance(sampled) - ArtworkBand.maxLuminance) < 0.02)
		var hue: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
		sampled.getHue(&hue, saturation: &s, brightness: &v, alpha: &a)
		#expect(abs(hue - 0.14) < 0.02)
	}

	@Test func aCardTopKeepsThePostersOwnBrightness() throws {
		let yellow = UIColor(red: 1, green: 0.84, blue: 0, alpha: 1)
		let sampled = try #require(ArtworkBand.color(for: solidImage(yellow), in: CGSize(width: 132, height: 198),
		                                             dimmedForWhiteText: false))
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		sampled.getRed(&r, green: &g, blue: &b, alpha: &a)
		#expect(abs(r - 1) < 0.02)
		#expect(abs(g - 0.84) < 0.02)
		#expect(b < 0.02)
	}

	@Test func aFilmsThemeKeepsItsPostersHue() throws {
		let teal = UIColor(red: 0.1, green: 0.5, blue: 0.5, alpha: 1)
		let theme = try #require(ArtworkBand.themeColor(for: solidImage(teal)))
		var h1: CGFloat = 0, s1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
		var h2: CGFloat = 0, s2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
		teal.getHue(&h1, saturation: &s1, brightness: &b1, alpha: &a1)
		theme.getHue(&h2, saturation: &s2, brightness: &b2, alpha: &a2)
		#expect(abs(h1 - h2) < 0.02)
		#expect(s2 > s1)
		#expect(ArtworkBand.relativeLuminance(theme) <= ArtworkBand.maxLuminance + 0.01)
	}

	@Test func aGreyPosterGivesAGreyPage() throws {
		let theme = try #require(ArtworkBand.themeColor(for: solidImage(UIColor(white: 0.2, alpha: 1))))
		var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		theme.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
		#expect(s < 0.02)
	}

	@Test func theDeeperEndKeepsTheHue() {
		let deeper = ArtworkBand.deeper(UIColor(hue: 0.95, saturation: 0.7, brightness: 0.5, alpha: 1))
		var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		deeper.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
		#expect(abs(h - 0.95) < 0.01)
		#expect(abs(b - 0.3) < 0.01)
	}

	@Test func midSwipeTheColourIsBetweenTheTwoShows() {
		let navy = UIColor(red: 0.1, green: 0.2, blue: 0.4, alpha: 1)
		let teal = UIColor(red: 0.1, green: 0.5, blue: 0.5, alpha: 1)
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		ArtworkBand.mix(navy, teal, 0.5).getRed(&r, green: &g, blue: &b, alpha: &a)
		#expect(abs(r - 0.1) < 0.001 && abs(g - 0.35) < 0.001 && abs(b - 0.45) < 0.001)
		// Overshooting the last page (a rubber-band past the end) holds its colour.
		ArtworkBand.mix(navy, teal, 1.4).getRed(&r, green: &g, blue: &b, alpha: &a)
		#expect(abs(g - 0.5) < 0.001)
	}

	@Test func onlyADarkBandNeedsHelpWithLightModeStatusBarText() {
		#expect(!ArtworkBand.hidesDarkStatusBarText(ArtworkBand.fallback))
		#expect(ArtworkBand.hidesDarkStatusBarText(UIColor(red: 0.08, green: 0.12, blue: 0.08, alpha: 1)))
	}
}

@MainActor
struct HeroLoopTests {

	@Test func eachEndIsCopiedRoundTheOther() {
		#expect(HeroLoop.pages(count: 3) == [2, 0, 1, 2, 0])
		#expect(HeroLoop.start(count: 3) == 1)
	}

	@Test func oneShowDoesNotLoop() {
		#expect(HeroLoop.pages(count: 1) == [0])
		#expect(HeroLoop.start(count: 1) == 0)
		#expect(HeroLoop.settled(0, count: 1) == 0)
		#expect(HeroLoop.pages(count: 0).isEmpty)
	}

	@Test func restingOnACopySwapsToTheRealPage() {
		#expect(HeroLoop.settled(0, count: 3) == 3)   // back past the first: the real last
		#expect(HeroLoop.settled(4, count: 3) == 1)   // on past the last: the real first
		#expect(HeroLoop.settled(2, count: 3) == 2)   // a real page stays put
	}

	@Test func aPageAShorterListLeftOutOfRangeComesBack() {
		#expect(HeroLoop.settled(5, count: 2) == 1)
	}

	@Test func thePageDotsFollowTheShowNotThePage() {
		#expect(HeroLoop.showIndex(ofPage: 0, count: 3) == 2)
		#expect(HeroLoop.showIndex(ofPage: 4, count: 3) == 0)
		#expect(HeroLoop.showIndex(ofPage: 2, count: 3) == 1)
	}
}
