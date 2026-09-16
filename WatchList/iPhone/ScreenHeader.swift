//
//  ScreenHeader.swift
//  WatchList
//
//  The header iPhone tabs share, after Home's design: the screen's name large
//  on the left and the profile button on the right, which opens the profile.
//

import SwiftUI

struct ScreenHeader: View {
	let title: String
	/// White with a soft shadow over a colour band (Home's hero); ink on paper.
	var onBand = false
	/// Space above the row. Home's scroll view runs up under the status bar, so
	/// it passes the status bar's height; screens that keep the safe area don't.
	var topPadding: CGFloat = 0

	@State private var showingProfile = false

	private var ink: Color { onBand ? .white : Glass.ink }

	var body: some View {
		HStack {
			Text(title)
				.font(.system(size: 34, weight: .bold))
				.foregroundStyle(ink)
				.shadow(color: .black.opacity(onBand ? 0.25 : 0), radius: 6, y: 1)
				.accessibilityAddTraits(.isHeader)
				.allowsHitTesting(false)
			Spacer()
			// Glass, so over a band it takes on the colour behind it.
			Button { showingProfile = true } label: {
				Image(systemName: "person.crop.circle")
					.font(.system(size: 22, weight: .medium))
					.foregroundStyle(ink)
					.frame(width: GlassControl.height, height: GlassControl.height)
					.contentShape(Circle())
			}
			.buttonStyle(.plain)
			.glassEffect(.regular.interactive(), in: Circle())
			.accessibilityLabel("Profile")
		}
		.padding(.horizontal, 20)
		.padding(.top, topPadding)
		.sheet(isPresented: $showingProfile) { ProfileView() }
	}
}

/// A sheet's name — Settings, Stats — set the way the tabs set theirs: large
/// and bold on the leading edge at the top, scrolling with the page.
struct SheetTitle: View {
	let text: String

	init(_ text: String) { self.text = text }

	var body: some View {
		Text(text)
			.font(.system(size: 34, weight: .bold))
			.foregroundStyle(Glass.ink)
			.frame(maxWidth: .infinity, alignment: .leading)
			// With the sheets' 18pt margin, this lands on the tabs' 20.
			.padding(.leading, 2)
			.accessibilityAddTraits(.isHeader)
	}
}
