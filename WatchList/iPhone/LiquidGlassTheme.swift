//
//  LiquidGlassTheme.swift
//  WatchList
//
//  The glass card the iPhone title pages — film, show, season, episode — lay
//  over their artwork's colour: iOS 26 glass with a faint white tint, so it
//  reads against the colour behind it; and the coloured ground the profile
//  lays it over. Everywhere else keeps the paper design system.
//

import SwiftUI

enum GlassControl {
	/// The height every glass button and switch stands at — the floating tab
	/// bar's and the search field's — on iPhone and iPad alike.
	static let height: CGFloat = 44
}

/// A colour running down to a deeper shade, as a title page does with its
/// poster's: the ground the profile, and Add Titles, lay their glass on.
struct PageGround {
	/// The top of it, already dim enough for white text.
	let base: UIColor

	/// Your accent, dimmed for white text.
	static var accent: PageGround { PageGround(base: ArtworkBand.dimmedForWhiteText(UIColor(Glass.accent))) }

	var gradient: LinearGradient {
		LinearGradient(colors: [Color(uiColor: base), Color(uiColor: ArtworkBand.deeper(base))],
		               startPoint: .top, endPoint: .bottom)
	}

	/// The deeper shade, for text on a white switch.
	var deep: Color { Color(uiColor: ArtworkBand.deeper(base)) }
}

extension View {
	/// A Liquid Glass card for a coloured title page.
	func liquidCard(cornerRadius: CGFloat = 22) -> some View {
		glassEffect(.regular.tint(.white.opacity(0.06)),
		            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
	}
}
