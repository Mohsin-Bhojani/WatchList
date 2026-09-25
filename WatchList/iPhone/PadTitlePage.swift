//
//  PadTitlePage.swift
//  WatchList
//
//  The film, show, season and episode pages on an iPad, held either way: a top
//  like Home's Up next held sideways — the landscape artwork on the trailing
//  side, fading in from the page's colour — with a stack down the leading
//  side: the poster, what it is, the title, TMDb's stars, a bigger synopsis
//  and the status switch. Under it, whatever the status puts first (Up next
//  while watching; your verdict and Everyone on WatchList once watched), then
//  two things side by side — the trailer, a season's episodes or an episode's
//  cast, beside Details — then the rest.
//
//  The iPhone, and an iPad narrowed to a phone's width, keep the one-column
//  page (TitlePageColumns).
//

import SwiftUI

enum PadTitleLayout {
	/// An iPad at full width or a wide split — not a phone-width slide-over.
	static func applies(_ sizeClass: UserInterfaceSizeClass?) -> Bool {
		UIDevice.current.userInterfaceIdiom == .pad && sizeClass == .regular
	}

	/// How far the page scrolls before the bar turns solid with the compact
	/// title: past the stack's title, which sits lower than a phone's.
	static let compactBarOffset: CGFloat = 440

	/// "FILM · 2010 · 2H 28M", in the small caps above the title.
	static func kindLine(_ parts: [String?]) -> String {
		parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ").uppercased()
	}
}

/// The top of an iPad title page.
struct PadTitleHero<Controls: View>: View {
	let backdropURL: String
	let posterURL: String
	let placeholder: String
	let kindLine: String
	let title: String
	let voteAverage: Double?
	/// "38K votes", beside the stars.
	let votes: String?
	let synopsis: String
	/// The status switch.
	@ViewBuilder let controls: Controls

	@State private var width: CGFloat = 0
	@State private var expanded = false
	/// The synopsis's height folded, and in full, to know whether "more" has anything to show.
	@State private var foldedHeight: CGFloat = 0
	@State private var fullHeight: CGFloat = 0

	/// Sideways — or any page this wide — the artwork is bigger and the stack
	/// narrower; upright, the stack runs a little way over the artwork's fade.
	private var wide: Bool { width >= 960 }

	var body: some View {
		let artWidth = width * (wide ? 0.68 : 0.62)
		let artHeight = min(artWidth * 9 / 16, wide ? 540 : 400)
		ZStack(alignment: .topLeading) {
			if !backdropURL.isEmpty {
				artwork
					.frame(width: artWidth, height: artHeight)
					.frame(maxWidth: .infinity, alignment: .trailing)
			}
			stack
				.frame(width: max(width * (wide ? 0.4 : 0.56), 300), alignment: .leading)
				.padding(.leading, 28)
				.padding(.top, 8)
		}
		.frame(maxWidth: .infinity, alignment: .topLeading)
		.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
	}

	private var artwork: some View {
		PosterImage(urlString: backdropURL, systemPlaceholder: placeholder)
			// Fades out at the foot, and in from the page's colour on the leading side.
			.mask {
				LinearGradient(stops: [
					.init(color: .clear, location: 0),
					.init(color: .black, location: 0.12),
					.init(color: .black, location: 0.7),
					.init(color: .clear, location: 1),
				], startPoint: .top, endPoint: .bottom)
			}
			.mask {
				LinearGradient(stops: [
					.init(color: .clear, location: 0),
					.init(color: .black, location: 0.45),
				], startPoint: .leading, endPoint: .trailing)
			}
			.allowsHitTesting(false)
			.accessibilityHidden(true)
	}

	private var synopsisText: some View {
		Text(synopsis)
			.font(.system(size: wide ? 16 : 15))
			.foregroundStyle(.white.opacity(0.88))
			.lineSpacing(2)
	}

	private var stack: some View {
		VStack(alignment: .leading, spacing: 0) {
			PosterImage(urlString: posterURL, systemPlaceholder: placeholder)
				.frame(width: wide ? 150 : 128, height: wide ? 225 : 192)
				.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
				.shadow(color: .black.opacity(0.45), radius: 22, y: 12)
				.accessibilityHidden(true)
			if !kindLine.isEmpty {
				Text(kindLine)
					.font(.system(size: 13, weight: .bold))
					.kerning(1)
					.foregroundStyle(.white.opacity(0.7))
					.padding(.top, 18)
			}
			Text(title)
				.font(.system(size: wide ? 40 : 34, weight: .bold))
				.foregroundStyle(.white)
				.lineLimit(3)
				.minimumScaleFactor(0.7)
				.fixedSize(horizontal: false, vertical: true)
				.accessibilityAddTraits(.isHeader)
				.padding(.top, 2)
			if (voteAverage ?? 0) > 0 {
				PageMetaLine(voteAverage: voteAverage, parts: votes.map { [$0] } ?? [])
					.padding(.top, 6)
			}
			if !synopsis.isEmpty {
				synopsisText
					.lineLimit(expanded ? nil : (wide ? 6 : 5))
					.fixedSize(horizontal: false, vertical: true)
					.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { foldedHeight = $0 }
					// The whole of it, unseen, measured at the same width.
					.background(alignment: .top) {
						synopsisText
							.fixedSize(horizontal: false, vertical: true)
							.hidden()
							.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
					}
					.padding(.top, 12)
				if expanded || fullHeight > foldedHeight + 1 {
					Button(expanded ? "less" : "more") {
						withAnimation(Glass.smooth) { expanded.toggle() }
					}
					.font(.system(size: 14, weight: .semibold))
					.foregroundStyle(.white)
					.padding(.top, 4)
				}
			}
			controls
				.padding(.top, 16)
		}
		.shadow(color: .black.opacity(0.25), radius: 6, y: 1)
	}
}

/// Everything under the top: `lead` across the page, then `main` and `side`
/// side by side — a film or show's trailer and Details, a season's episodes
/// and Details — then `rest` across the page.
struct PadTitleBody<Lead: View, Main: View, Side: View, Rest: View>: View {
	@ViewBuilder let lead: Lead
	@ViewBuilder let main: Main
	@ViewBuilder let side: Side
	@ViewBuilder let rest: Rest

	@State private var width: CGFloat = 0

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			lead
			HStack(alignment: .top, spacing: 20) {
				VStack(spacing: 16) { main }
					.frame(maxWidth: .infinity)
				VStack(spacing: 16) { side }
					.frame(width: max((width - 20) * 0.42, 300))
			}
			rest
		}
		.padding(.horizontal, 28)
		.padding(.top, 20)
		.padding(.bottom, 32)
		.onGeometryChange(for: CGFloat.self) { $0.size.width - 56 } action: { width = $0 }
		.frame(maxWidth: 1240)
		.frame(maxWidth: .infinity)
	}
}
