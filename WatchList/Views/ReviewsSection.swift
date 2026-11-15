//
//  ReviewsSection.swift
//  WatchList
//
//  Reviews on a show or film page: what people wrote about it on TMDb. One
//  shows on the page, cut to a few lines and opened by a tap; All reviews
//  lists the rest, so a long page doesn't get longer. The section isn't there when nobody has written one, so a
//  title with none doesn't get an empty card.
//

import SwiftUI
import WatchListCore

struct ReviewsSection: View {
	let kind: MediaKind
	let tmdbID: Int?

	@State private var reviews: [TMDbReview] = []

	/// Kept for the session, so going back to a page doesn't fetch them again.
	@MainActor private static var cache: [String: [TMDbReview]] = [:]

	private static let shown = 1

	var body: some View {
		// A stack, not a Group, so its task runs while there's nothing to show.
		VStack(spacing: 0) {
			if !reviews.isEmpty {
				PageSection(title: "Reviews") {
					VStack(spacing: 0) {
						ForEach(Array(reviews.prefix(Self.shown).enumerated()), id: \.element.id) { index, review in
							if index > 0 { PageRowDivider(inset: 0) }
							ReviewRow(review: review, collapsedLines: 3)
						}
						if reviews.count > Self.shown {
							PageRowDivider(inset: 0)
							NavigationLink { AllReviewsView(reviews: reviews) } label: {
								HStack {
									Text("All reviews")
										.font(.system(.subheadline, weight: .semibold))
									Spacer()
									Text("\(reviews.count)")
										.font(.system(.footnote, weight: .medium))
										.foregroundStyle(.white.opacity(0.6))
									Image(systemName: "chevron.right")
										.font(.system(.caption, weight: .bold))
										.foregroundStyle(.white.opacity(0.5))
								}
								.foregroundStyle(.white)
								.padding(.vertical, 12)
								.contentShape(Rectangle())
							}
							.buttonStyle(.plain)
						}
					}
					.padding(.horizontal, 14)
					.liquidCard(cornerRadius: 20)
				}
				.transition(.opacity)
			}
		}
		.task(id: tmdbID) { await load() }
	}

	private var key: String? { tmdbID.map { "\(kind == .film ? "film" : "show")-\($0)" } }

	private func load() async {
		guard let key, let tmdbID, TMDbConfig.isConfigured else { return }
		if let cached = Self.cache[key] {
			reviews = cached
			return
		}
		guard let fetched = try? await TMDbService.shared.reviews(kind, id: tmdbID), !Task.isCancelled else { return }
		let readable = ReviewText.readable(fetched)
		Self.cache[key] = readable
		withAnimation(.easeOut(duration: 0.25)) { reviews = readable }
	}
}

/// One review: who wrote it, their stars and when, then what they wrote —
/// a few lines until it's tapped open.
struct ReviewRow: View {
	let review: TMDbReview
	var collapsedLines = 5

	@State private var expanded = false

	var body: some View {
		let text = ReviewText.cleaned(review.content ?? "")
		VStack(alignment: .leading, spacing: 8) {
			HStack(alignment: .firstTextBaseline, spacing: 8) {
				Text(ReviewText.author(review))
					.font(.system(.subheadline, weight: .semibold))
					.lineLimit(1)
				if let stars = ReviewText.stars(review) {
					StarsLabel(value: stars, showsValue: false)
				}
				Spacer(minLength: 4)
				if let date = ReviewText.date(review) {
					Text(date.formatted(.dateTime.month(.abbreviated).year()))
						.font(.system(.caption, weight: .medium))
						.foregroundStyle(.white.opacity(0.55))
				}
			}
			Text(text)
				.font(.system(.subheadline))
				.foregroundStyle(.white.opacity(0.85))
				.lineLimit(expanded ? nil : collapsedLines)
				.fixedSize(horizontal: false, vertical: true)
			if !expanded && text.count > collapsedLines * 55 {
				Text("More")
					.font(.system(.footnote, weight: .semibold))
					.foregroundStyle(.white)
			}
		}
		.foregroundStyle(.white)
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.vertical, 12)
		.contentShape(Rectangle())
		.onTapGesture {
			Haptics.selection()
			withAnimation(Glass.smooth) { expanded.toggle() }
		}
		.accessibilityElement(children: .combine)
		.accessibilityHint(expanded ? "Shows less" : "Shows the whole review")
	}
}

/// Every review, each open in full.
struct AllReviewsView: View {
	let reviews: [TMDbReview]

	var body: some View {
		ScrollView {
			VStack(spacing: 0) {
				ForEach(Array(reviews.enumerated()), id: \.element.id) { index, review in
					if index > 0 { PageRowDivider(inset: 0) }
					ReviewRow(review: review, collapsedLines: 12)
				}
			}
			.padding(.horizontal, 14)
			.liquidCard(cornerRadius: 20)
			.padding(18)
		}
		.background(Color(red: 0.07, green: 0.08, blue: 0.1).ignoresSafeArea())
		.environment(\.colorScheme, .dark)
		.navigationTitle("Reviews")
		.navigationBarTitleDisplayMode(.inline)
	}
}
