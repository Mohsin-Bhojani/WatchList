//
//  ScreenHeader.swift
//  WatchList
//
//  The header the tabs share, after Home's design: the screen's name large on
//  the left and the profile button on the right, which opens the profile.
//    - iPhone: ScreenHeader, at the top of the page, with the navigation bar
//      hidden
//    - iPad: .screenBar, either side of the floating tab bar in the row it
//      sits in — the navigation bar, which also holds Search's field — so
//      ScreenHeader draws nothing there
//

import SwiftUI
import WatchListCore
import WatchListLibrary

struct ScreenHeader: View {
	/// Keyed on the device, like the app's shell: an iPad's tab bar floats at
	/// the top, with room either side of it.
	static let isInBar = UIDevice.current.userInterfaceIdiom == .pad

	let title: String
	/// White with a soft shadow over a colour band (Home's hero); ink on paper.
	var onBand = false
	/// Space above the row. Home's scroll view runs up under the status bar, so
	/// it passes the status bar's height; screens that keep the safe area don't.
	var topPadding: CGFloat = 0
	/// A live line under the name — "568 titles · 4 watching" — when the screen
	/// has one.
	var subtitle: String? = nil

	@State private var showingProfile = false
	@ObservedObject private var profile = ProfileStore.shared

	private var ink: Color { onBand ? .white : Glass.ink }

	var body: some View {
		if !Self.isInBar { header }
	}

	private var header: some View {
		HStack(alignment: .top) {
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(.system(size: 34, weight: .bold))
					.foregroundStyle(ink)
					.accessibilityAddTraits(.isHeader)
				if let subtitle {
					Text(subtitle)
						.font(.system(size: 13, weight: .medium))
						.foregroundStyle(ink.opacity(0.7))
						.lineLimit(1)
				}
			}
			.shadow(color: .black.opacity(onBand ? 0.25 : 0), radius: 6, y: 1)
			.allowsHitTesting(false)
			Spacer()
			// Your picture, or your initial, ringed so it reads on any ground.
			Button { showingProfile = true } label: {
				ProfileAvatar(nickname: profile.nickname, image: profile.avatar, size: 40)
					.frame(width: GlassControl.height, height: GlassControl.height)
					.contentShape(Circle())
			}
			.buttonStyle(.plain)
			.padding(.top, 2)
			.accessibilityLabel(profile.nickname.isEmpty ? "Profile" : "Profile, \(profile.nickname)")
		}
		.padding(.horizontal, 20)
		.padding(.top, topPadding)
		.sheet(isPresented: $showingProfile) { ProfileView() }
	}
}

extension View {
	/// A tab's name and profile button in the navigation bar on an iPad, beside
	/// the floating tab bar; on an iPhone the bar stays hidden and ScreenHeader
	/// shows them on the page. `onBand` as ScreenHeader's.
	func screenBar(_ title: String, onBand: Bool = false) -> some View {
		modifier(ScreenBar(title: title, onBand: onBand))
	}
}

private struct ScreenBar: ViewModifier {
	let title: String
	let onBand: Bool

	@State private var showingProfile = false

	private static let titleFont = UIFont.systemFont(ofSize: 28, weight: .bold)
	/// About what's left beside the floating tab bar on an 11-inch iPad upright.
	private static let maxTitleWidth: CGFloat = 116

	private var ink: Color { onBand ? .white : Glass.ink }

	private var titleWidth: CGFloat {
		let width = (title as NSString).size(withAttributes: [.font: Self.titleFont]).width
		return min(ceil(width) + 2, Self.maxTitleWidth)
	}

	func body(content: Content) -> some View {
		if ScreenHeader.isInBar {
			content
				// The name has its own place on the leading side; the title stays
				// set only to name the back button on pages pushed from here, and
				// is never drawn large under the bar either.
				.navigationBarTitleDisplayMode(.inline)
				.toolbar(removing: .title)
				.toolbar {
					ToolbarItem(placement: .topBarLeading) {
						// A set width, measured: left to size itself the bar squeezes it
						// to a few letters, or moves a long name like Collections into its
						// overflow menu. Past the room beside the tab bar, it shrinks.
						Text(title)
							.font(Font(Self.titleFont))
							.foregroundStyle(ink)
							.shadow(color: .black.opacity(onBand ? 0.25 : 0), radius: 6, y: 1)
							.lineLimit(1)
							.minimumScaleFactor(0.7)
							.frame(width: titleWidth, alignment: .leading)
							.accessibilityAddTraits(.isHeader)
					}
					.sharedBackgroundVisibility(.hidden)
					ToolbarItem(placement: .topBarTrailing) {
						Button { showingProfile = true } label: {
							Image(systemName: "person.crop.circle")
								.font(.system(size: 20, weight: .medium))
						}
						.tint(ink)
						.accessibilityLabel("Profile")
					}
				}
				.sheet(isPresented: $showingProfile) { ProfileView() }
		} else {
			content.toolbar(.hidden, for: .navigationBar)
		}
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
