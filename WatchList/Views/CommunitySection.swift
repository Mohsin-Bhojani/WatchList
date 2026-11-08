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
import WatchListCore
import WatchListLibrary

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

	/// The rating most gave, in its colour, and how many rated it.
	private func headline(_ opinion: CommunityOpinion) -> some View {
		HStack(alignment: .firstTextBaseline) {
			if let leading = opinion.leading {
				Text(leading.option)
					.font(.system(.title2, design: .serif, weight: .bold))
					.foregroundStyle(scale.tint(leading.option))
					.lineLimit(1)
					.minimumScaleFactor(0.7)
			}
			Spacer()
			Text("\(opinion.total) rating\(opinion.total == 1 ? "" : "s")")
				.font(.system(.caption, weight: .medium))
				.foregroundStyle(.white.opacity(0.6))
		}
		.accessibilityElement(children: .combine)
	}

	/// After design B of the alternatives: one bar split by how everyone
	/// rated it, in the scale's order, with yours marked under its share and
	/// the colours named beneath.
	private func spread(_ opinion: CommunityOpinion) -> some View {
		let options = scale.options
		let shares = options.map { opinion.share(of: $0) }
		return VStack(alignment: .leading, spacing: 8) {
			GeometryReader { proxy in
				let width = proxy.size.width
				let gaps = CGFloat(max(shares.filter { $0 > 0 }.count - 1, 0)) * 2
				ZStack(alignment: .topLeading) {
					HStack(spacing: 2) {
						ForEach(Array(options.enumerated()), id: \.offset) { index, option in
							if shares[index] > 0 {
								Rectangle()
									.fill(scale.tint(option))
									.frame(width: (width - gaps) * shares[index])
							}
						}
					}
					.frame(height: 14)
					.clipShape(Capsule())
					// Yours, under the middle of its share.
					if let yours = opinion.yours, let index = options.firstIndex(of: yours) {
						let before = shares[..<index].reduce(0, +)
						let middle = (width - gaps) * (before + shares[index] / 2)
						HStack(spacing: 3) {
							Image(systemName: "arrowtriangle.up.fill")
								.font(.caption2)
							Text("You")
								.font(.system(.caption2, weight: .bold))
						}
						.foregroundStyle(scale.tint(yours))
						.fixedSize()
						.offset(x: min(max(middle - 14, 0), width - 34), y: 18)
					}
				}
			}
			.frame(height: 34)
			.accessibilityElement()
			.accessibilityLabel(options.enumerated().map { "\($0.element) \(Int((shares[$0.offset] * 100).rounded())) per cent" }
				.joined(separator: ", ") + (opinion.yours.map { ". Yours: \($0)" } ?? ""))
			TileFlowLayout(spacing: 10) {
				ForEach(options, id: \.self) { option in
					HStack(spacing: 4) {
						RoundedRectangle(cornerRadius: 2).fill(scale.tint(option)).frame(width: 8, height: 8)
						Text(option)
							.font(.system(.caption2, weight: .medium))
							.foregroundStyle(.white.opacity(0.75))
					}
				}
			}
			.accessibilityHidden(true)
		}
	}

	/// How many have rated it, and that they're all you for now.
	private func footnote(_ opinion: CommunityOpinion) -> some View {
		Text(opinion.total == 1 && opinion.yours != nil
		     ? "1 rating — yours. Others appear here when WatchList can reach them."
		     : "\(opinion.total) ratings")
			.font(.system(.caption, weight: .medium))
			.foregroundStyle(.white.opacity(0.6))
			.fixedSize(horizontal: false, vertical: true)
	}

	private var waiting: some View {
		HStack(spacing: 10) {
			Image(systemName: "person.2")
				.font(.system(.body, weight: .light))
				.foregroundStyle(.white.opacity(0.6))
			Text("No ratings yet. Rate it and yours shows here.")
				.font(.system(.subheadline, weight: .medium))
				.foregroundStyle(.white.opacity(0.75))
				.fixedSize(horizontal: false, vertical: true)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}
}
