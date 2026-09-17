//
//  Community.swift
//  WatchList
//
//  Everyone on WatchList: how the people who have rated a title rated it, on
//  that title's own scale — a verdict for shows and films, Skip / Watch /
//  Rewatch for episodes. The design's "62% Go for it" is the headline; the
//  spread underneath it is where every rating sits, with yours marked.
//
//  Where those ratings come from is one seam, `CommunitySource`. Nothing is
//  sent anywhere: the only source today is this device, which knows one
//  person's ratings — yours. A server can be put behind the same seam later
//  without the section changing.
//

import Foundation
import SwiftUI

/// A title, as everyone else would refer to it: by what TMDb calls it, since
/// that's the one id two people's libraries share.
enum CommunityTitle: Hashable {
	case show(tmdbID: Int)
	case film(tmdbID: Int)
	case episode(tmdbID: Int, season: Int, episode: Int)
}

/// Which ratings a title takes: shows and films are given a verdict, episodes
/// a rewatch tier.
enum CommunityScale {
	case verdict
	case tier

	/// The ratings it offers, best first.
	var options: [String] {
		switch self {
		case .verdict: return Rating.allCases.sorted { $0.sortRank < $1.sortRank }.map(\.rawValue)
		case .tier:    return EpisodeTier.allCases.sorted { $0.sortRank < $1.sortRank }.map(\.rawValue)
		}
	}

	/// The colour a rating is drawn in, as the rest of the app draws it.
	func tint(_ option: String) -> Color {
		switch self {
		case .verdict: return Rating(rawValue: option).map(Glass.tint) ?? Glass.accent3
		case .tier:    return EpisodeTier(rawValue: option).map(Glass.tint) ?? Glass.accent3
		}
	}
}

/// How a title was rated, by everyone who has.
struct CommunityOpinion: Equatable {
	let scale: CommunityScale
	/// How many gave each rating, by its name.
	var counts: [String: Int]
	/// Yours, when you've rated it — counted in `counts` like anyone else's.
	var yours: String?

	var total: Int { counts.values.reduce(0, +) }

	/// The ratings in the scale's order, with how many gave each.
	var spread: [(option: String, count: Int)] {
		scale.options.map { ($0, counts[$0] ?? 0) }
	}

	/// The rating most people gave, and how many of them did — the headline's
	/// "62% Go for it". Nil until someone has rated it. A tie goes to the
	/// better rating, which is the order the scale is in.
	var leading: (option: String, share: Double)? {
		guard total > 0 else { return nil }
		// The spread runs best rating first, and only a strictly larger count
		// takes the lead, so a tie goes to the better rating.
		var best: (option: String, count: Int)?
		for entry in spread where entry.count > (best?.count ?? 0) { best = entry }
		guard let best else { return nil }
		return (best.option, Double(best.count) / Double(total))
	}

	/// What share of everyone gave this rating, 0 to 1.
	func share(of option: String) -> Double {
		guard total > 0 else { return 0 }
		return Double(counts[option] ?? 0) / Double(total)
	}

	/// The same opinion with your rating counted in.
	func counting(yours rating: String?) -> CommunityOpinion {
		guard let rating else { return self }
		var counted = self
		counted.counts[rating, default: 0] += 1
		counted.yours = rating
		return counted
	}
}

/// Everyone else's ratings for a title. The app reads the community through
/// this and nothing else, so the day there's a server to ask, only the
/// implementation changes.
protocol CommunitySource: Sendable {
	/// How many people gave each rating, leaving out yours — the section adds
	/// that itself, so a source never has to know who you are.
	func others(for title: CommunityTitle, scale: CommunityScale) async -> [String: Int]
}

/// The only source there is for now: this device, where the one person on
/// WatchList is you. Nothing leaves the phone, and nothing is asked of the
/// network.
struct ThisDeviceCommunity: CommunitySource {
	func others(for title: CommunityTitle, scale: CommunityScale) async -> [String: Int] { [:] }
}

enum Community {
	/// What the pages read. Point this at a server's source to light the
	/// section up for everyone.
	static var source: CommunitySource = ThisDeviceCommunity()

	/// Everyone's ratings for a title, yours included.
	static func opinion(for title: CommunityTitle, scale: CommunityScale, yours: String?) async -> CommunityOpinion {
		let others = await source.others(for: title, scale: scale)
		return CommunityOpinion(scale: scale, counts: others, yours: nil).counting(yours: yours)
	}
}
