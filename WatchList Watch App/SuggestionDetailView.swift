//
//  SuggestionDetailView.swift
//  WatchList Watch App
//
//  What tapping a Discover poster opens: the title, what it is, TMDb's average,
//  and the synopsis — then the three swipes as buttons, for when a button suits
//  better than a swipe.
//

import SwiftUI

struct SuggestionDetailView: View {
	let suggestion: Suggestion
	let onDecide: (CardDecision) -> Void

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 6) {
					Text(suggestion.title)
						.font(.headline)
						.fixedSize(horizontal: false, vertical: true)
						.accessibilityAddTraits(.isHeader)
					Text(meta)
						.font(.footnote)
						.foregroundStyle(.secondary)
					if let score = suggestion.averageScore {
						Label("\(score.formatted(.number.precision(.fractionLength(1)))) on TMDb",
						      systemImage: "star.fill")
							.font(.footnote)
							.foregroundStyle(WatchColors.starGold)
					}
					Text(suggestion.overview.isEmpty ? "TMDb has no synopsis for this one." : suggestion.overview)
						.font(.body)
						.foregroundStyle(suggestion.overview.isEmpty ? .secondary : .primary)
						.fixedSize(horizontal: false, vertical: true)
						.padding(.top, 2)

					VStack(spacing: 6) {
						decision(.add, tint: .green)
						decision(.later, tint: .gray)
						decision(.notInterested, tint: .red)
					}
					.padding(.top, 8)
				}
			}
		}
	}

	/// "TV Show · 2024 · Drama, Mystery".
	private var meta: String {
		var parts = [suggestion.kindLabel]
		if let year = suggestion.year { parts.append(String(year)) }
		if !suggestion.genres.isEmpty { parts.append(suggestion.genres.prefix(2).joined(separator: ", ")) }
		return parts.joined(separator: " · ")
	}

	private func decision(_ decision: CardDecision, tint: Color) -> some View {
		Button { onDecide(decision) } label: {
			Label(decision.label, systemImage: decision.symbol)
				.frame(maxWidth: .infinity)
		}
		.tint(tint)
	}
}
