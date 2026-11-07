//
//  TitlePageCards.swift
//  WatchList
//
//  The title pages' sections and cards: headings, synopsis, cast, the poster
//  header, your verdict and the details rows. Split out of TitlePageKit.swift.
//

import SwiftUI
import SwiftData
import WatchListCore
import WatchListLibrary

// MARK: - Sections and cards

struct PageSection<Content: View>: View {
	let title: String
	@ViewBuilder let content: Content

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text(title)
				.font(.system(size: 20, weight: .bold))
				.foregroundStyle(.white)
				.accessibilityAddTraits(.isHeader)
			content
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.top, 8)
	}
}

struct PageSmallCaps: View {
	let text: String

	var body: some View {
		Text(text.uppercased())
			.font(.system(size: 10, weight: .semibold, design: .monospaced))
			.kerning(1.2)
			.foregroundStyle(.white.opacity(0.55))
	}
}

/// A synopsis in a glass card; long ones fold to four lines with "more".
struct PageSynopsisCard: View {
	let text: String
	@State private var expanded = false

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			PageSmallCaps(text: "Synopsis")
			Text(text)
				.font(.system(size: 14))
				.foregroundStyle(.white.opacity(0.9))
				.lineLimit(expanded ? nil : 4)
				.fixedSize(horizontal: false, vertical: true)
			if text.count > 180 {
				Button(expanded ? "less" : "more") {
					withAnimation(Glass.smooth) { expanded.toggle() }
				}
				.font(.system(size: 13, weight: .semibold))
				.foregroundStyle(.white)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(14)
		.liquidCard(cornerRadius: 20)
	}
}

/// People in a row that runs out to the screen's edges.
struct PageCastRow: View {
	let cast: [CastEntry]

	var body: some View {
		ScrollView(.horizontal) {
			HStack(alignment: .top, spacing: 14) {
				ForEach(cast) { person in
					VStack(spacing: 6) {
						PersonAvatar(urlString: person.profileURL, name: person.name)
							.frame(width: 60, height: 60)
							.overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
						Text(person.name)
							.font(.system(size: 11, weight: .semibold))
							.foregroundStyle(.white)
							.multilineTextAlignment(.center)
							.lineLimit(2)
						if !person.character.isEmpty {
							Text(person.character)
								.font(.system(size: 10, weight: .medium))
								.foregroundStyle(.white.opacity(0.55))
								.lineLimit(1)
						}
					}
					.frame(width: 76)
					.accessibilityElement(children: .combine)
				}
			}
			.padding(.horizontal, 18)
		}
		.scrollIndicators(.hidden)
		.padding(.horizontal, -18)
	}
}

// MARK: - Header and your rating

/// A title page's header: the poster, the title — with a line under it when
/// there is one — and the meta line.
struct PagePosterHeader: View {
	let posterURL: String
	let placeholder: String
	let title: String
	var subtitle: String? = nil
	let voteAverage: Double?
	let metaParts: [String]

	var body: some View {
		VStack(spacing: 10) {
			PosterImage(urlString: posterURL, systemPlaceholder: placeholder)
				.frame(width: 132, height: 198)
				.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
				.shadow(color: .black.opacity(0.45), radius: 22, y: 12)
				.padding(.top, 6)
				.accessibilityHidden(true)
			VStack(spacing: 2) {
				Text(title)
					.font(.system(size: 30, weight: .bold))
					.foregroundStyle(.white)
					.multilineTextAlignment(.center)
					.accessibilityAddTraits(.isHeader)
				if let subtitle {
					Text(subtitle)
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(.white.opacity(0.8))
				}
			}
			.padding(.top, 6)
			PageMetaLine(voteAverage: voteAverage, parts: metaParts)
		}
		.frame(maxWidth: .infinity)
	}
}

/// Your rating: the verdict, its stars and when, Edit, the private note, and a
/// placeholder for sharing it with friends.
struct PageVerdictCard: View {
	let rating: Rating?
	let stars: Double?
	let dateLine: String?
	let note: String
	var noteLabel = "Private note"
	let onEdit: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 8) {
				VerdictChip(rating: rating)
				if let stars { StarsLabel(value: stars) }
				if let dateLine {
					Text(dateLine)
						.font(.system(size: 12, weight: .medium))
						.foregroundStyle(.white.opacity(0.6))
						.lineLimit(1)
						.minimumScaleFactor(0.85)
				}
				Spacer(minLength: 4)
				Button("Edit", action: onEdit)
					.font(.system(size: 13, weight: .semibold))
					.foregroundStyle(.white)
			}
			if !note.isEmpty {
				Text(note)
					.font(.system(size: 14))
					.foregroundStyle(.white.opacity(0.9))
					.fixedSize(horizontal: false, vertical: true)
			}
			HStack {
				Label(noteLabel, systemImage: "lock.fill")
					.font(.system(size: 11, weight: .medium))
					.foregroundStyle(.white.opacity(0.55))
				Spacer()
				PlaceholderTag(label: "Share with friends")
			}
		}
		.padding(14)
		.liquidCard(cornerRadius: 20)
	}
}

// MARK: - Details

/// A Details card row: an icon in a circle, a small-caps label and its value.
struct PageDetailRow<Value: View>: View {
	let label: String
	let icon: String
	@ViewBuilder let value: Value

	var body: some View {
		HStack(spacing: 12) {
			Image(systemName: icon)
				.font(.system(size: 13, weight: .semibold))
				.foregroundStyle(.white.opacity(0.7))
				.frame(width: 32, height: 32)
				.background(.white.opacity(0.08), in: Circle())
			VStack(alignment: .leading, spacing: 3) {
				PageSmallCaps(text: label)
				value
			}
			Spacer(minLength: 0)
		}
		.padding(.vertical, 8)
	}
}

extension PageDetailRow where Value == PageDetailValue {
	init(_ label: String, icon: String, text: String) {
		self.init(label: label, icon: icon) { PageDetailValue(text: text) }
	}
}

struct PageDetailValue: View {
	let text: String

	var body: some View {
		Text(text)
			.font(.system(size: 14, weight: .semibold))
			.foregroundStyle(.white)
	}
}

/// The hairline between rows, set in past a row's leading icon or artwork.
struct PageRowDivider: View {
	var inset: CGFloat = 44

	var body: some View {
		Rectangle()
			.fill(.white.opacity(0.08))
			.frame(height: 1)
			.padding(.leading, inset)
	}
}
