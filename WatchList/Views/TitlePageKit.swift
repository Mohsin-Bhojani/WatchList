//
//  TitlePageKit.swift
//  WatchList
//
//  The pieces the iPhone show, season and episode pages share, after the
//  "Show view" design: a colour taken from the artwork, the page's gradient and
//  bar, the status switch, verdict chips, section headings, the
//  synopsis cards, the cast row and the compact bar's title — and the actions
//  their menus share: the status and rating sections, sharing, the artwork
//  sheet, details rows and removing a record.
//
//  This file holds the colour and the page layout; the rest is in
//  TitlePageControls, TitlePageCards and TitlePageActions.
//

import SwiftUI
import SwiftData
import WatchListCore
import WatchListLibrary

// MARK: - Colour

/// Colours sampled from artwork, by URL, so going back into a page doesn't
/// flash the fallback before its own colour.
@MainActor
enum PageTheme {
	/// The design's slate, until the artwork is in or when there is none.
	static let fallback = UIColor(resource: .pageFallback)

	private static var sampled: [String: UIColor] = [:]

	static func cached(_ url: String) -> UIColor? { sampled[url] }

	static func load(_ url: String) async -> UIColor? {
		if let hit = sampled[url] { return hit }
		guard !url.isEmpty, let link = URL(string: url),
		      let image = await ImageCache.shared.image(for: link),
		      let sampledColor = await ArtworkBand.sampledThemeColor(for: image) else { return nil }
		// Dark enough for the page's small white text, not just its title.
		let color = ArtworkBand.dimmedForWhiteText(sampledColor, limit: ArtworkBand.maxBodyTextLuminance)
		sampled[url] = color
		return color
	}
}

enum TitlePageLayout {
	/// The widest a title page's content runs in one column: all of an iPhone,
	/// and a readable column centred on an iPad upright. Wider, TitlePageColumns
	/// makes two.
	static let maxColumnWidth: CGFloat = 720
}

/// A title page's content. One column on a phone, and centred in a readable
/// width on an iPad upright; on an iPad wide enough — held sideways, say — two:
/// the title's own part (the poster, status and your verdict) on the leading
/// side and the rest beside it. `lead` then `rest` is the one column's order.
struct TitlePageColumns<Lead: View, Rest: View>: View {
	@ViewBuilder let lead: Lead
	@ViewBuilder let rest: Rest

	@State private var width: CGFloat = 0

	var body: some View {
		Group {
			if width >= 960 {
				HStack(alignment: .top, spacing: 28) {
					VStack(spacing: 16) { lead }
						.frame(width: min(width * 0.38, 420))
					VStack(spacing: 16) { rest }
						.frame(maxWidth: .infinity)
				}
				.padding(.horizontal, 28)
				.padding(.bottom, 32)
				.frame(maxWidth: 1240)
				.frame(maxWidth: .infinity)
				.environment(\.titlePageTwoColumns, true)
			} else {
				VStack(spacing: 16) {
					lead
					rest
				}
				.padding(.horizontal, 18)
				.padding(.bottom, 32)
				.readableColumn()
			}
		}
		.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
	}
}

extension EnvironmentValues {
	/// Inside TitlePageColumns' side-by-side layout, on a wide iPad.
	@Entry var titlePageTwoColumns = false
}

/// Builds its content knowing whether the title page is in two columns, so a
/// section can sit in the lead column there and in the flow on a phone.
struct PageColumnsReader<Content: View>: View {
	@Environment(\.titlePageTwoColumns) private var twoColumns
	@ViewBuilder let content: (Bool) -> Content

	var body: some View { content(twoColumns) }
}

extension View {
	/// Centres a page's content in a readable column on a wide screen.
	func readableColumn() -> some View {
		frame(maxWidth: TitlePageLayout.maxColumnWidth)
			.frame(maxWidth: .infinity)
	}

	/// A title page's ground: its colour running down to a deeper shade, the
	/// dark scheme, and a bar that turns solid once the title scrolls away.
	func titlePage(color: UIColor?, compactBar: Bool) -> some View {
		let base = color ?? PageTheme.fallback
		return background(LinearGradient(colors: [Color(uiColor: base), Color(uiColor: ArtworkBand.deeper(base))],
		                                 startPoint: .top, endPoint: .bottom)
				.ignoresSafeArea())
			.environment(\.colorScheme, .dark)
			.navigationBarTitleDisplayMode(.inline)
			.toolbarColorScheme(.dark, for: .navigationBar)
			.toolbarBackground(Color(uiColor: base), for: .navigationBar)
			.toolbarBackgroundVisibility(compactBar ? .visible : .hidden, for: .navigationBar)
	}

	/// The page's glass capsule buttons: View on IMDb, Share.
	func titlePageCapsule() -> some View {
		font(.system(.footnote, weight: .semibold))
			.foregroundStyle(.white)
			.frame(maxWidth: .infinity, minHeight: GlassControl.height)
			.glassEffect(.regular, in: Capsule())
	}
}
