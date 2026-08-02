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
	var episodeTier: EpisodeTier? = nil
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

			if let episodeTier { EpisodeTierBadge(tier: episodeTier, compact: true) }
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

// MARK: - Detail page tabs

/// The tabs a detail page can show. An Episode's cast tab is labelled
/// "In this episode", so the title travels with the item rather than the case.
enum DetailTab: Hashable {
	case details, cast, similar
}

struct DetailTabItem: Identifiable {
	let tab: DetailTab
	let title: String
	var id: DetailTab { tab }
}

/// The underline tab bar that sits directly below the status and rating rows on
/// Show, Season and Episode pages. Hairline under the whole row; the selected
/// tab gets a Classic Red underline and full-ink text.
struct DetailTabBar: View {
	let items: [DetailTabItem]
	@Binding var selection: DetailTab

	var body: some View {
		HStack(alignment: .bottom, spacing: 22) {
			ForEach(items) { item in
				let active = item.tab == selection
				Button {
					Haptics.selection()
					withAnimation(Glass.pop) { selection = item.tab }
				} label: {
					Text(item.title)
						.font(Glass.serif(15, .semibold))
						.foregroundStyle(active ? Color.primary : Color.secondary)
						.padding(.bottom, 9)
						.overlay(alignment: .bottom) {
							Rectangle()
								.fill(active ? Glass.accent : Color.clear)
								.frame(height: 2.5)
						}
						.contentShape(Rectangle())
				}
				.buttonStyle(.plain)
				.accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
			}
			Spacer(minLength: 0)
		}
		// Behind the row, so the selected tab's underline sits on top of it.
		.background(alignment: .bottom) {
			Rectangle()
				.fill(Glass.hairline.opacity(0.16))
				.frame(height: 1)
		}
	}
}

// MARK: - Cast row

/// A circular headshot, falling back to the person's initials on the muted
/// paper tone when TMDb has no profile image.
struct PersonAvatar: View {
	let urlString: String
	let name: String

	private var initials: String {
		let words = name.split(separator: " ").prefix(2)
		return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
	}

	var body: some View {
		Group {
			if urlString.isEmpty {
				ZStack {
					Rectangle().fill(Glass.hairline.opacity(0.06))
					Text(initials)
						.font(.system(size: 15, weight: .semibold, design: .serif))
						.foregroundStyle(Glass.accent3)
				}
			} else {
				PosterImage(urlString: urlString, systemPlaceholder: "person.fill")
			}
		}
		.clipShape(Circle())
	}
}

/// One person in a Cast tab: headshot, name, character (or the ochre flag that
/// replaces it) and an episode count. No chevron — there is nowhere to go.
struct CastRow: View {
	let entry: CastEntry

