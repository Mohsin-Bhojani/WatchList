//
//  EpisodeRatingView.swift
//  WatchList Watch App
//
//  What Mark Watched opens: the episode, and its three ratings — Skip, Watch,
//  Rewatch, as the iPhone's rating sheet offers them. Picking one marks the
//  episode watched with that rating; Watched Without Rating marks it and keeps
//  whatever rating it had.
//

import SwiftUI
import WatchKit

struct EpisodeRatingView: View {
	let showTitle: String
	let episode: UpNextEpisode
	let onRate: (EpisodeTier?) -> Void

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 8) {
					VStack(alignment: .leading, spacing: 1) {
						Text(episode.code)
							.font(.footnote.weight(.semibold))
							.foregroundStyle(.tint)
						Text(showTitle)
							.font(.headline)
							.lineLimit(2)
						if !episode.title.isEmpty {
							Text(episode.title)
								.font(.footnote)
								.foregroundStyle(.secondary)
								.lineLimit(2)
						}
					}

					HStack(spacing: 4) {
						ForEach(EpisodeTier.allCases) { tier in
							tierButton(tier)
						}
					}

					Button { onRate(nil) } label: {
						Text("Watched Without Rating")
							.font(.footnote)
							.multilineTextAlignment(.center)
							.frame(maxWidth: .infinity)
					}
				}
			}
			.navigationTitle("Rate")
			.navigationBarTitleDisplayMode(.inline)
		}
	}

	private func tierButton(_ tier: EpisodeTier) -> some View {
		let tint = WatchColors.tint(tier)
		let current = episode.tier == tier
		return Button { onRate(tier) } label: {
			VStack(spacing: 3) {
				Image(systemName: tier.systemImage)
					.font(.body.weight(.semibold))
				Text(tier.rawValue)
					.font(.caption2.weight(.semibold))
					.lineLimit(1)
					.minimumScaleFactor(0.7)
			}
			.foregroundStyle(.white)
			.frame(maxWidth: .infinity, minHeight: 58)
			.background(tint.opacity(current ? 0.75 : 0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			.overlay {
				if current {
					RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 1.5)
				}
			}
		}
		.buttonStyle(.plain)
		.accessibilityLabel(tier.rawValue)
		.accessibilityAddTraits(current ? .isSelected : [])
	}
}

/// The iPhone's colours as the watch uses them, from Shared/SharedColors.xcassets.
enum WatchColors {
	static func tint(_ tier: EpisodeTier) -> Color {
		switch tier {
		case .skip:    return Color(.tierSkip)
		case .watch:   return Color(.tierWatch)
		case .rewatch: return Color(.tierRewatch)
		}
	}

	static let starGold = Color(.starGold)
}

/// The watch's haptics, by what they mean.
enum Haptics {
	static func success() { WKInterfaceDevice.current().play(.success) }
	static func click() { WKInterfaceDevice.current().play(.click) }
}
