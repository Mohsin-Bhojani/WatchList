//
//  HomeFeed.swift
//  WatchList
//
//  What the iPhone Home screen shows, worked out from the library: the shows in
//  progress and the episode each is up to, what Mark Watched touches, and
//  everything Watched in the order it was marked. Kept apart from the views so
//  it can be tested.
//

import Foundation
import SwiftUI
import WatchListCore

/// A show or film on Home's Recently watched row, or in the Shows tab's grid
/// when it lists both.
public enum WatchedTitle: Identifiable {
	case show(Show)
	case film(Film)

	public var id: UUID {
		switch self {
		case .show(let show): return show.id
		case .film(let film): return film.id
		}
	}

	public var title: String {
		switch self {
		case .show(let show): return show.title
		case .film(let film): return film.title
		}
	}

	public var posterURL: String {
		switch self {
		case .show(let show): return show.posterURL
		case .film(let film): return film.posterURL
		}
	}

	public var rating: Rating? {
		switch self {
		case .show(let show): return show.rating
		case .film(let film): return film.rating
		}
	}

	/// The stars shown for it: picked by hand, or its verdict's own.
	public var stars: Double? {
		switch self {
		case .show(let show): return show.shownStars
		case .film(let film): return film.shownStars
		}
	}

	public var watchedAt: Date? {
		switch self {
		case .show(let show): return show.watchedAt
		case .film(let film): return film.watchedAt
		}
	}

	/// Its comma-separated genres.
	public var genre: String {
		switch self {
		case .show(let show): return show.genre
		case .film(let film): return film.genre
		}
	}

	/// The year it came out — a show's first season — when it's known.
	public var year: Int? {
		switch self {
		case .show(let show): return Int(show.firstAirYear.prefix(4))
		case .film(let film): return Int(film.year.prefix(4))
		}
	}

	public var kind: MediaKind {
		switch self {
		case .show: return .show
		case .film: return .film
		}
	}

	/// Nil for a title added by hand.
	public var tmdbID: Int? {
		switch self {
		case .show(let show): return show.tmdbID
		case .film(let film): return film.tmdbID
		}
	}

	/// When its verdict was last given or changed.
	public var ratedAt: Date? {
		switch self {
		case .show(let show): return show.ratedAt
		case .film(let film): return film.ratedAt
		}
	}

	/// Its synopsis; empty when there's none.
	public var synopsis: String {
		switch self {
		case .show(let show): return show.overview
		case .film(let film): return film.synopsis
		}
	}

	public var dateAdded: Date {
		switch self {
		case .show(let show): return show.dateAdded
		case .film(let film): return film.dateAdded
		}
	}

	public var status: WatchStatus {
		switch self {
		case .show(let show): return show.status
		case .film(let film): return film.status
		}
	}

	/// A grid card's line: a show's seasons and episodes, a film's year and
	/// first genre.
	public var cardSubtitle: String {
		switch self {
		case .show(let show):
			return show.subtitle
		case .film(let film):
			return [film.year, film.genre.components(separatedBy: ", ").first ?? ""]
				.filter { !$0.isEmpty }.joined(separator: " · ")
		}
	}

	public var kindLabel: String {
		switch self {
		case .show: return "Show"
		case .film: return "Film"
		}
	}

	public var placeholder: String {
		switch self {
		case .show: return "tv"
		case .film: return "film"
		}
	}
}

public enum HomeFeed {

	// MARK: In progress

	/// Shows set to Watching — the hero's pages — in the order given.
	public static func watching(_ shows: [Show]) -> [Show] {
		shows.filter { $0.status == .watching }
	}

	/// The episode to watch next: the first not yet Watched that has aired,
	/// running through the seasons in order with specials (season 0) saved for
	/// last. Nil once you're caught up, even with episodes still to air.
	public static func nextEpisode(of show: Show, asOf now: Date = .now) -> Episode? {
		unwatched(of: show, asOf: now).out.first
	}

	/// The first episode not yet Watched that hasn't aired — what a caught-up
	/// show is waiting on. Nil when nothing is still to air.
	public static func nextToAir(of show: Show, asOf now: Date = .now) -> Episode? {
		unwatched(of: show, asOf: now).toAir.first
	}

	/// A show's episodes not yet Watched, in running order, split into those out
	/// by `now` and those still to air. What Home, the watch and the widget
	/// each show of a show is read from this.
	public static func unwatched(of show: Show, asOf now: Date = .now) -> (out: [Episode], toAir: [Episode]) {
		let order = runningOrder(of: show)
		let pairs = zip(order, aired(order, asOf: now)).filter { $0.0.status != .watched }
		return (pairs.filter(\.1).map(\.0), pairs.filter { !$0.1 }.map(\.0))
	}

	/// True when every episode that's out is Watched but some are still to air.
	public static func isCaughtUp(_ show: Show, asOf now: Date = .now) -> Bool {
		nextEpisode(of: show, asOf: now) == nil && nextToAir(of: show, asOf: now) != nil
	}