	var body: some View {
		HStack(spacing: 12) {
			PersonAvatar(urlString: entry.profileURL, name: entry.name)
				.frame(width: 44, height: 44)
				.overlay {
					if entry.flag != .none {
						Circle().strokeBorder(Glass.toWatch.opacity(0.55), lineWidth: 2)
					}
				}

			VStack(alignment: .leading, spacing: 3) {
				Text(entry.name)
					.font(.system(size: 16, weight: .semibold, design: .rounded))
					.foregroundStyle(.primary)
					.lineLimit(1)
				if let flag = entry.flag.label {
					Text(flag)
						.font(.system(size: 13, weight: .semibold, design: .rounded))
						.foregroundStyle(Glass.toWatch)
						.lineLimit(1)
				} else if !entry.character.isEmpty {
					Text(entry.character)
						.font(.system(size: 13, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}
			}
			Spacer(minLength: 6)

			if let count = entry.episodeCount, count > 0 {
				Text("\(count) ep")
					.font(.system(size: 13, weight: .medium, design: .rounded))
					.foregroundStyle(.tertiary)
			}
		}
		.padding(.vertical, 11)
		.padding(.horizontal, 14)
		.glass(cornerRadius: 18)
	}
}

// MARK: - Similar row

/// One title in a Similar tab. There is no match percentage here on purpose:
/// TMDb doesn't return one, so the row shows its vote average and the genres it
/// shares with the title you came from.
struct SimilarRow: View {
	let entry: SimilarEntry
	let inLibrary: Bool
	let isAdding: Bool
	let onAdd: () -> Void

	var body: some View {
		HStack(spacing: 12) {
			PosterImage(urlString: entry.posterURL, systemPlaceholder: "tv")
				.frame(width: 44, height: 62)
				.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

			VStack(alignment: .leading, spacing: 3) {
				Text(entry.title)
					.font(.system(size: 16, weight: .semibold, design: .rounded))
					.foregroundStyle(.primary)
					.lineLimit(2)
				meta
				if inLibrary {
					HStack(spacing: 4) {
						Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
						Text("In your library")
					}
					.font(.system(size: 12, weight: .semibold, design: .rounded))
					.foregroundStyle(Glass.watched)
				} else if !entry.sharedGenres.isEmpty {
					Text("Also \(entry.sharedGenres.joined(separator: ", "))")
						.font(.system(size: 12, weight: .medium, design: .rounded))
						.foregroundStyle(.tertiary)
						.lineLimit(1)
				}
			}
			Spacer(minLength: 6)
			addControl
		}
		.padding(.vertical, 11)
		.padding(.horizontal, 14)
		.glass(cornerRadius: 18)
	}

	@ViewBuilder private var meta: some View {
		HStack(spacing: 5) {
			if !entry.year.isEmpty { Text(entry.year) }
			if !entry.year.isEmpty && entry.voteAverage > 0 { Text("·") }
			if entry.voteAverage > 0 {
				HStack(spacing: 3) {
					Image(systemName: "star.fill").font(.system(size: 10, weight: .bold))
					Text(String(format: "%.1f", entry.voteAverage))
				}
			}
		}
		.font(.system(size: 13, weight: .medium, design: .rounded))
		.foregroundStyle(.secondary)
	}

	@ViewBuilder private var addControl: some View {
		if isAdding {
			ProgressView().frame(width: 34, height: 34)
		} else if inLibrary {
			Image(systemName: "checkmark")
				.font(.system(size: 15, weight: .bold))
				.foregroundStyle(Glass.watched)
				.frame(width: 34, height: 34)
				.background(Circle().fill(Glass.watched.opacity(0.14)))
				.accessibilityLabel("Already in your library")
		} else {
			Button(action: onAdd) {
				Image(systemName: "plus")
					.font(.system(size: 15, weight: .bold))
					.foregroundStyle(.white)
					.frame(width: 34, height: 34)
					.background(Circle().fill(Glass.toWatch))
			}
			.buttonStyle(.pressable)
			.accessibilityLabel("Add \(entry.title) to your library")
		}
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

// MARK: - Episode rewatch-tier picker (Skip · Watch · Rewatch)

struct EpisodeTierPicker: View {
	@Binding var tier: EpisodeTier?

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 8) {
				ForEach(EpisodeTier.allCases) { t in
					let selected = tier == t
					Button {
						Haptics.selection()
						withAnimation(Glass.pop) { tier = selected ? nil : t }
					} label: {
						HStack(spacing: 6) {
							Image(systemName: t.systemImage).font(.system(size: 12, weight: .bold))
							Text(t.rawValue).font(.system(size: 13, weight: .semibold, design: .rounded))
						}
						.foregroundStyle(selected ? .white : Color.primary)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 11)
						.background {
							if selected {
								Capsule().fill(Glass.tint(t))
							} else {
								Capsule().fill(.ultraThinMaterial)
							}
						}
					}
					.buttonStyle(.pressable)
				}
			}
			if tier != nil {
				Text("Tap the selected one again to clear it.")
					.font(.system(size: 11, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
			}
		}
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
				SpecRowsCard(rows: rows)
			}
		}
	}
}

/// The label / value card behind Technical Specs — also used for an episode's
/// Directed by / Written by pair.
struct SpecRowsCard: View {
	let rows: [(String, String)]

	var body: some View {
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
