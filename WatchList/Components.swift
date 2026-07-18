//
//  Components.swift
//  WatchList
//
//  Shared Liquid Glass building blocks: stat chips, poster cards, list rows,
//  trivia & spec sections.
//

import SwiftUI

// MARK: - Stat chip

struct StatChip: View {
	let label: String
	let value: String
	let systemImage: String
	let tint: Color

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 5) {
				Image(systemName: systemImage).font(.system(size: 12, weight: .bold))
				Text(label).font(.system(size: 12, weight: .semibold, design: .rounded))
			}
			.foregroundStyle(tint)
			Text(value)
				.font(.system(size: 26, weight: .bold, design: .serif))
				.foregroundStyle(.primary)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.vertical, 14)
		.padding(.horizontal, 16)
		.glass(cornerRadius: 18)
	}
}

// MARK: - Poster grid card

struct PosterCard: View {
	let title: String
	let subtitle: String
	let posterURL: String
	let status: WatchStatus
	var rating: Rating? = nil
	var placeholder: String = "film"

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			PosterImage(urlString: posterURL, systemPlaceholder: placeholder)
				.aspectRatio(2.0/3.0, contentMode: .fit)
				.clipShape(RoundedRectangle(cornerRadius: Glass.corner, style: .continuous))
				.overlay(alignment: .topTrailing) {
					StatusBadge(status: status, compact: true)
						.padding(8)
				}
				.overlay(alignment: .topLeading) {
					if let rating {
						RatingBadge(rating: rating, compact: true)
							.padding(8)
					}
				}

			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(.system(size: 15, weight: .bold, design: .serif))
					.foregroundStyle(.primary)
					.lineLimit(1)
				Text(subtitle)
					.font(.system(size: 12, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal, 10)
			.padding(.top, 9)
			.padding(.bottom, 11)
		}
		.glass(cornerRadius: Glass.corner)
	}
}

// MARK: - Generic glass list row (seasons, episodes, search)

struct GlassRow: View {
	let title: String
	let subtitle: String
	var thumbURL: String = ""
	var thumbPlaceholder: String = "film"
	var status: WatchStatus? = nil
	var rating: Rating? = nil
	var leadingNumber: Int? = nil
	var showsChevron: Bool = true

	var body: some View {
		HStack(spacing: 12) {
			if let n = leadingNumber {
				Text("\(n)")
					.font(.system(size: 17, weight: .bold, design: .rounded))
					.foregroundStyle(Glass.accent)
					.frame(width: 34, height: 34)
					.background(Glass.accent.opacity(0.14), in: Circle())
			} else if !thumbURL.isEmpty {
				PosterImage(urlString: thumbURL, systemPlaceholder: thumbPlaceholder)
					.frame(width: 54, height: 76)
					.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
			}

			VStack(alignment: .leading, spacing: 3) {
				Text(title)
					.font(.system(size: 16, weight: .semibold, design: .rounded))
					.foregroundStyle(.primary)
					.lineLimit(2)
				if !subtitle.isEmpty {
					Text(subtitle)
						.font(.system(size: 13, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
						.lineLimit(2)
				}
			}
			Spacer(minLength: 6)

			if let rating { RatingBadge(rating: rating, compact: true) }
			if let status { StatusBadge(status: status, compact: true) }
			if showsChevron {
				Image(systemName: "chevron.right")
					.font(.system(size: 13, weight: .bold))
					.foregroundStyle(.tertiary)
			}
		}
		.padding(.vertical, 11)
		.padding(.horizontal, 14)
		.glass(cornerRadius: 18)
	}
}

// MARK: - Status picker (segmented glass)

struct StatusPicker: View {
	@Binding var status: WatchStatus
	var body: some View {
		HStack(spacing: 8) {
			ForEach(WatchStatus.allCases) { s in
				let selected = status == s
				Button {
					Haptics.selection()
					withAnimation(Glass.pop) { status = s }
				} label: {
					HStack(spacing: 5) {
						Image(systemName: s.systemImage).font(.system(size: 12, weight: .bold))
						Text(s.rawValue).font(.system(size: 13, weight: .semibold, design: .rounded))
					}
					.foregroundStyle(selected ? .white : Color.primary)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 11)
					.background {
						if selected {
							Capsule().fill(Glass.tint(s))
						} else {
							Capsule().fill(.ultraThinMaterial)
						}
					}
				}
				.buttonStyle(.pressable)
			}
		}
	}
}

// MARK: - Rating picker (2×2 glass grid, clearable)

struct RatingPicker: View {
	@Binding var rating: Rating?
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass

