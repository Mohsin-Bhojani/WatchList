//
//  TitlePageControls.swift
//  WatchList
//
//  The title pages' status switch, verdict and tier chips, and the labels
//  and compact title they share. Split out of TitlePageKit.swift.
//

import SwiftUI
import SwiftData
import WatchListCore
import WatchListLibrary

// MARK: - Status switch

struct PageSwitchOption: Identifiable {
	let title: String
	var systemImage: String? = nil
	let selected: Bool
	let fill: Color
	let action: () -> Void

	var id: String { title }
}

/// The design's To watch / Watched switch; a show in progress adds a third,
/// Watching side.
struct PageSwitch: View {
	let options: [PageSwitchOption]
	/// The chosen side's text: the page's deep shade.
	let selectedText: Color

	var body: some View {
		HStack(spacing: 4) {
			ForEach(options) { option in
				Button {
					Haptics.selection()
					option.action()
				} label: {
					HStack(spacing: 5) {
						if let systemImage = option.systemImage {
							Image(systemName: systemImage)
								.font(.system(size: 11, weight: .bold))
						}
						Text(option.title)
							.font(.system(size: 14, weight: .semibold))
							.lineLimit(1)
					}
					.foregroundStyle(option.selected ? selectedText : .white.opacity(0.75))
					.padding(.horizontal, 16)
					// Inside the switch's 4pt rim, so the whole switch is a glass control's height.
					.frame(height: GlassControl.height - 8)
					.background {
						if option.selected { Capsule().fill(option.fill) }
					}
					.contentShape(Capsule())
				}
				.buttonStyle(.plain)
				.accessibilityAddTraits(option.selected ? .isSelected : [])
			}
		}
		.padding(4)
		.glassEffect(.regular.tint(.white.opacity(0.06)), in: Capsule())
	}
}

// MARK: - Chips and labels

/// A verdict as a small capsule with its colour dot; "Rate" when there's none.
struct VerdictChip: View {
	let rating: Rating?
	var emptyLabel = "Not rated"

	var body: some View {
		HStack(spacing: 5) {
			if let rating {
				Circle()
					.fill(Glass.tint(rating))
					.frame(width: 7, height: 7)
			}
			Text(rating?.rawValue ?? emptyLabel)
				.font(.system(size: 12, weight: .semibold))
				.lineLimit(1)
		}
		.foregroundStyle(.white.opacity(rating == nil ? 0.75 : 1))
		.padding(.horizontal, 9)
		.padding(.vertical, 5)
		.background(.white.opacity(rating == nil ? 0.1 : 0.12), in: Capsule())
	}
}

/// An episode's rating as a small capsule; "Rate" when there's none.
struct TierChip: View {
	let tier: EpisodeTier?

	var body: some View {
		HStack(spacing: 4) {
			if let tier {
				Image(systemName: tier.systemImage)
					.font(.system(size: 9, weight: .bold))
					.foregroundStyle(Glass.tint(tier))
			}
			Text(tier?.rawValue ?? "Rate")
				.font(.system(size: 11, weight: .semibold))
		}
		.foregroundStyle(.white.opacity(tier == nil ? 0.7 : 1))
		.padding(.horizontal, 8)
		.padding(.vertical, 4)
		.background(.white.opacity(tier == nil ? 0.08 : 0.14), in: Capsule())
	}
}

/// The status menu's label: the verdict once rated and watched, otherwise the
/// status.
struct PageStatusLabel: View {
	let status: WatchStatus
	let rating: Rating?

	var body: some View {
		HStack(spacing: 6) {
			if status == .watched, let rating {
				Circle()
					.fill(Glass.tint(rating))
					.frame(width: 8, height: 8)
				Text(rating.rawValue)
			} else {
				Image(systemName: status.systemImage)
					.font(.system(size: 12, weight: .semibold))
				Text(status.rawValue)
			}
			Image(systemName: "chevron.down")
				.font(.system(size: 11, weight: .bold))
		}
		.font(.system(size: 14, weight: .semibold))
		.foregroundStyle(.white)
	}
}

/// The compact bar's poster, title and one line under it.
struct PageCompactTitle: View {
	let posterURL: String
	let placeholder: String
	let title: String
	let subtitle: String

	var body: some View {
		HStack(spacing: 8) {
			PosterImage(urlString: posterURL, systemPlaceholder: placeholder)
				.frame(width: 24, height: 36)
				.clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
			VStack(alignment: .leading, spacing: 0) {
				Text(title)
					.font(.system(size: 14, weight: .bold))
					.lineLimit(1)
				Text(subtitle)
					.font(.system(size: 11, weight: .medium))
					.foregroundStyle(.white.opacity(0.65))
					.lineLimit(1)
			}
		}
		.foregroundStyle(.white)
	}
}

/// TMDb's stars out of ten as five, with the rest of the meta line after them.
struct PageMetaLine: View {
	let voteAverage: Double?
	let parts: [String]

	var body: some View {
		let average = voteAverage ?? 0
		HStack(spacing: 6) {
			if average > 0 {
				HStack(spacing: 1) {
					ForEach(Array(FilmFacts.stars(outOf10: average).enumerated()), id: \.offset) { _, star in
						Image(systemName: StarRatingPicker.symbol(star))
					}
				}
				.font(.system(size: 10))
				.accessibilityElement(children: .ignore)
				.accessibilityLabel(String(format: "TMDb rating %.1f out of 10", average))
			}
			if !parts.isEmpty {
				Text(parts.joined(separator: " · "))
			}
		}
		.font(.system(size: 13, weight: .medium))
		.foregroundStyle(.white.opacity(0.75))
		.multilineTextAlignment(.center)
	}
}
