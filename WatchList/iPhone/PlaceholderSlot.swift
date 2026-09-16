//
//  PlaceholderSlot.swift
//  WatchList
//
//  How the iPhone redesign holds a place for something not built yet: a dashed
//  box for a whole section, a dashed tag for a single value or option.
//

import SwiftUI

/// A dashed box keeping a section's place — Home's reserved slot, the film
/// page's community ratings and trailer.
struct PlaceholderSlot: View {
	var height: CGFloat = 90
	var label = "Placeholder"

	var body: some View {
		Text(label)
			.font(.system(size: 13, weight: .semibold))
			.foregroundStyle(.tertiary)
			.frame(maxWidth: .infinity)
			.frame(height: height)
			.overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
				.strokeBorder(Glass.hairline.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [6, 5])))
			.accessibilityLabel("\(label), not available yet")
	}
}

/// The inline version, for a single value or option that isn't built yet.
struct PlaceholderTag: View {
	var label = "Placeholder"

	var body: some View {
		Text(label)
			.font(.system(size: 11, weight: .semibold))
			.foregroundStyle(.tertiary)
			.lineLimit(1)
			.padding(.horizontal, 9)
			.padding(.vertical, 4)
			.overlay(Capsule().strokeBorder(Glass.hairline.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
			.accessibilityLabel("\(label), not available yet")
	}
}
