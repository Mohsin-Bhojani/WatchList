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
//      To Watch to Watching
//    - verdict dates: stamped when a verdict is given or changed, forgotten
//      when it's cleared — Discover starts from the most recently rated
//    - hand-picked stars: kept only while they fit the verdict (StarRating)
//

import Foundation

protocol WatchTracked: AnyObject {
	var status: WatchStatus { get set }
	var watchedAt: Date? { get set }
}

extension WatchTracked {
	/// Sets the status and keeps the watched date in step with it.
	func mark(_ newStatus: WatchStatus, at date: Date = .now) {
		if newStatus != .watched {
			watchedAt = nil
		} else if status != .watched {
			watchedAt = date
		}
		status = newStatus
	}
}

extension Show: WatchTracked {}
extension Film: WatchTracked {}
extension Episode: WatchTracked {}

extension Episode {
	/// Marks it Watched and starts its season and show: either one still To
	/// Watch becomes Watching. One already Watching or Watched is left alone.
	func markWatched(at date: Date = .now) {
		mark(.watched, at: date)
		if let season, season.status == .toWatch { season.status = .watching }
		if let show = season?.show, show.status == .toWatch { show.mark(.watching, at: date) }
	}
}

protocol Rated: AnyObject {
	var rating: Rating? { get set }
	var stars: Double? { get set }
	var ratedAt: Date? { get set }
}

extension Rated {
	/// The stars to show: picked by hand while they fit the verdict, otherwise
	/// the verdict's own. Nil when it isn't rated.
	var shownStars: Double? { StarRating.shown(explicit: stars, verdict: rating) }

	/// Sets the verdict and stars together, dating the verdict when it changes.
	func rate(_ verdict: Rating?, stars newStars: Double?, at date: Date = .now) {
		if verdict != rating { ratedAt = verdict == nil ? nil : date }
		rating = verdict
		stars = newStars
	}

	/// Sets the verdict, keeping hand-picked stars only if they still fit it.
	func setVerdict(_ verdict: Rating?, at date: Date = .now) {
		rate(verdict, stars: StarRating.explicit(stars, afterChoosing: verdict), at: date)
	}
}

extension Show: Rated {}
extension Season: Rated {}
extension Film: Rated {}
