//
//  CommunitySection.swift
//  WatchList
//
//  The Everyone on WatchList card on the show, episode and film pages: the
//  rating most people gave as the headline — the design's "62% Go for it" —
//  the spread of every rating under it, and where yours sits. Until there's a
//  server behind Community.source, the only rating it has is your own, and it
//  says so.
//

import SwiftUI

struct CommunitySection: View {
	let title: CommunityTitle
	let scale: CommunityScale
	/// Your own rating, by name; nil while you haven't given one.
	let yours: String?

	@State private var opinion: CommunityOpinion?

	var body: some View {
		PageSection(title: "Everyone on WatchList") {
			VStack(alignment: .leading, spacing: 12) {
				if let opinion, opinion.total > 0 {
					headline(opinion)
					spread(opinion)
					footnote(opinion)
				} else {
					waiting
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(14)
			.liquidCard(cornerRadius: 20)
		}
		.task(id: yours) {
			opinion = await Community.opinion(for: title, scale: scale, yours: yours)
		}
	}

	/// "62% Go For It", as the design has it.
	private func headline(_ opinion: CommunityOpinion) -> some View {
		Group {
			if let leading = opinion.leading {
				HStack(spacing: 8) {
					Circle()
						.fill(scale.tint(leading.option))
						.frame(width: 10, height: 10)
					Text("\(Int((leading.share * 100).rounded()))% \(leading.option)")
						.font(.system(size: 22, weight: .bold))
						.foregroundStyle(.white)
						.lineLimit(1)
						.minimumScaleFactor(0.7)
				}
				.accessibilityElement(children: .combine)
				.accessibilityLabel("\(Int((leading.share * 100).rounded())) per cent said \(leading.option)")
			}
		}
	}

	/// A bar for each rating, longest first in the scale's own order.
	private func spread(_ opinion: CommunityOpinion) -> some View {
		VStack(spacing: 6) {
			ForEach(opinion.spread, id: \.option) { entry in
				HStack(spacing: 8) {
					Text(entry.option)
						.font(.system(size: 13, weight: .medium))
						.foregroundStyle(.white.opacity(entry.count > 0 ? 0.9 : 0.5))
						.frame(width: 84, alignment: .leading)
						.lineLimit(1)
						.minimumScaleFactor(0.8)
					GeometryReader { proxy in
						let share = opinion.share(of: entry.option)
						Capsule()
							.fill(.white.opacity(0.12))
							.overlay(alignment: .leading) {
								Capsule()
									.fill(scale.tint(entry.option))
									.frame(width: max(proxy.size.width * share, share > 0 ? 6 : 0))
							}
							.clipShape(Capsule())
					}
					.frame(height: 8)
					Text("\(entry.count)")
						.font(.system(size: 12, weight: .semibold, design: .rounded))
						.foregroundStyle(.white.opacity(entry.count > 0 ? 0.8 : 0.4))
						.frame(width: 22, alignment: .trailing)
					// Yours, marked where it sits.
					Image(systemName: "person.fill")
						.font(.system(size: 10, weight: .bold))
						.foregroundStyle(entry.option == opinion.yours ? .white : .clear)
						.accessibilityHidden(entry.option != opinion.yours)
						.accessibilityLabel("Your rating")
				}
				.accessibilityElement(children: .combine)
				.accessibilityLabel("\(entry.option), \(entry.count)\(entry.option == opinion.yours ? ", yours" : "")")
			}
		}
	}

	/// How many have rated it, and that they're all you for now.
	private func footnote(_ opinion: CommunityOpinion) -> some View {
		Text(opinion.total == 1 && opinion.yours != nil
		     ? "1 rating — yours. Others appear here when WatchList can reach them."
		     : "\(opinion.total) ratings")
			.font(.system(size: 12, weight: .medium))
			.foregroundStyle(.white.opacity(0.6))
			.fixedSize(horizontal: false, vertical: true)
	}

	private var waiting: some View {
		HStack(spacing: 10) {
			Image(systemName: "person.2")
				.font(.system(size: 18, weight: .light))
				.foregroundStyle(.white.opacity(0.6))
			Text("No ratings yet. Rate it and yours shows here.")
				.font(.system(size: 14, weight: .medium))
				.foregroundStyle(.white.opacity(0.75))
				.fixedSize(horizontal: false, vertical: true)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}
}