	private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			if horizontalSizeClass == .regular {
				// iPad: a 2×2 grid fits the narrow two-column side column.
				LazyVGrid(columns: columns, spacing: 8) {
					ForEach(Rating.allCases) { chip($0, expands: true) }
				}
			} else {
				// iPhone: a single horizontal scrollable row.
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 8) {
						ForEach(Rating.allCases) { chip($0, expands: false) }
					}
					.padding(.vertical, 2)
				}
			}
			if rating != nil {
				Text("Tap the selected rating again to clear it.")
					.font(.system(size: 11, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
			}
		}
	}

	private func chip(_ r: Rating, expands: Bool) -> some View {
		let selected = rating == r
		return Button {
			Haptics.selection()
			withAnimation(Glass.pop) { rating = selected ? nil : r }
		} label: {
			HStack(spacing: 6) {
				Image(systemName: r.systemImage).font(.system(size: 12, weight: .bold))
				Text(r.rawValue).font(.system(size: 13, weight: .semibold, design: .rounded))
			}
			.foregroundStyle(selected ? .white : Color.primary)
			.frame(maxWidth: expands ? .infinity : nil)
			.padding(.horizontal, expands ? 0 : 16)
			.padding(.vertical, 11)
			.background {
				if selected {
					Capsule().fill(Glass.tint(r))
				} else {
					Capsule().fill(.ultraThinMaterial)
				}
			}
		}
		.buttonStyle(.pressable)
	}
}

// MARK: - Trivia section

struct TriviaSection: View {
	let trivia: [String]
	let isLoading: Bool
	let hasIMDb: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "Trivia", systemImage: "lightbulb.fill")
			if isLoading {
				HStack(spacing: 10) {
					ProgressView()
					Text("Pulling trivia from IMDb…")
						.font(.system(size: 14, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(16)
				.glass(cornerRadius: 18)
			} else if trivia.isEmpty {
				Text(hasIMDb
				     ? "No trivia found on IMDb for this title."
				     : "Add an IMDb link to pull trivia for this title.")
					.font(.system(size: 14, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(16)
					.glass(cornerRadius: 18)
			} else {
				VStack(alignment: .leading, spacing: 10) {
					ForEach(Array(trivia.enumerated()), id: \.offset) { _, fact in
						HStack(alignment: .top, spacing: 10) {
							Image(systemName: "sparkle")
								.font(.system(size: 12, weight: .bold))
								.foregroundStyle(Glass.accent3)
								.padding(.top, 3)
							Text(fact)
								.font(.system(size: 14, weight: .regular, design: .rounded))
								.foregroundStyle(.primary)
								.fixedSize(horizontal: false, vertical: true)
						}
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(16)
				.glass(cornerRadius: 18)
			}
		}
	}
}

// MARK: - Technical specs section

struct SpecsSection: View {
	let specs: TechSpecs?

	private var rows: [(String, String)] {
		guard let s = specs else { return [] }
		var r: [(String, String)] = []
		if let rt = s.runtimeMinutes { r.append(("Runtime", "\(rt) min")) }
		if let d = s.releaseDate, !d.isEmpty { r.append(("Release date", d)) }
		if let st = s.status, !st.isEmpty { r.append(("Status", st)) }
		if let lang = s.originalLanguage, !lang.isEmpty { r.append(("Original language", lang.uppercased())) }
		if !s.spokenLanguages.isEmpty { r.append(("Spoken languages", s.spokenLanguages.joined(separator: ", "))) }
		if !s.productionCountries.isEmpty { r.append(("Countries", s.productionCountries.joined(separator: ", "))) }
		if !s.productionCompanies.isEmpty { r.append(("Production", s.productionCompanies.prefix(3).joined(separator: ", "))) }
		if let b = s.budget { r.append(("Budget", currency(b))) }
		if let rev = s.revenue { r.append(("Revenue", currency(rev))) }
		if let v = s.voteAverage, v > 0 { r.append(("TMDb rating", String(format: "%.1f / 10", v))) }
		if let code = s.productionCode, !code.isEmpty { r.append(("Production code", code)) }
		return r
	}

	private func currency(_ n: Int) -> String {
		let f = NumberFormatter()
		f.numberStyle = .currency
		f.currencyCode = "USD"
		f.maximumFractionDigits = 0
		return f.string(from: NSNumber(value: n)) ?? "$\(n)"
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "Technical Specs", systemImage: "gearshape.fill")
			if rows.isEmpty {
				Text("No technical specs available.")
					.font(.system(size: 14, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(16)
					.glass(cornerRadius: 18)
			} else {
				VStack(spacing: 0) {
					ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
						HStack(alignment: .top) {
							Text(row.0)
								.font(.system(size: 14, weight: .semibold, design: .rounded))
								.foregroundStyle(.secondary)
							Spacer(minLength: 16)
							Text(row.1)
								.font(.system(size: 14, weight: .medium, design: .rounded))
								.foregroundStyle(.primary)
								.multilineTextAlignment(.trailing)
						}
						.padding(.vertical, 11)
						if idx < rows.count - 1 { Divider().opacity(0.4) }
					}
				}
				.padding(.horizontal, 16)
				.glass(cornerRadius: 18)
			}
		}
	}
}

// MARK: - Synopsis section

struct SynopsisSection: View {
	let text: String
	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "Synopsis", systemImage: "text.alignleft")
			Text(text.isEmpty ? "No synopsis available." : text)
				.font(.system(size: 15, weight: .regular, design: .rounded))
				.foregroundStyle(text.isEmpty ? .secondary : .primary)
				.fixedSize(horizontal: false, vertical: true)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(16)
				.glass(cornerRadius: 18)
		}
	}
}
