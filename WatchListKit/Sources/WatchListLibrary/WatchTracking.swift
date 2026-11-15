//
//  WatchTracking.swift
//  WatchList
//
//  What every title keeps beside its status and verdict, and the rules that
//  keep them in step — all on the models, so they're saved and deleted with
//  the title:
//    - watched dates: stamped when a show, film or episode becomes Watched,
//      kept while it stays Watched, forgotten when it stops being
//    - watching an episode starts its season and show, moving either from
//      To Watch to Watching, and rates it Watch when it has no rating yet
//    - a show or film marked Watched without a verdict gets Go For It
//    - verdict dates: stamped when a verdict is given or changed, forgotten
//      when it's cleared — Discover starts from the most recently rated
//    - hand-picked stars: kept only while they fit the verdict (StarRating)
//

import Foundation
import WatchListCore

public protocol WatchTracked: AnyObject {
	var status: WatchStatus { get set }
	var watchedAt: Date? { get set }
}

extension WatchTracked {
	/// Sets the status and keeps the watched date in step with it. A show or
	/// film marked Watched without a verdict gets Go For It, the one most get;
	/// a verdict already given is kept.
	public func mark(_ newStatus: WatchStatus, at date: Date = .now) {
		if newStatus != .watched {
			watchedAt = nil
		} else if status != .watched {
			watchedAt = date
		}
		status = newStatus
		if newStatus == .watched, let rated = self as? Rated, rated.rating == nil {
			rated.rate(.goForIt, stars: nil, at: date)
		}
	}
}

extension WatchTracked {
	/// Moves the watched date, for something watched before it was marked —
	/// only while it's Watched, and never past `now`.
	public func setWatchedDate(_ date: Date, now: Date = .now) {
		guard status == .watched else { return }
		watchedAt = min(date, now)
	}
}

/// When something was watched, as people say it: today, yesterday, a week or a
/// month back. Anything else is picked on a calendar.
public enum WatchedWhen: CaseIterable, Identifiable, Sendable {
	case today, yesterday, weekAgo, monthAgo

	public var id: Self { self }

	public var title: String {
		switch self {
		case .today:     return "Today"
		case .yesterday: return "Yesterday"
		case .weekAgo:   return "A week ago"
		case .monthAgo:  return "A month ago"
		}
	}

	/// The moment it stands for, at `now`'s time of day.
	public func date(now: Date = .now, calendar: Calendar = .current) -> Date {
		switch self {
		case .today:     return now
		case .yesterday: return calendar.date(byAdding: .day, value: -1, to: now) ?? now
		case .weekAgo:   return calendar.date(byAdding: .day, value: -7, to: now) ?? now
		case .monthAgo:  return calendar.date(byAdding: .month, value: -1, to: now) ?? now
		}
	}

	/// "Watched today", "Watched yesterday", or "Watched 3 Nov" — the year too
	/// when it isn't this one.
	public static func label(for date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
		if calendar.isDate(date, inSameDayAs: now) { return "Watched today" }
		if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
		   calendar.isDate(date, inSameDayAs: yesterday) { return "Watched yesterday" }
		let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
		var style = sameYear ? Date.FormatStyle.dateTime.day().month(.abbreviated)
		                     : Date.FormatStyle.dateTime.day().month(.abbreviated).year()
		style.calendar = calendar
		style.timeZone = calendar.timeZone
		return "Watched \(date.formatted(style))"
	}
}

extension Show: WatchTracked {}
extension Film: WatchTracked {}
extension Episode: WatchTracked {}

extension Episode {
	/// Marks it Watched and starts its season and show: either one still To
	/// Watch becomes Watching. One already Watching or Watched is left alone.
	/// Without a rating, it's rated Watch — the one most episodes get; a rating
	/// already given is kept.
	public func markWatched(at date: Date = .now) {
		mark(.watched, at: date)
		if episodeTier == nil { episodeTier = .watch }
		if let season, season.status == .toWatch { season.status = .watching }
		if let show = season?.show, show.status == .toWatch { show.mark(.watching, at: date) }
	}
}

public enum TitleRatings {
	/// Gives Go For It to every watched show and film without a verdict, for
	/// titles marked before watching one rated it, dated when each was
	/// watched. Returns how many it rated.
	@discardableResult
	public static func rateUnrated(shows: [Show], films: [Film], now: Date = .now) -> Int {
		var rated = 0
		for show in shows where show.status == .watched && show.rating == nil {
			show.rate(.goForIt, stars: nil, at: show.watchedAt ?? now)
			rated += 1
		}
		for film in films where film.status == .watched && film.rating == nil {
			film.rate(.goForIt, stars: nil, at: film.watchedAt ?? now)
			rated += 1
		}
		return rated
	}
}

public enum EpisodeRatings {
	/// Rates Watch every watched episode that has no rating, for episodes
	/// marked before watching one rated it. Returns how many it rated.
	@discardableResult
	public static func rateUnrated(_ episodes: [Episode]) -> Int {
		var rated = 0
		for episode in episodes where episode.status == .watched && episode.episodeTier == nil {
			episode.episodeTier = .watch
			rated += 1
		}
		return rated
	}
}

public protocol Rated: AnyObject {
	var rating: Rating? { get set }
	var stars: Double? { get set }
	var ratedAt: Date? { get set }
}

extension Rated {
	/// The stars to show: picked by hand while they fit the verdict, otherwise
	/// the verdict's own. Nil when it isn't rated.
	public var shownStars: Double? { StarRating.shown(explicit: stars, verdict: rating) }

	/// Sets the verdict and stars together, dating the verdict when it changes.
	public func rate(_ verdict: Rating?, stars newStars: Double?, at date: Date = .now) {
		if verdict != rating { ratedAt = verdict == nil ? nil : date }
		rating = verdict
		stars = newStars
	}

	/// Sets the verdict, keeping hand-picked stars only if they still fit it.
	public func setVerdict(_ verdict: Rating?, at date: Date = .now) {
		rate(verdict, stars: StarRating.explicit(stars, afterChoosing: verdict), at: date)
	}
}

extension Show: Rated {}
extension Season: Rated {}
extension Film: Rated {}
