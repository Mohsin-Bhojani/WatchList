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

/// A show or film on Home's Recently watched row, or in the Shows tab's grid
/// when it lists both.
enum WatchedTitle: Identifiable {
	case show(Show)
	case film(Film)

	var id: UUID {
		switch self {
		case .show(let show): return show.id
		case .film(let film): return film.id
		}
	}

	var title: String {
		switch self {
		case .show(let show): return show.title
		case .film(let film): return film.title
		}
	}

	var posterURL: String {
		switch self {
		case .show(let show): return show.posterURL
		case .film(let film): return film.posterURL
		}
	}

	var rating: Rating? {
		switch self {
		case .show(let show): return show.rating
		case .film(let film): return film.rating
		}
	}

	/// The stars shown for it: picked by hand, or its verdict's own.
	var stars: Double? {
		switch self {
		case .show(let show): return show.shownStars
		case .film(let film): return film.shownStars
		}
	}

	var watchedAt: Date? {
		switch self {
		case .show(let show): return show.watchedAt
		case .film(let film): return film.watchedAt
		}
	}

	/// Its comma-separated genres.
	var genre: String {
		switch self {
		case .show(let show): return show.genre
		case .film(let film): return film.genre
		}
	}

	/// The year it came out — a show's first season — when it's known.
	var year: Int? {
		switch self {
		case .show(let show): return Int(show.firstAirYear.prefix(4))
		case .film(let film): return Int(film.year.prefix(4))
		}
	}

	var kind: MediaKind {
		switch self {
		case .show: return .show
		case .film: return .film
		}
	}

	/// Nil for a title added by hand.
	var tmdbID: Int? {
		switch self {
		case .show(let show): return show.tmdbID
		case .film(let film): return film.tmdbID
		}
	}

	/// When its verdict was last given or changed.
	var ratedAt: Date? {
		switch self {
		case .show(let show): return show.ratedAt
		case .film(let film): return film.ratedAt
		}
	}

	/// Its synopsis; empty when there's none.
	var synopsis: String {
		switch self {
		case .show(let show): return show.overview
		case .film(let film): return film.synopsis
		}
	}

	var dateAdded: Date {
		switch self {
		case .show(let show): return show.dateAdded
		case .film(let film): return film.dateAdded
		}
	}

	var status: WatchStatus {
		switch self {
		case .show(let show): return show.status
		case .film(let film): return film.status
		}
	}

	/// A grid card's line: a show's seasons and episodes, a film's year and
	/// first genre.
	var cardSubtitle: String {
		switch self {
		case .show(let show):
			return show.subtitle
		case .film(let film):
			return [film.year, film.genre.components(separatedBy: ", ").first ?? ""]
				.filter { !$0.isEmpty }.joined(separator: " · ")
		}
	}

	var kindLabel: String {
		switch self {
		case .show: return "Show"
		case .film: return "Film"
		}
	}

	var placeholder: String {
		switch self {
		case .show: return "tv"
		case .film: return "film"
		}
	}

	@ViewBuilder var destination: some View {
		switch self {
		case .show(let show): PhoneShowDetailView(show: show)
		case .film(let film): PhoneFilmDetailView(film: film)
		}
	}
}

enum HomeFeed {

	// MARK: In progress

	/// Shows set to Watching — the hero's pages — in the order given.
	static func watching(_ shows: [Show]) -> [Show] {
		shows.filter { $0.status == .watching }
	}

	/// The episode to watch next: the first not yet Watched, running through
	/// the seasons in order with specials (season 0) saved for last.
	static func nextEpisode(of show: Show) -> Episode? {
		runningOrder(of: show).first { $0.status != .watched }
	}

	/// Every episode in the order it runs: season by season, specials last.
	static func runningOrder(of show: Show) -> [Episode] {
		show.seasons
			.sorted { runOrder($0.seasonNumber) < runOrder($1.seasonNumber) }
			.flatMap(\.sortedEpisodes)
	}

	private static func runOrder(_ seasonNumber: Int) -> Int {
		seasonNumber == 0 ? Int.max : seasonNumber
	}

