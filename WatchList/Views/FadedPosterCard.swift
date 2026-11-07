//
//  FadedPosterCard.swift
//  WatchList
//
//  The Shows tab's grid card and Home's Recently watched card, after design B
//  of the alternatives: the whole poster, clean, with the verdict as a seal in
//  its corner (none while unrated), and the title and where it's up to under
//  it on the page — the status a coloured dot beside its name in ink, so it
//  reads in light and dark alike.
//

import SwiftUI
import WatchListCore
import WatchListLibrary

struct FadedPosterCard: View {
	let item: WatchedTitle

	/// "Watching · S2 E2" for a show under way; otherwise the kind and size.
	private var detail: String {
		if case .show(let show) = item, show.status == .watching, let next = HomeFeed.nextEpisode(of: show) {
			return ShowFacts.code(next)
		}
		return item.cardSubtitle
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			PosterImage(urlString: item.posterURL, systemPlaceholder: item.placeholder)
				.aspectRatio(2.0 / 3.0, contentMode: .fit)
				.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
				.overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
				.overlay(alignment: .bottomTrailing) {
					if let rating = item.rating { VerdictSeal(rating: rating).padding(8) }
				}
				.shadow(color: .black.opacity(0.18), radius: 10, y: 6)

			VStack(alignment: .leading, spacing: 3) {
				Text(item.title)
					.font(.system(size: 15, weight: .bold, design: .serif))
					.foregroundStyle(Glass.ink)
					.lineLimit(1)
				HStack(spacing: 5) {
					Circle().fill(Glass.tint(item.status)).frame(width: 7, height: 7)
					Text([item.status.rawValue, detail].filter { !$0.isEmpty }.joined(separator: " · "))
						.font(.system(size: 12, weight: .medium, design: .rounded))
						.foregroundStyle(Glass.ink.opacity(0.68))
						.lineLimit(1)
				}
			}
			.padding(.horizontal, 2)
		}
		.accessibilityElement(children: .combine)
	}
}

/// A verdict as a seal: its colour, its symbol in near-black on it, ringed in
/// the ground so it stands off any poster.
struct VerdictSeal: View {
	let rating: Rating
	var size: CGFloat = 36

	var body: some View {
		Image(systemName: rating.systemImage)
			.font(.system(size: size * 0.42, weight: .bold))
			.foregroundStyle(Color(red: 0.04, green: 0.05, blue: 0.07))
			.frame(width: size, height: size)
			.background(Glass.tint(rating), in: Circle())
			.overlay(Circle().strokeBorder(.black.opacity(0.45), lineWidth: 3))
			.accessibilityLabel(rating.rawValue)
	}
}
