//
//  ProfileCards.swift
//  WatchList
//
//  The Profile screen's verdict summary and its shelf of posters.
//  Split out of ProfileView.swift.
//

import SwiftUI
import SwiftData
import WatchListCore
import WatchListLibrary

// MARK: - Verdicts

/// Your verdicts added up: a bar split by how many titles have each, and the
/// counts under it. The profile makes it the way into Stats.
struct VerdictSummaryCard: View {
	let counts: [ProfileFeed.VerdictCount]

	/// After design B of the alternatives: what your verdicts add up to, said
	/// in a sentence; the counts in words under it; the split as a bar; and the
	/// way into Stats.
	var body: some View {
		let total = counts.reduce(0) { $0 + $1.count }
		VStack(alignment: .leading, spacing: 12) {
			Text(Self.sentence(for: counts))
				.font(.system(.title2, design: .serif, weight: .bold))
				.fixedSize(horizontal: false, vertical: true)
			if total > 0 {
				Text(Self.breakdown(for: counts))
					.font(.system(.footnote, weight: .medium))
					.foregroundStyle(.white.opacity(0.75))
					.fixedSize(horizontal: false, vertical: true)
				bar(total: total)
			}
			HStack(spacing: 4) {
				Text(total == 0 ? "Your verdicts" : "See your stats")
				Image(systemName: "chevron.right")
					.font(.system(.caption, weight: .bold))
			}
			.font(.system(.footnote, weight: .semibold))
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(18)
		.liquidCard(cornerRadius: 20)
	}

	/// What the verdicts come to, in a sentence.
	static func sentence(for counts: [ProfileFeed.VerdictCount]) -> String {
		let total = counts.reduce(0) { $0 + $1.count }
		guard total > 0, let top = counts.max(by: { $0.count < $1.count }) else {
			return "Rate what you watch, and your verdicts add up here."
		}
		let liked = counts.filter { $0.rating == .perfection || $0.rating == .goForIt }.reduce(0) { $0 + $1.count }
		if liked == total { return total == 1 ? "You loved the one title you've rated." : "You've loved everything you've rated so far." }
		if top.rating == .skip { return "You're hard to please: most of what you rate, you'd skip." }
		return "Most of what you rate, you call \(top.rating.rawValue)."
	}

	/// "1 Perfection and 1 Go For It, from 2 rated titles."
	static func breakdown(for counts: [ProfileFeed.VerdictCount]) -> String {
		let total = counts.reduce(0) { $0 + $1.count }
		let parts = counts.filter { $0.count > 0 }.map { "\($0.count) \($0.rating.rawValue)" }
		let list = parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + parts.last! : parts.first ?? ""
		return "\(list), from \(total) rated title\(total == 1 ? "" : "s")."
	}

	/// A segment for each verdict given, as wide as its share, 2pt apart.
	private func bar(total: Int) -> some View {
		let given = counts.filter { $0.count > 0 }
		return GeometryReader { proxy in
			let room = proxy.size.width - CGFloat(given.count - 1) * 2
			HStack(spacing: 2) {
				ForEach(given) { item in
					Rectangle()
						.fill(Glass.tint(item.rating))
						.frame(width: room * CGFloat(item.count) / CGFloat(total))
				}
			}
		}
		.frame(height: 10)
		.clipShape(Capsule())
		.accessibilityHidden(true)
	}
}

// MARK: - Shelf poster

/// A poster on the profile's Top 4 shelf, four across: the art, the title and
/// its stars.
struct ShelfPoster: View {
	let item: WatchedTitle

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			PosterImage(urlString: item.posterURL, systemPlaceholder: item.placeholder)
				.aspectRatio(2.0 / 3.0, contentMode: .fit)
				.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
				.shadow(color: .black.opacity(0.35), radius: 8, y: 8)
			VStack(alignment: .leading, spacing: 2) {
				Text(item.title)
					.font(.system(.caption, weight: .semibold))
					.lineLimit(1)
				if let stars = item.stars {
					HStack(spacing: 3) {
						Image(systemName: "star.fill")
							.font(.caption2)
							.foregroundStyle(StarRatingPicker.gold)
						Text(StarRating.label(stars))
					}
					.font(.system(.caption2, weight: .semibold))
					.foregroundStyle(.white.opacity(0.7))
				} else {
					Text(item.kindLabel)
						.font(.system(.caption2, weight: .semibold))
						.foregroundStyle(.white.opacity(0.7))
				}
			}
		}
		.accessibilityElement(children: .combine)
	}
}

/// A free spot on the Top 4 shelf: a dashed poster-sized outline with a plus,
/// which opens Add Titles.
struct ShelfAddSpot: View {
	var body: some View {
		RoundedRectangle(cornerRadius: 10, style: .continuous)
			.strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
			.aspectRatio(2.0 / 3.0, contentMode: .fit)
			.overlay {
				Image(systemName: "plus")
					.font(.system(.body, weight: .semibold))
					.foregroundStyle(.white.opacity(0.7))
			}
			.contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
			.accessibilityElement(children: .ignore)
			.accessibilityLabel("Add to Top 4")
	}
}
