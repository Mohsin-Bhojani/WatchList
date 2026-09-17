//
//  FadedPosterCard.swift
//  WatchList
//
//  The Shows tab's grid card, like Home's Recently watched cards: the poster
//  fading from its own colour down into a strip of its verdict's — a neutral
//  slate when it isn't rated — with the title, its stars and details on the
//  strip, and its watch status as a label on the poster.
//

import SwiftUI

struct FadedPosterCard: View {
	let item: WatchedTitle

	@State private var tone: UIColor?

	private static let unratedColor = Color(.unratedTone)

	init(item: WatchedTitle) {
		self.item = item
		_tone = State(initialValue: PageTheme.cached(item.posterURL))
	}

	/// A neutral dark until the poster's colour is in, or when there's no poster.
	private var toneColor: Color { Color(uiColor: tone ?? UIColor(resource: .posterToneFallback)) }
	private var verdictColor: Color { item.rating.map { Glass.tint($0) } ?? Self.unratedColor }

	/// The verdict, then the kind and size: "Go For It · 3 seasons · 19 ep".
	private var detailLine: String {
		[item.rating?.rawValue ?? "", item.cardSubtitle].filter { !$0.isEmpty }.joined(separator: " · ")
	}

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: Glass.corner, style: .continuous)
		VStack(alignment: .leading, spacing: 0) {
			PosterImage(urlString: item.posterURL, systemPlaceholder: item.placeholder)
				.aspectRatio(2.0 / 3.0, contentMode: .fit)
				.mask {
					LinearGradient(stops: [
						.init(color: .black, location: 0),
						.init(color: .black, location: 0.74),
						.init(color: .clear, location: 1),
					], startPoint: .top, endPoint: .bottom)
				}
				.overlay(alignment: .topTrailing) {
					statusLabel
						.padding(8)
				}

			VStack(alignment: .leading, spacing: 3) {
				// The stars beside the title when both fit; otherwise the title
				// keeps the room, and the verdict under it still says the rating.
				ViewThatFits(in: .horizontal) {
					HStack(alignment: .center, spacing: 6) {
						title
						Spacer(minLength: 0)
						if let stars = item.stars {
							StarsLabel(value: stars, size: 9, showsValue: false)
								.fixedSize()
						}
					}
					title
				}
				Text(detailLine)
					.font(.system(size: 12, weight: .medium, design: .rounded))
					.foregroundStyle(.white.opacity(0.8))
					.lineLimit(1)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal, 10)
			// Up into the fade, so the details sit on the strip's colour.
			.padding(.top, -16)
			.padding(.bottom, 11)
		}
		// The poster's colour at the top, turning to the verdict's under the fade.
		.background(LinearGradient(stops: [
			.init(color: toneColor, location: 0),
			.init(color: toneColor, location: 0.6),
			.init(color: verdictColor, location: 0.86),
			.init(color: verdictColor, location: 1),
		], startPoint: .top, endPoint: .bottom))
		.clipShape(shape)
		.overlay(shape.strokeBorder(.white.opacity(0.1), lineWidth: 1))
		.shadow(color: .black.opacity(0.12), radius: 10, y: 6)
		.accessibilityElement(children: .combine)
		.task(id: item.posterURL) {
			guard let sampled = await PageTheme.load(item.posterURL), !Task.isCancelled,
			      sampled != tone else { return }
			withAnimation(.easeOut(duration: 0.3)) { tone = sampled }
		}
	}

	private var title: some View {
		Text(item.title)
			.font(.system(size: 15, weight: .bold, design: .serif))
			.foregroundStyle(.white)
			.lineLimit(1)
	}

	/// The watch status, named, in its own colour.
	private var statusLabel: some View {
		HStack(spacing: 4) {
			Image(systemName: item.status.systemImage)
				.font(.system(size: 9, weight: .bold))
			Text(item.status.rawValue)
				.font(.system(size: 11, weight: .semibold))
		}
		.foregroundStyle(.white)
		.padding(.horizontal, 8)
		.padding(.vertical, 4)
		.background(Glass.tint(item.status).opacity(0.92), in: Capsule())
		.overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
	}
}
