//
//  StarRatingViews.swift
//  WatchList
//
//  The half-star scale on screen: a picker you tap or drag across, and a small
//  read-only row for showing a rating.
//

import SwiftUI

/// Five stars, set by tapping or dragging across them: a star's left half gives
/// its half, its right half the whole star, and just left of the first star, 0.
struct StarRatingPicker: View {
	let value: Double?
	let onChange: (Double) -> Void
	var size: CGFloat = 28
	var spacing: CGFloat = 6

	static let gold = Color(hex: "#F5C451")

	/// Touchable room left of the first star, where the rating is 0.
	private static let zeroRoom: CGFloat = 14

	/// The rating at `x` points from the first star's leading edge.
	static func value(atX x: CGFloat, size: CGFloat, spacing: CGFloat) -> Double {
		guard x > 0 else { return 0 }
		let pitch = size + spacing
		let star = min(Int(x / pitch), 4)
		// The gap after a star counts as that star's right half.
		let into = x - CGFloat(star) * pitch
		return Double(star) + (into <= size / 2 ? 0.5 : 1)
	}

	static func symbol(_ star: FilmFacts.Star) -> String {
		switch star {
		case .full:  return "star.fill"
		case .half:  return "star.leadinghalf.filled"
		case .empty: return "star"
		}
	}

	var body: some View {
		HStack(spacing: spacing) {
			// A 0–5 rating is a 0–10 one in halves.
			ForEach(Array(FilmFacts.stars(outOf10: (value ?? 0) * 2).enumerated()), id: \.offset) { _, star in
				Image(systemName: Self.symbol(star))
					.font(.system(size: size))
					.frame(width: size, height: size)
					.foregroundStyle(value == nil ? Color.white.opacity(0.35) : Self.gold)
			}
		}
		.padding(.leading, Self.zeroRoom)
		.contentShape(Rectangle())
		.gesture(DragGesture(minimumDistance: 0).onChanged { drag in
			let picked = Self.value(atX: drag.location.x - Self.zeroRoom, size: size, spacing: spacing)
			if picked != value {
				Haptics.selection()
				onChange(picked)
			}
		})
		// The room for 0 reaches out past the stars rather than pushing them over.
		.padding(.leading, -Self.zeroRoom)
		.accessibilityElement()
		.accessibilityLabel("Stars")
		.accessibilityValue(value.map { "\(StarRating.label($0)) of 5" } ?? "Not rated")
		.accessibilityAdjustableAction { direction in
			let current = value ?? 0
			switch direction {
			case .increment: onChange(StarRating.snapped(current + 0.5))
			case .decrement: onChange(StarRating.snapped(current - 0.5))
			@unknown default: break
			}
		}
	}
}

/// A rating's stars at a glance, with the number beside them unless it's left
/// off.
struct StarsLabel: View {
	let value: Double
	var size: CGFloat = 11
	var showsValue = true

	var body: some View {
		HStack(spacing: 4) {
			HStack(spacing: 1) {
				ForEach(Array(FilmFacts.stars(outOf10: value * 2).enumerated()), id: \.offset) { _, star in
					Image(systemName: StarRatingPicker.symbol(star))
				}
			}
			.foregroundStyle(StarRatingPicker.gold)
			if showsValue {
				Text(StarRating.label(value))
					.foregroundStyle(.white.opacity(0.8))
			}
		}
		.font(.system(size: size, weight: .semibold))
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("\(StarRating.label(value)) of 5 stars")
	}
}