	/// "Season 2 · Episode 8" — "Specials" standing in for season 0.
	static func episodeLine(_ episode: Episode) -> String {
		let season = episode.seasonNumber == 0 ? "Specials" : "Season \(episode.seasonNumber)"
		return "\(season) · Episode \(episode.episodeNumber)"
	}

	/// The episode line while there's an episode to go; after that, why Mark
	/// Watched now finishes the show instead.
	static func progressLine(for show: Show, next: Episode?) -> String {
		if let next { return episodeLine(next) }
		let count = show.episodeCount
		return count == 0 ? "No episodes tracked" : "All \(count) episodes watched"
	}

	/// What the rating sheet does with a pick: records the rating when one was
	/// chosen — marking watched without one leaves an earlier rating alone —
	/// and marks the episode Watched.
	static func markWatched(_ episode: Episode, tier: EpisodeTier?) {
		if let tier { episode.episodeTier = tier }
		episode.mark(.watched)
	}

	/// Home's Mark Watched. Marks the next episode when there is one. Once
	/// every episode is Watched it marks the show itself — cascading down to
	/// seasons and episodes the way the Show page does, when `cascade` (the
	/// "Mark all episodes watched" setting) is on. Returns the episode marked.
	@discardableResult
	static func markNextWatched(in show: Show, cascade: Bool) -> Episode? {
		if let episode = nextEpisode(of: show) {
			episode.mark(.watched)
			return episode
		}
		show.mark(.watched)
		if cascade {
			for season in show.seasons {
				season.status = .watched
				for episode in season.episodes { episode.mark(.watched) }
			}
		}
		return nil
	}

	/// The hero's artwork, best first, for the design's wide frame: the landscape
	/// picture chosen by hand when there is one (`chosenByHand`), then a textless
	/// backdrop (no printed title under the one Home draws), then a textless
	/// poster, then whatever backdrop or poster the show was saved with.
	static func heroArtURL(for show: Show, gallery: ImageGallery?, chosenByHand: Bool = false) -> String {
		if chosenByHand, !show.backdropURL.isEmpty {
			return show.backdropURL.replacingOccurrences(of: "/t/p/w780/", with: "/t/p/w1280/")
		}
		if let gallery {
			if let backdrop = textless(.backdrop, in: gallery) {
				// A 1080p original reads sharp at hero size; bigger originals run
				// to megabytes, so those come down at 1280.
				let size = (1...1920).contains(backdrop.width) ? "original" : "w1280"
				return "\(TMDbConfig.imageBase)/\(size)\(backdrop.id)"
			}
			if let poster = textless(.poster, in: gallery) {
				return "\(TMDbConfig.imageBase)/w780\(poster.id)"
			}
		}
		// What the show was saved with is sized for detail headers and grid cards,
		// so ask for the next size up. Posters picked from Photos are file URLs
		// and pass through untouched.
		if !show.backdropURL.isEmpty {
			return show.backdropURL.replacingOccurrences(of: "/t/p/w780/", with: "/t/p/w1280/")
		}
		return show.posterURL.replacingOccurrences(of: "/t/p/w500/", with: "/t/p/w780/")
	}

	/// Galleries arrive best-rated first, so the first untagged entry wins.
	private static func textless(_ kind: ImageEntry.Kind, in gallery: ImageGallery) -> ImageEntry? {
		gallery.groups.first { $0.kind == kind }?.entries.first { $0.language == nil }
	}

	// MARK: To Watch

	/// Shows and films still To Watch, newest added first — leaving out any
	/// already rated Skip, since those aren't worth suggesting.
	static func toWatch(shows: [Show], films: [Film]) -> [WatchedTitle] {
		let titles = shows.filter { $0.status == .toWatch && $0.rating != .skip }.map(WatchedTitle.show)
			+ films.filter { $0.status == .toWatch && $0.rating != .skip }.map(WatchedTitle.film)
		return titles.sorted { $0.dateAdded > $1.dateAdded }
	}

	// MARK: Recently watched

	/// Shows and films marked Watched, most recently marked first. Titles with
	/// no recorded date — Watched before dates were kept — follow, newest-added
	/// first.
	static func recentlyWatched(shows: [Show], films: [Film]) -> [WatchedTitle] {
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