	/// Which of `order` are out by `now`, one flag each.
	///
	/// A dated episode is out from its air date. TMDb leaves the date off
	/// episodes it hasn't scheduled yet — and off the odd old one — so an
	/// undated episode counts as out when it's one added by hand (no TMDb show),
	/// a special, or comes before one in the main run that has aired.
	public static func aired(_ order: [Episode], asOf now: Date = .now) -> [Bool] {
		let today = AirDate.day(now)
		let lastAired = order.lastIndex {
			$0.seasonNumber != 0 && AirDate.hasAired($0.airDate, today: today) == true
		}
		return order.indices.map { index in
			let episode = order[index]
			if let aired = AirDate.hasAired(episode.airDate, today: today) { return aired }
			if episode.tmdbShowID == nil || episode.seasonNumber == 0 { return true }
			return lastAired.map { index < $0 } ?? false
		}
	}

	/// Every episode in the order it runs: season by season, specials last.
	public static func runningOrder(of show: Show) -> [Episode] {
		show.seasons
			.sorted { runOrder($0.seasonNumber) < runOrder($1.seasonNumber) }
			.flatMap(\.sortedEpisodes)
	}

	private static func runOrder(_ seasonNumber: Int) -> Int {
		seasonNumber == 0 ? Int.max : seasonNumber
	}

	/// The season Up Next's bar is drawn from: the next episode's, else the
	/// one waiting to air, else the last in the main run. Nil with no episodes.
	public static func currentSeason(of show: Show, next: Episode?, asOf now: Date = .now) -> Season? {
		if let season = (next ?? nextToAir(of: show, asOf: now))?.season { return season }
		return show.sortedSeasons.last { $0.seasonNumber > 0 && !$0.episodes.isEmpty }
			?? show.sortedSeasons.last { !$0.episodes.isEmpty }
	}

	/// The episode watched most recently — the latest watched date, else the
	/// furthest on in running order. Nil when none is watched.
	public static func lastWatched(in show: Show) -> Episode? {
		let order = runningOrder(of: show)
		return order.indices
			.filter { order[$0].status == .watched }
			.max { lhs, rhs in
				let (l, r) = (order[lhs].watchedAt ?? .distantPast, order[rhs].watchedAt ?? .distantPast)
				return l != r ? l < r : lhs < rhs
			}
			.map { order[$0] }
	}

	/// "Season 2 · Episode 8" — "Specials" standing in for season 0.
	public static func episodeLine(_ episode: Episode) -> String {
		EpisodeCode.long(season: episode.seasonNumber, episode: episode.episodeNumber)
	}

	/// The episode line while there's an episode to go; after that, why Mark
	/// Watched now finishes the show instead.
	public static func progressLine(for show: Show, next: Episode?, asOf now: Date = .now) -> String {
		if let next { return episodeLine(next) }
		if let waiting = nextToAir(of: show, asOf: now) {
			return AirDate.caughtUpLine(nextAirDate: waiting.airDate, now: now)
		}
		let count = show.episodeCount
		return count == 0 ? "No episodes tracked" : "All \(count) episodes watched"
	}

	/// What the rating sheet does with a pick: records the rating when one was
	/// chosen — marking watched without one leaves an earlier rating alone —
	/// and marks the episode Watched, starting its season and show.
	public static func markWatched(_ episode: Episode, tier: EpisodeTier?) {
		if let tier { episode.episodeTier = tier }
		episode.markWatched()
	}

	/// Home's Mark Watched. Marks the next episode when there is one. Once
	/// every episode is Watched it marks the show itself — cascading down to
	/// seasons and episodes the way the Show page does, when `cascade` (the
	/// "Mark all episodes watched" setting) is on. A show caught up with
	/// episodes still to air is left as it is. Returns the episode marked.
	@discardableResult
	public static func markNextWatched(in show: Show, cascade: Bool, asOf now: Date = .now) -> Episode? {
		if let episode = nextEpisode(of: show, asOf: now) {
			episode.markWatched()
			return episode
		}
		guard nextToAir(of: show, asOf: now) == nil else { return nil }
		show.mark(.watched)
		if cascade {
			for season in show.seasons {
				season.markWatched()
				for episode in season.episodes { episode.markWatched() }
			}
		}
		return nil
	}

	// MARK: To Watch

	/// Shows and films still To Watch, newest added first — leaving out any
	/// already rated Skip, since those aren't worth suggesting.
	public static func toWatch(shows: [Show], films: [Film]) -> [WatchedTitle] {
		let titles = shows.filter { $0.status == .toWatch && $0.rating != .skip }.map(WatchedTitle.show)
			+ films.filter { $0.status == .toWatch && $0.rating != .skip }.map(WatchedTitle.film)
		return titles.sorted { $0.dateAdded > $1.dateAdded }
	}

	// MARK: Recently watched

	/// Shows and films marked Watched, most recently marked first. Titles with
	/// no recorded date — Watched before dates were kept — follow, newest-added
	/// first.
	public static func recentlyWatched(shows: [Show], films: [Film]) -> [WatchedTitle] {
		let titles = shows.filter { $0.status == .watched }.map(WatchedTitle.show)
			+ films.filter { $0.status == .watched }.map(WatchedTitle.film)
		return titles.sorted { lhs, rhs in
			switch (lhs.watchedAt, rhs.watchedAt) {
			case let (left?, right?) where left != right: return left > right
			case (.some, .none): return true
			case (.none, .some): return false
			default: return lhs.dateAdded > rhs.dateAdded
			}
		}
	}
}
