//
//  EpisodeRatingSheet.swift
//  WatchList
//
//  What Home's Mark Watched opens for the episode a show is up to, after design
//  B of the alternatives — mark first, rate if you like: the still at its own
//  16:9 across the sheet, the episode and the show, Mark Watched, then an
//  optional rating to go with it and the episode after this one. The sheet is
//  as tall as it needs, never narrower. Swiping it away changes nothing.
//

import SwiftUI
import WatchListCore
import WatchListLibrary

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

	/// The rating to record with the mark; starts as the episode's own, or
	/// Watch when it has none — the one most episodes get.
	@State private var picked: EpisodeTier?
	@State private var pickedLoaded = false

	/// The episode after this one still to watch, for the line at the foot.
	private var upNext: Episode? {
		guard let show else { return nil }
		let order = HomeFeed.runningOrder(of: show)
		guard let index = order.firstIndex(where: { $0.id == episode.id }) else { return nil }
		return order[(index + 1)...].first { $0.status != .watched }
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				// Its own shape, the full width: taller rather than cropped.
				PosterImage(urlString: stillURL, systemPlaceholder: "film")
					.aspectRatio(16 / 9, contentMode: .fit)
					.frame(maxWidth: .infinity)
					.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
					.overlay(alignment: .bottomLeading) {
						Text(ShowFacts.code(episode))
							.font(.system(.caption, weight: .bold))
							.foregroundStyle(.white)
							.padding(.horizontal, 10)
							.padding(.vertical, 5)
							.background(.black.opacity(0.5), in: Capsule())
							.padding(10)
					}
					.accessibilityHidden(true)

				VStack(alignment: .leading, spacing: 4) {
					if let show {
						Text(show.title)
							.font(.system(.subheadline, weight: .semibold))
							.foregroundStyle(.secondary)
					}
					Text(episode.displayTitle)
						.font(.system(.title2, weight: .bold))
						.fixedSize(horizontal: false, vertical: true)
					Text(HomeFeed.episodeLine(episode))
						.font(.system(.footnote, weight: .medium))
						.foregroundStyle(.secondary)
				}

				if !episode.synopsis.isEmpty {
					Text(episode.synopsis)
						.font(.subheadline)
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				}

				Button { rate(picked) } label: {
					Label("Mark Watched", systemImage: "checkmark")
						.font(.system(.body, weight: .semibold))
						.foregroundStyle(Color(.systemBackground))
						.frame(maxWidth: .infinity, minHeight: 50)
						.background(Glass.ink, in: Capsule())
				}
				.buttonStyle(.pressable)

				HStack {
					Text("Rate it, optional")
						.font(.system(.subheadline, weight: .medium))
						.foregroundStyle(.secondary)
					Spacer()
					HStack(spacing: 2) {
						ForEach(EpisodeTier.allCases) { tierButton($0) }
					}
					.padding(3)
					.glassEffect(.regular, in: Capsule())
				}

				if let upNext {
					Divider()
					HStack(spacing: 10) {
						Text("Up next")
							.font(.system(.footnote, weight: .medium))
							.foregroundStyle(.secondary)
						Text([ShowFacts.code(upNext), ShowFacts.distinctName(upNext)].compactMap { $0 }.joined(separator: " · "))
							.font(.subheadline)
							.lineLimit(1)
						Spacer(minLength: 0)
						if let minutes = upNext.runtimeMinutes ?? upNext.specs?.runtimeMinutes {
							Text("\(minutes) min")
								.font(.system(.footnote, weight: .medium))
								.foregroundStyle(.secondary)
						}
					}
				}
			}
			.padding(.horizontal, 20)
			// Clear of the drag indicator, now there's no bar above.
			.padding(.top, 28)
			.padding(.bottom, 20)
		}
		.presentationDetents([.large])
		.presentationDragIndicator(.visible)
		.onAppear {
			guard !pickedLoaded else { return }
			picked = episode.episodeTier ?? .watch
			pickedLoaded = true
		}
	}

	/// One of the three ratings in the optional row; tapped again, unpicked.
	private func tierButton(_ tier: EpisodeTier) -> some View {
		let current = picked == tier
		return Button {
			Haptics.selection()
			withAnimation(Glass.pop) { picked = current ? nil : tier }
		} label: {
			Text(tier.rawValue)
				.font(.system(.footnote, weight: .semibold))
				.foregroundStyle(current ? Glass.onTint : Glass.ink)
				.padding(.horizontal, 12)
				.frame(minHeight: 32)
				.background(current ? Glass.tint(tier) : .clear, in: Capsule())
				.contentShape(Capsule())
		}
		.buttonStyle(.plain)
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
