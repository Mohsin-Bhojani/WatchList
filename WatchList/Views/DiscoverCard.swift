//
//  DiscoverCard.swift
//  WatchList
//
//  Discover's swipe card: the poster, what it's tagged with, and the swipe that
//  decides it — right to add, left if not interested, up for later.
//  Split out of PhoneDiscoverView.swift.
//

import SwiftUI
import SwiftData
import WatchListCore
import WatchListLibrary

// MARK: - Card

/// The suggestion on screen. It follows the finger, tilting as it goes and
/// saying what it's about to decide; let go past the threshold and it flies off
/// that way before deciding, short of it and it springs back. The drag is kept
/// in here, so the page around the card isn't redrawn as it moves.
struct DiscoverCard: View {
	let suggestion: Suggestion
	let reason: String?
	/// The poster of the library title it was suggested from, for the reason chip.
	var reasonPosterURL: String? = nil
	let posterMaxWidth: CGFloat
	let showsHint: Bool
	let onDecide: (CardDecision) -> Void

	@State private var offset: CGSize = .zero
	/// Set once it's decided, so a second swipe can't decide it again.
	@State private var decided = false

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
		VStack(spacing: 12) {
			PosterImage(urlString: suggestion.largePosterURL, systemPlaceholder: suggestion.placeholder)
				.aspectRatio(2.0 / 3.0, contentMode: .fit)
				// Why it's here, on the poster itself (design B): the title it came
				// from, small, beside the reason — and what it's tagged with.
				.overlay(alignment: .topLeading) {
					if let reason {
						HStack(spacing: 6) {
							if let reasonPosterURL, !reasonPosterURL.isEmpty {
								PosterImage(urlString: reasonPosterURL, systemPlaceholder: "film")
									.frame(width: 22, height: 22)
									.clipShape(Circle())
							}
							Text(reason)
								.font(.system(size: 12, weight: .semibold))
								.foregroundStyle(.white)
								.lineLimit(1)
								.minimumScaleFactor(0.8)
						}
						.padding(.leading, reasonPosterURL == nil ? 10 : 4)
						.padding(.trailing, 10)
						.padding(.vertical, 4)
						.glassEffect(.regular.tint(.black.opacity(0.3)), in: Capsule())
						.padding(10)
					}
				}
				.overlay(alignment: .bottomLeading) {
					HStack(spacing: 6) {
						ForEach(suggestion.genres.prefix(2), id: \.self) { genre in
							Text(genre)
								.font(.system(size: 12, weight: .semibold))
								.foregroundStyle(.white)
								.padding(.horizontal, 10)
								.padding(.vertical, 5)
								.glassEffect(.regular.tint(.black.opacity(0.3)), in: Capsule())
						}
					}
					.padding(10)
				}
				.clipShape(shape)
				.overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 1))
				.overlay { hint }
				.shadow(color: .black.opacity(0.35), radius: 24, y: 12)
				// Whatever height the rest leaves, so the page never has to scroll.
				.frame(maxWidth: posterMaxWidth, maxHeight: .infinity)
				.accessibilityHidden(true)
			VStack(spacing: 8) {
				Text(suggestion.title)
					.font(.system(size: 26, weight: .bold))
					.foregroundStyle(.white)
					.multilineTextAlignment(.center)
					.lineLimit(2)
					.minimumScaleFactor(0.8)
					.accessibilityAddTraits(.isHeader)
				score
				HStack(spacing: 8) {
					if let verdict = suggestion.equivalentVerdict { VerdictChip(rating: verdict) }
					Label(suggestion.kindLabel, systemImage: suggestion.kind.systemImage)
						.font(.system(size: 12, weight: .semibold))
						.foregroundStyle(.white)
						.padding(.horizontal, 9)
						.padding(.vertical, 5)
						.background(.white.opacity(0.12), in: Capsule())
				}
			}
			.fixedSize(horizontal: false, vertical: true)
			if !suggestion.overview.isEmpty {
				Text(suggestion.overview)
					.font(.system(size: 15))
					.foregroundStyle(.white.opacity(0.82))
					.multilineTextAlignment(.center)
					.lineLimit(4)
					.fixedSize(horizontal: false, vertical: true)
			}
			if showsHint {
				Text("Swipe right to add · left if not interested · up for later")
					.font(.system(size: 12, weight: .medium))
					.foregroundStyle(.white.opacity(0.55))
					.lineLimit(1)
					.minimumScaleFactor(0.8)
			}
		}
		.padding(.horizontal, 24)
		.padding(.top, 6)
		.contentShape(Rectangle())
		.offset(offset)
		.rotationEffect(.degrees(Double(offset.width) / 20), anchor: .bottom)
		.gesture(swipe)
		.accessibilityElement(children: .contain)
		.accessibilityActions {
			Button(CardDecision.add.label) { commit(.add) }
			Button(CardDecision.notInterested.label) { commit(.notInterested) }
			Button(CardDecision.later.label) { commit(.later) }
		}
	}

	/// TMDb's average, as stars and as the number.
	@ViewBuilder private var score: some View {
		if let average = suggestion.averageScore, let stars = suggestion.averageStars {
			HStack(spacing: 8) {
				StarsLabel(value: stars, size: 13, showsValue: false)
				Text("\(average.formatted(.number.precision(.fractionLength(1)))) average on TMDb")
					.font(.system(size: 14, weight: .medium))
					.foregroundStyle(.white.opacity(0.8))
			}
			.accessibilityElement(children: .combine)
		} else {
			Text("No ratings on TMDb yet")
				.font(.system(size: 14, weight: .medium))
				.foregroundStyle(.white.opacity(0.7))
		}
	}

	/// What the card is about to decide, stamped on the poster and firming up as
	/// it nears the threshold.
	@ViewBuilder private var hint: some View {
		if let lean = CardDecision.leaning(offset) {
			Label(lean.decision.swipeLabel, systemImage: lean.decision.symbol)
				.font(.system(size: 17, weight: .heavy))
				.foregroundStyle(.white)
				.padding(.horizontal, 16)
				.padding(.vertical, 9)
				.background(lean.decision.tint ?? .black.opacity(0.6), in: Capsule())
				.scaleEffect(0.85 + 0.15 * lean.progress)
				.opacity(Double(lean.progress))
		}
	}

	private var swipe: some Gesture {
		DragGesture(minimumDistance: 12)
			.onChanged { value in
				guard !decided else { return }
				let wasPast = CardDecision.forSwipe(translation: offset, predictedEnd: offset) != nil
				offset = value.translation
				let isPast = CardDecision.forSwipe(translation: offset, predictedEnd: offset) != nil
				// A tick as it crosses the threshold, either way.
				if isPast != wasPast { Haptics.selection() }
			}
			.onEnded { value in
				guard !decided else { return }
				if let decision = CardDecision.forSwipe(translation: value.translation,
				                                        predictedEnd: value.predictedEndTranslation) {
					commit(decision)
				} else {
					withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { offset = .zero }
				}
			}
	}

	/// Flies off the way the decision goes, from wherever it's been dragged, then
	/// decides.
	private func commit(_ decision: CardDecision) {
		guard !decided else { return }
		decided = true
		withAnimation(.easeIn(duration: 0.24)) { offset = decision.flyOff(from: offset) }
		Task {
			try? await Task.sleep(for: .milliseconds(240))
			onDecide(decision)
			// Back at rest, for when the same title comes straight round again.
			withAnimation(Glass.smooth) { offset = .zero }
			decided = false
		}
	}
}

extension CardDecision {
	/// The swipe label's colour.
	var tint: Color? {
		switch self {
		case .add:           return Glass.ratingPerfection
		case .notInterested: return Glass.ratingSkip
		case .later:         return nil
		}
	}
}
