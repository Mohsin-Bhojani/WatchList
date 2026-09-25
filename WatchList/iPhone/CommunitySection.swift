//
//  CommunitySection.swift
//  WatchList
//
//  The Everyone on WatchList card on the show, episode and film pages: a
//  half-circle gauge split by how many gave each rating, with the rating most
//  people gave in its middle — the design's "62% Go for it" — and a key of
//  every rating beside it (under it, where the card is narrow), marking yours. Until there's a
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
					// The key beside the gauge where there's room, under it where there isn't.
					ViewThatFits(in: .horizontal) {
						HStack(alignment: .center, spacing: 22) {
							gauge(opinion)
							key(opinion)
						}
						VStack(spacing: 14) {
							gauge(opinion)
							key(opinion)
						}
					}
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

	/// A half circle split into each rating's share, best rating on the left,
	/// with the leading rating's share and name in the middle.
	private func gauge(_ opinion: CommunityOpinion) -> some View {
		let width: CGFloat = 190
		let line: CGFloat = 18
		let segments = CommunityGauge.segments(opinion)
		return ZStack(alignment: .bottom) {
			ZStack {
				GaugeArc(from: 0, to: 1)
					.stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: line, lineCap: .butt))
				ForEach(segments, id: \.option) { segment in
					GaugeArc(from: segment.from, to: segment.to)
						.stroke(scale.tint(segment.option), style: StrokeStyle(lineWidth: line, lineCap: .butt))
				}
			}
			.padding(line / 2)
			.frame(width: width, height: width / 2 + line / 2)
			if let leading = opinion.leading {
				VStack(spacing: 0) {
					Text("\(Int((leading.share * 100).rounded()))%")
						.font(.system(size: 30, weight: .bold, design: .rounded))
						.foregroundStyle(.white)
					Text(leading.option)
						.font(.system(size: 13, weight: .semibold))
						.foregroundStyle(scale.tint(leading.option))
						.lineLimit(1)
						.minimumScaleFactor(0.7)
				}
				.frame(width: width - line * 2 - 16)
			}
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(opinion.leading.map {
			"\(Int(($0.share * 100).rounded())) per cent said \($0.option)"
		} ?? "No ratings")
	}

	/// Every rating in the scale's order: its colour, name, how many, and yours marked.
	private func key(_ opinion: CommunityOpinion) -> some View {
		VStack(alignment: .leading, spacing: 7) {
			ForEach(opinion.spread, id: \.option) { entry in
				HStack(spacing: 8) {
					Circle()
						.fill(scale.tint(entry.option).opacity(entry.count > 0 ? 1 : 0.35))
						.frame(width: 9, height: 9)
					Text(entry.option)
						.font(.system(size: 13, weight: .medium))
						.foregroundStyle(.white.opacity(entry.count > 0 ? 0.9 : 0.5))
						.lineLimit(1)
					Spacer(minLength: 8)
					if entry.option == opinion.yours {
						Image(systemName: "person.fill")
							.font(.system(size: 10, weight: .bold))
							.foregroundStyle(.white)
					}
					Text("\(Int((opinion.share(of: entry.option) * 100).rounded()))%")
						.font(.system(size: 12, weight: .semibold, design: .rounded))
						.foregroundStyle(.white.opacity(entry.count > 0 ? 0.8 : 0.4))
						.frame(width: 38, alignment: .trailing)
				}
				.accessibilityElement(children: .combine)
				.accessibilityLabel("\(entry.option), \(entry.count)\(entry.option == opinion.yours ? ", yours" : "")")
			}
		}
		.frame(minWidth: 170, maxWidth: 280)
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

enum CommunityGauge {
	/// Each rating given, as where its slice starts and ends along the arc, 0
	/// to 1, in the scale's order — with a hairline gap between neighbours but
	/// none at the gauge's two ends.
	static func segments(_ opinion: CommunityOpinion) -> [(option: String, from: Double, to: Double)] {
		let given = opinion.spread.filter { $0.count > 0 }
		let gap = given.count > 1 ? 0.008 : 0
		var start = 0.0
		return given.enumerated().map { index, entry in
			let end = index == given.count - 1 ? 1 : start + opinion.share(of: entry.option)
			defer { start = end }
			return (entry.option, start + (index > 0 ? gap / 2 : 0), end - (index < given.count - 1 ? gap / 2 : 0))
		}
	}
}

/// A stretch of the gauge's half circle, which runs from the left end (0)
/// over the top to the right end (1).
private struct GaugeArc: Shape {
	let from: Double
	let to: Double

	func path(in rect: CGRect) -> Path {
		let radius = min(rect.width / 2, rect.height)
		let centre = CGPoint(x: rect.midX, y: rect.maxY)
		var path = Path()
		path.addArc(center: centre, radius: radius,
		            startAngle: .degrees(180 + 180 * from), endAngle: .degrees(180 + 180 * to), clockwise: false)
		return path
	}
}
