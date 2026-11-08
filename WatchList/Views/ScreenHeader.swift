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

/// Whether a screen gets the wide layout: an iPad at regular width, where the
/// tab bar floats at the top with room either side of it. An iPad in a narrow
/// Split View or Slide Over gets the phone's layout, as its tab bar does.
enum WideLayout {
	static func applies(_ sizeClass: UserInterfaceSizeClass?) -> Bool {
		UIDevice.current.userInterfaceIdiom == .pad && sizeClass == .regular
	}
}

struct ScreenHeader: View {
	@Environment(\.horizontalSizeClass) private var sizeClass
	private var isInBar: Bool { WideLayout.applies(sizeClass) }

	let title: String
	/// White with a soft shadow over a colour band (Home's hero); ink on paper.
	var onBand = false
	/// Space above the row. Home's scroll view runs up under the status bar, so
	/// it passes the status bar's height; screens that keep the safe area don't.
	var topPadding: CGFloat = 0
	/// A live line under the name — "568 titles · 4 watching" — when the screen
	/// has one.
	var subtitle: String? = nil
	/// When given, a Filter & Sort button beside the profile.
	var onFilter: (() -> Void)? = nil

	@State private var showingProfile = false
	@ObservedObject private var profile = ProfileStore.shared

	private var ink: Color { onBand ? .white : Glass.ink }

	var body: some View {
		if !isInBar { header }
	}

	private var header: some View {
		HStack(alignment: .top) {
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(.system(.largeTitle, weight: .bold))
					.foregroundStyle(ink)
					.accessibilityAddTraits(.isHeader)
				if let subtitle {
					Text(subtitle)
						.font(.system(.footnote, weight: .medium))
						.foregroundStyle(ink.opacity(0.7))
						.lineLimit(1)
				}
			}
			.shadow(color: .black.opacity(onBand ? 0.25 : 0), radius: 6, y: 1)
			.allowsHitTesting(false)
			Spacer()
			if let onFilter {
				Button("Filter & Sort", systemImage: "line.3.horizontal.decrease", action: onFilter)
					.labelStyle(.iconOnly)
					.font(.system(.body, weight: .semibold))
					.foregroundStyle(ink)
					.frame(width: GlassControl.height, height: GlassControl.height)
					.glassEffect(.regular.interactive(), in: Circle())
					.padding(.top, 2)
			}
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
	/// A tab's name, subtitle, filter button and profile button.
	///   - iPhone: a system large title and toolbar. Pages that draw their own
	///     header over artwork (Home, Discover) pass `pageHeader` and keep the
	///     bar hidden, with ScreenHeader on the page.
	///   - iPad: the name and buttons either side of the floating tab bar.
	/// `onFilter`, when given, puts a Filter & Sort button in the toolbar.
	func screenBar(_ title: String, subtitle: String? = nil, onBand: Bool = false,
	               pageHeader: Bool = false, onFilter: (() -> Void)? = nil) -> some View {
		modifier(ScreenBar(title: title, subtitle: subtitle, onBand: onBand,
		                   pageHeader: pageHeader, onFilter: onFilter))
	}
}

private struct ScreenBar: ViewModifier {
	let title: String
	let subtitle: String?
	let onBand: Bool
	let pageHeader: Bool
	let onFilter: (() -> Void)?

	@State private var showingProfile = false
	@ObservedObject private var profile = ProfileStore.shared
	@Environment(\.dynamicTypeSize) private var typeSize
	@Environment(\.horizontalSizeClass) private var sizeClass

	private var titleFont: UIFont { .preferred(.title1, weight: .bold, typeSize: typeSize) }
	/// About what's left beside the floating tab bar on an 11-inch iPad upright.
	private static let maxTitleWidth: CGFloat = 116

	private var ink: Color { onBand ? .white : Glass.ink }

	private var titleWidth: CGFloat {
		let width = (title as NSString).size(withAttributes: [.font: titleFont]).width
		return min(ceil(width) + 2, Self.maxTitleWidth)
	}

	func body(content: Content) -> some View {
		if WideLayout.applies(sizeClass) {
			content
				// The name has its own place on the leading side; the title stays
				// set only to name the back button on pages pushed from here, and
				// is never drawn large under the bar either.
				.navigationTitle(title)
				.navigationBarTitleDisplayMode(.inline)
				.toolbar(removing: .title)
				.toolbar {
					ToolbarItem(placement: .topBarLeading) {
						// A set width, measured: left to size itself the bar squeezes it
						// to a few letters, or moves a long name like Collections into its
						// overflow menu. Past the room beside the tab bar, it shrinks.
						Text(title)
							.font(.system(.title, weight: .bold))
							.foregroundStyle(ink)
							.shadow(color: .black.opacity(onBand ? 0.25 : 0), radius: 6, y: 1)
							.lineLimit(1)
							.minimumScaleFactor(0.7)
							.frame(width: titleWidth, alignment: .leading)
							.accessibilityAddTraits(.isHeader)
					}
					.sharedBackgroundVisibility(.hidden)
					trailingItems
				}
				.sheet(isPresented: $showingProfile) { ProfileView() }
		} else if pageHeader {
			content.toolbar(.hidden, for: .navigationBar)
		} else {
			content
				.navigationTitle(title)
				.navigationSubtitle(subtitle ?? "")
				.navigationBarTitleDisplayMode(.large)
				.toolbar { trailingItems }
				.sheet(isPresented: $showingProfile) { ProfileView() }
		}
	}

	@ToolbarContentBuilder private var trailingItems: some ToolbarContent {
		if let onFilter {
			ToolbarItem(placement: .topBarTrailing) {
				Button("Filter & Sort", systemImage: "line.3.horizontal.decrease", action: onFilter)
					.tint(ink)
			}
		}
		ToolbarSpacer(.fixed, placement: .topBarTrailing)
		ToolbarItem(placement: .topBarTrailing) {
			Button { showingProfile = true } label: {
				ProfileAvatar(nickname: profile.nickname, image: profile.avatar, size: 34)
			}
			.accessibilityLabel(profile.nickname.isEmpty ? "Profile" : "Profile, \(profile.nickname)")
		}
		.sharedBackgroundVisibility(.hidden)
	}
}
