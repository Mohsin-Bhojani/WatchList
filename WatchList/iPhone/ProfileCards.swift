//
//  ProfileCards.swift
//  WatchList
//
//  The Profile screen's verdict summary and its shelf of posters.
//  Split out of ProfileView.swift.
//

import SwiftUI
import SwiftData

// MARK: - Verdicts

/// Your verdicts added up: a bar split by how many titles have each, and the
/// counts under it. The profile makes it the way into Stats.
struct VerdictSummaryCard: View {
	let counts: [ProfileFeed.VerdictCount]

	var body: some View {
		let total = counts.reduce(0) { $0 + $1.count }
		VStack(alignment: .leading, spacing: 12) {
			HStack(alignment: .firstTextBaseline) {
				Text("Your verdicts")
					.font(.system(size: 15, weight: .semibold))
				Spacer()
				HStack(spacing: 6) {
					Text(total == 0 ? "None yet" : "\(total) rated")
					// It opens Stats.
					Image(systemName: "chevron.right")
						.font(.system(size: 12, weight: .bold))
				}
				.font(.system(size: 13, weight: .medium))
				.foregroundStyle(.white.opacity(0.6))
			}
			if total > 0 { bar(total: total) }
			LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible())],
			          alignment: .leading, spacing: 8) {
				ForEach(counts) { item in
					HStack(spacing: 8) {
						Circle()
							.fill(Glass.tint(item.rating))
							.frame(width: 8, height: 8)
						Text(item.rating.rawValue)
							.font(.system(size: 13, weight: .medium))
							.foregroundStyle(.white.opacity(0.85))
						Spacer(minLength: 4)
						Text("\(item.count)")
							.font(.system(size: 13, weight: .bold))
							.monospacedDigit()
					}
					.accessibilityElement(children: .combine)
				}
			}
		}
		.padding(16)
		.liquidCard(cornerRadius: 20)
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
					.font(.system(size: 12, weight: .semibold))
					.lineLimit(1)
				if let stars = item.stars {
					HStack(spacing: 3) {
						Image(systemName: "star.fill")
							.font(.system(size: 9))
							.foregroundStyle(StarRatingPicker.gold)
						Text(StarRating.label(stars))
					}
					.font(.system(size: 11, weight: .semibold))
					.foregroundStyle(.white.opacity(0.7))
				} else {
					Text(item.kindLabel)
						.font(.system(size: 11, weight: .semibold))
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
					.font(.system(size: 18, weight: .semibold))
					.foregroundStyle(.white.opacity(0.7))
			}
			.contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
			.accessibilityElement(children: .ignore)
			.accessibilityLabel("Add to Top 4")
	}
}
