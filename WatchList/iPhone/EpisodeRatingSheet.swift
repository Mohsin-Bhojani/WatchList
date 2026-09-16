//
//  EpisodeRatingSheet.swift
//  WatchList
//
//  What Home's Mark Watched opens for the episode a show is up to: its still,
//  the season and episode, the show, the synopsis, and the three episode
//  ratings. Picking one records it and marks the episode Watched in the same
//  tap; swiping the sheet away changes nothing.
//

import SwiftUI

struct EpisodeRatingSheet: View {
	let episode: Episode

	@Environment(\.dismiss) private var dismiss

	private var show: Show? { episode.season?.show }

	/// The still, asked for larger than the list thumbnail it was saved as, or
	/// the show's backdrop when the episode has none.
	private var stillURL: String {
		if !episode.stillURL.isEmpty {
			return episode.stillURL.replacingOccurrences(of: "/t/p/w300/", with: "/t/p/w780/")
		}
		return show?.backdropURL ?? ""
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				PosterImage(urlString: stillURL, systemPlaceholder: "film")
					.aspectRatio(16 / 9, contentMode: .fit)
					.frame(maxWidth: .infinity)
					.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
					.accessibilityHidden(true)

				// The same order as the hero: where you are, then whose it is.
				VStack(alignment: .leading, spacing: 4) {
					Text(HomeFeed.episodeLine(episode))
						.font(.system(size: 14, weight: .semibold))
						.foregroundStyle(Glass.accent)
					if let show {
						Text(show.title)
							.font(.system(size: 24, weight: .bold))
							.fixedSize(horizontal: false, vertical: true)
					}
					if !episode.title.isEmpty {
						Text(episode.title)
							.font(.system(size: 17, weight: .medium))
							.foregroundStyle(.secondary)
							.fixedSize(horizontal: false, vertical: true)
					}
				}

				if !episode.synopsis.isEmpty {
					Text(episode.synopsis)
						.font(.system(size: 15))
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				}

				VStack(alignment: .leading, spacing: 10) {
					Text("Rate this episode")
						.font(.system(size: 17, weight: .semibold))
					HStack(spacing: 10) {
						ForEach(EpisodeTier.allCases) { tierButton($0) }
					}
					Button { rate(nil) } label: {
						Text("Mark Watched Without Rating")
							.font(.system(size: 14, weight: .medium))
							.foregroundStyle(.secondary)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 8)
					}
					.buttonStyle(.plain)
				}
				.padding(.top, 4)
			}
			.padding(.horizontal, 20)
			// Clear of the drag indicator, now there's no bar above.
			.padding(.top, 28)
			.padding(.bottom, 20)
		}
		.presentationDetents([.fraction(0.85), .large])
		.presentationDragIndicator(.visible)
	}

	private func tierButton(_ tier: EpisodeTier) -> some View {
		let current = episode.episodeTier == tier
		let tint = Glass.tint(tier)
		let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
		return Button { rate(tier) } label: {
			VStack(spacing: 5) {
				Image(systemName: tier.systemImage)
					.font(.system(size: 20, weight: .semibold))
				Text(tier.rawValue)
					.font(.system(size: 15, weight: .semibold))
			}
			.foregroundStyle(tint)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 12)
			.background(shape.fill(tint.opacity(current ? 0.26 : 0.13)))
			.overlay(shape.strokeBorder(tint.opacity(current ? 0.9 : 0.3), lineWidth: current ? 2 : 1))
		}
		.buttonStyle(.pressable)
		.accessibilityLabel(tier.rawValue)
		.accessibilityAddTraits(current ? .isSelected : [])
	}

	private func rate(_ tier: EpisodeTier?) {
		withAnimation(Glass.smooth) {
			HomeFeed.markWatched(episode, tier: tier)
		}
		Haptics.success()
		dismiss()
	}
}
