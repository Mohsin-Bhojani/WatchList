//
//  SuggestionDetailView.swift
//  WatchList Watch App
//
//  What tapping a Discover poster opens: the rest of the iPhone's Discover card,
//  on the poster's colour — why it's suggested, the title, TMDb's average as
//  stars, the verdict those come to and whether it's a show or a film, and the
//  synopsis — then the three swipes as Liquid Glass buttons.
//

import SwiftUI

struct SuggestionDetailView: View {
	let suggestion: Suggestion
	/// "Because you rated Arrival Perfection".
	let reason: String?
	let tone: Color
	let onDecide: (CardDecision) -> Void

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 8) {
					if let reason {
						Text(reason)
							.font(.system(size: 12, weight: .medium))
							.foregroundStyle(.white.opacity(0.8))
							.multilineTextAlignment(.center)
							.fixedSize(horizontal: false, vertical: true)
					}
					Text(suggestion.title)
						.font(.system(size: 19, weight: .bold))
						.foregroundStyle(.white)
						.multilineTextAlignment(.center)
						.fixedSize(horizontal: false, vertical: true)
						.accessibilityAddTraits(.isHeader)
					score
					HStack(spacing: 5) {
						if let verdict = suggestion.equivalentVerdict { VerdictChip(rating: verdict) }
						Chip {
							Label(suggestion.kindLabel, systemImage: suggestion.kind.systemImage)
						}
					}
					if !suggestion.overview.isEmpty {
						Text(suggestion.overview)
							.font(.system(size: 14))
							.foregroundStyle(.white.opacity(0.82))
							.multilineTextAlignment(.center)
							.fixedSize(horizontal: false, vertical: true)
							.padding(.top, 2)
					}

					VStack(spacing: 6) {
						decision(.add, tint: Color(.ratingPerfection))
						decision(.later, tint: nil)
						decision(.notInterested, tint: Color(.ratingSkip))
					}
					.padding(.top, 8)
				}
				.padding(.horizontal, 2)
			}
			.containerBackground(for: .navigation) {
				LinearGradient(colors: [tone, Artwork.deeper(tone)], startPoint: .top, endPoint: .bottom)
			}
		}
		// The close button in plain glass, not the red accent, over the poster's colour.
		.tint(.white.opacity(0.35))
	}

	/// TMDb's average, as stars and as the number — as the iPhone's card shows it.
	@ViewBuilder
	private var score: some View {
		if let average = suggestion.averageScore, let stars = suggestion.averageStars {
			VStack(spacing: 2) {
				HStack(spacing: 1) {
					ForEach(0..<5, id: \.self) { index in
						Image(systemName: symbol(for: stars - Double(index)))
					}
				}
				.font(.system(size: 11, weight: .semibold))
				.foregroundStyle(WatchColors.starGold)
				Text("\(average.formatted(.number.precision(.fractionLength(1)))) average on TMDb")
					.font(.system(size: 12, weight: .medium))
					.foregroundStyle(.white.opacity(0.8))
			}
			.accessibilityElement(children: .ignore)
			.accessibilityLabel("\(StarRating.label(stars)) of 5 stars, \(average.formatted(.number.precision(.fractionLength(1)))) on TMDb")
		} else {
			Text("No ratings on TMDb yet")
				.font(.system(size: 12, weight: .medium))
				.foregroundStyle(.white.opacity(0.7))
		}
	}

	private func symbol(for filled: Double) -> String {
		if filled >= 1 { return "star.fill" }
		if filled >= 0.5 { return "star.leadinghalf.filled" }
		return "star"
	}

	/// A decision as a Liquid Glass capsule across the sheet, tinted as the
	/// iPhone's swipe stamp is.
	private func decision(_ decision: CardDecision, tint: Color?) -> some View {
		Button { onDecide(decision) } label: {
			Label(decision.label, systemImage: decision.symbol)
				.font(.system(size: 14, weight: .semibold))
				.foregroundStyle(.white)
				.lineLimit(1)
				.minimumScaleFactor(0.8)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 10)
				.glassEffect(tint.map { .regular.tint($0.opacity(0.55)).interactive() } ?? .regular.interactive(),
				             in: Capsule())
		}
		.buttonStyle(.plain)
	}
}

/// A verdict as the iPhone's chip shows it: its colour as a dot, and its name.
private struct VerdictChip: View {
	let rating: Rating

	var body: some View {
		Chip {
			HStack(spacing: 4) {
				Circle()
					.fill(WatchColors.verdict(rating))
					.frame(width: 6, height: 6)
				Text(rating.rawValue)
			}
		}
	}
}

/// The iPhone card's small capsule.
private struct Chip<Content: View>: View {
	@ViewBuilder let content: Content

	var body: some View {
		content
			.font(.system(size: 11, weight: .semibold))
			.foregroundStyle(.white)
			.lineLimit(1)
			.padding(.horizontal, 8)
			.padding(.vertical, 4)
			.background(.white.opacity(0.12), in: Capsule())
	}
}
