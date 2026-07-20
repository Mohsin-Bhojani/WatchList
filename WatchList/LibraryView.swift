//
//  LibraryView.swift
//  WatchList
//
//  Home screen. Splits the library into Shows and Films via an editorial
//  underline tab control, with status stats and a poster grid.
//
//  Bottom dock (Mail-style): a Library/home button on the left, a Search bar in
//  the middle, and an Add (+) button on the right. Stats and Settings live in
//  the top navigation bar; Settings opens this app's page in the iOS Settings
//  app, where preferences are stored (see Settings.bundle).
//

import SwiftUI
import SwiftData
import UIKit

/// Sort order for the poster grid. WatchList has no personal rating field, so
/// the options lean on what's actually on the model: added date, title, year, status.
enum LibrarySortOption: String, CaseIterable, Identifiable {
	case dateAdded = "Recently Added"
	case titleAZ = "Title A–Z"
	case year = "Year"
	case status = "Status"
	case rating = "Rating"
	var id: String { rawValue }
	var systemImage: String {
		switch self {
		case .dateAdded: return "clock"
		case .titleAZ: return "textformat"
		case .year: return "calendar"
		case .status: return "checklist"
		case .rating: return "star"
		}
	}
}

struct LibraryView: View {
	@Environment(\.modelContext) private var ctx
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Query(sort: \Show.dateAdded, order: .reverse) private var shows: [Show]
	@Query(sort: \Film.dateAdded, order: .reverse) private var films: [Film]

	@State private var kind: MediaKind = .show
	@State private var showingAdd = false
	@State private var showingSearch = false
	@State private var showingStats = false
	@State private var showingNearby = false
	@State private var showingSettings = false
	@State private var sortOption: LibrarySortOption = .dateAdded
	@State private var genreFilter: String? = nil

	/// iPhone keeps two fixed columns; iPad (regular width) fits as many
	/// poster-sized columns as the width allows so posters don't blow up.
	private var columns: [GridItem] {
		if horizontalSizeClass == .regular {
			return [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)]
		}
		return [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
	}

	// Status tallies across the current segment.
	private var toWatch: Int {
		kind == .show ? shows.filter { $0.status == .toWatch }.count : films.filter { $0.status == .toWatch }.count
	}
	private var watching: Int {
		kind == .show ? shows.filter { $0.status == .watching }.count : films.filter { $0.status == .watching }.count
	}
	private var watched: Int {
		kind == .show ? shows.filter { $0.status == .watched }.count : films.filter { $0.status == .watched }.count
	}

	// MARK: Genre filter + sort (derived, since @Query only sorts by date)

	/// Distinct genre tokens for the current segment ("Action, Drama" -> both).
	private var genres: [String] {
		let source = kind == .show ? shows.map(\.genre) : films.map(\.genre)
		let tokens = source
			.flatMap { $0.components(separatedBy: ",") }
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
		return Array(Set(tokens)).sorted()
	}

	private func sortedAndFiltered<T>(
		_ items: [T],
		genre: (T) -> String,
		title: (T) -> String,
		dateAdded: (T) -> Date,
		year: (T) -> String,
		status: (T) -> WatchStatus,
		rating: (T) -> Rating?
	) -> [T] {
		let filtered: [T]
		if let genreFilter {
			filtered = items.filter { genre($0).localizedCaseInsensitiveContains(genreFilter) }
		} else {
			filtered = items
		}
		switch sortOption {
		case .dateAdded:
			return filtered.sorted { dateAdded($0) > dateAdded($1) }
		case .titleAZ:
			return filtered.sorted { title($0).localizedCaseInsensitiveCompare(title($1)) == .orderedAscending }
		case .year:
			return filtered.sorted { year($0) > year($1) }
		case .status:
			return filtered.sorted { status($0).sortRank < status($1).sortRank }
		case .rating:
			// Best rating first; unrated titles fall to the end, then A–Z.
			return filtered.sorted { a, b in
				let ra = rating(a)?.sortRank ?? Int.max
				let rb = rating(b)?.sortRank ?? Int.max
				if ra != rb { return ra < rb }
				return title(a).localizedCaseInsensitiveCompare(title(b)) == .orderedAscending
			}
		}
	}

	private var displayedShows: [Show] {
		sortedAndFiltered(shows, genre: \.genre, title: \.title, dateAdded: \.dateAdded,
		                   year: \.firstAirYear, status: \.status, rating: \.rating)
	}
	private var displayedFilms: [Film] {
		sortedAndFiltered(films, genre: \.genre, title: \.title, dateAdded: \.dateAdded,
		                   year: \.year, status: \.status, rating: \.rating)
	}

	var body: some View {
		NavigationStack {
			ZStack(alignment: .bottom) {
				GlassBackground()

				ScrollView {
					VStack(spacing: 18) {
						segmented
						statsRow
						genreFilterRow
						grid
						Color.clear.frame(height: 96)
					}
					.padding(.horizontal, 18)
					.padding(.top, 6)
				}

				// Fade the content into the paper behind the bar so it scrolls
				// away smoothly instead of appearing sharply under the dock.
				LinearGradient(colors: [.clear, Glass.paper], startPoint: .top, endPoint: .bottom)
					.frame(maxWidth: .infinity)
					.frame(height: 130)
					.allowsHitTesting(false)
					.ignoresSafeArea(edges: .bottom)

				dock()
			}
			.navigationTitle("WatchList")
				.toolbarBackground(.hidden, for: .navigationBar)
				.toolbar {
					ToolbarItem(placement: .topBarTrailing) {
						HStack(spacing: 2) {
							Menu {
								ForEach(LibrarySortOption.allCases) { option in
									Button {
										Haptics.selection()
										withAnimation(Glass.pop) { sortOption = option }
									} label: {
										Label(option.rawValue, systemImage: option.systemImage)
										if sortOption == option { Image(systemName: "checkmark") }
									}
								}
							} label: {
								Image(systemName: "arrow.up.arrow.down.circle.fill")
							}
						}
						.font(.system(size: 17, weight: .semibold))
						.foregroundStyle(Glass.accent)
					}
				}
				.sheet(isPresented: $showingAdd) { AddEntryView() }
				.sheet(isPresented: $showingSearch) { SearchView() }
				.sheet(isPresented: $showingStats) { StatsView() }
				.sheet(isPresented: $showingNearby) { NearbyView() }
				.sheet(isPresented: $showingSettings) { SettingsView() }
		}
	}

	// MARK: Bottom tab bar (Search · Stats · [+] · Nearby · Settings)

	private func dock() -> some View {
		ZStack {
			HStack(spacing: 0) {
				tabButton("magnifyingglass", "Search") { Haptics.tap(); showingSearch = true }
				tabButton("chart.bar.fill", "Stats") { Haptics.tap(); showingStats = true }
				Color.clear.frame(width: 84)
				tabButton("person.2.fill", "Nearby") { Haptics.tap(); showingNearby = true }
				tabButton("gearshape.fill", "Settings") { Haptics.tap(); showingSettings = true }
			}
			.padding(.horizontal, 12)
			.frame(height: 62)
			.frame(maxWidth: .infinity)

			// Raised center Add button, cradled by the notch.
			Button {
				Haptics.tap(.medium); showingAdd = true
			} label: {
				Image(systemName: "plus")
					.font(.system(size: 26, weight: .bold))
					.foregroundStyle(.white)
					.frame(width: 58, height: 58)
					.background(Circle().fill(Glass.accent))
					.shadow(color: Glass.accent.opacity(0.35), radius: 8, y: 3)
			}
			.buttonStyle(.pressable)
			.offset(y: -26)
		}
		.background(
			NotchedBar(cornerRadius: 26, notchRadius: 38)
				.fill(Glass.surface)
				.overlay(
					NotchedBar(cornerRadius: 26, notchRadius: 38)
						.stroke(Glass.hairline.opacity(0.12), lineWidth: 1)
				)
				.shadow(color: .black.opacity(0.08), radius: 12, y: -3)
				.ignoresSafeArea(edges: .bottom)
		)
	}

	private func tabButton(_ icon: String, _ label: String, _ action: @escaping () -> Void) -> some View {
		Button(action: action) {
			VStack(spacing: 3) {
				Image(systemName: icon).font(.system(size: 18, weight: .semibold))
				Text(label).font(.system(size: 10, weight: .semibold, design: .rounded))
			}
			.foregroundStyle(.secondary)
			.frame(maxWidth: .infinity)
			.contentShape(Rectangle())
		}
		.buttonStyle(.pressable)
	}

	// MARK: Segmented control (editorial underline tabs)

	private var segmented: some View {
		VStack(spacing: 10) {
			HStack(spacing: 26) {
				ForEach(MediaKind.allCases) { k in
					let selected = kind == k
					Button {
						Haptics.selection()
						withAnimation(Glass.pop) { kind = k; genreFilter = nil }
					} label: {
						VStack(spacing: 7) {
							Text(k == .show ? "Shows" : "Films")
								.font(.system(size: 19, weight: selected ? .bold : .regular, design: .serif))
								.foregroundStyle(selected ? Glass.accent : Color.primary.opacity(0.5))
							Capsule()
								.fill(selected ? Glass.accent : Color.clear)
								.frame(width: 26, height: 2)
						}
					}
					.buttonStyle(.pressable)
				}
				Spacer()
			}
			Rectangle()
				.fill(Glass.hairline.opacity(0.16))
				.frame(height: 1)
		}
	}

	// MARK: Stats

	private var statsRow: some View {
		HStack(spacing: 10) {
			StatChip(label: "To Watch", value: "\(toWatch)", systemImage: "bookmark", tint: Glass.toWatch)
			StatChip(label: "Watching", value: "\(watching)", systemImage: "play.circle.fill", tint: Glass.watching)
			StatChip(label: "Watched", value: "\(watched)", systemImage: "checkmark.circle.fill", tint: Glass.watched)
		}
	}

	// MARK: Genre filter chips

	@ViewBuilder private var genreFilterRow: some View {
		if genres.count > 1 {
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 8) {
					genreChip(nil, label: "All")
					ForEach(genres, id: \.self) { g in genreChip(g, label: g) }
				}
				.padding(.vertical, 2)
			}
		}
	}

	private func genreChip(_ value: String?, label: String) -> some View {
		let selected = genreFilter == value
		return Button {
			Haptics.selection()
			withAnimation(Glass.pop) { genreFilter = value }
		} label: {
			Text(label)
				.font(.system(size: 13, weight: .semibold, design: .rounded))
				.foregroundStyle(selected ? .white : Color.primary)
				.padding(.horizontal, 14)
				.padding(.vertical, 8)
				.background {
					if selected { Capsule().fill(Glass.accent) }
					else { Capsule().fill(.ultraThinMaterial) }
				}
				.overlay(Capsule().strokeBorder(Glass.hairline.opacity(selected ? 0 : 0.16), lineWidth: 1))
		}
		.buttonStyle(.pressable)
	}

	// MARK: Grid

	@ViewBuilder private var grid: some View {
		if kind == .show {
			if shows.isEmpty {
				EmptyState(icon: "tv", title: "No shows yet", subtitle: "Tap + to paste an IMDb link or add one manually.")
					.padding(.top, 30)
			} else if displayedShows.isEmpty {
				EmptyState(icon: "line.3.horizontal.decrease.circle", title: "No matches",
				           subtitle: "Nothing in \u{201C}\(genreFilter ?? "")\u{201D}. Try a different genre.")
					.padding(.top, 30)
			} else {
				LazyVGrid(columns: columns, spacing: 16) {
					ForEach(displayedShows) { show in
						NavigationLink { ShowDetailView(show: show) } label: {
							PosterCard(title: show.title, subtitle: show.subtitle,
							           posterURL: show.posterURL, status: show.status,
							           rating: show.rating, placeholder: "tv")
						}
						.buttonStyle(.pressable)
						.contextMenu { deleteButton { ctx.delete(show) } }
					}
				}
			}
		} else {
			if films.isEmpty {
				EmptyState(icon: "film", title: "No films yet", subtitle: "Tap + to paste an IMDb link or add one manually.")
					.padding(.top, 30)
			} else if displayedFilms.isEmpty {
				EmptyState(icon: "line.3.horizontal.decrease.circle", title: "No matches",
				           subtitle: "Nothing in \u{201C}\(genreFilter ?? "")\u{201D}. Try a different genre.")
					.padding(.top, 30)
			} else {
				LazyVGrid(columns: columns, spacing: 16) {
					ForEach(displayedFilms) { film in
						NavigationLink { FilmDetailView(film: film) } label: {
							PosterCard(title: film.title,
							           subtitle: [film.year, film.genre.components(separatedBy: ", ").first ?? ""]
								.filter { !$0.isEmpty }.joined(separator: " · "),
							           posterURL: film.posterURL, status: film.status,
							           rating: film.rating, placeholder: "film")
						}
						.buttonStyle(.pressable)
						.contextMenu { deleteButton { ctx.delete(film) } }
					}
				}
			}
		}
	}

	@ViewBuilder private func deleteButton(_ action: @escaping () -> Void) -> some View {
		Button(role: .destructive) { withAnimation { action() } } label: {
			Label("Delete", systemImage: "trash")
		}
	}
}

// MARK: - Notched bottom-bar shape

/// A filled bottom-bar shape: rounded top corners, a concave semicircular notch
/// centered on the top edge (cradling the raised Add button), and a flat bottom
/// so the bar fills to the screen edge.
struct NotchedBar: Shape {
	var cornerRadius: CGFloat = 26
	var notchRadius: CGFloat = 38

	func path(in rect: CGRect) -> Path {
		let w = rect.width, h = rect.height
		let cr = min(cornerRadius, h)
		let nr = notchRadius
		let cx = rect.midX
		var p = Path()
		p.move(to: CGPoint(x: 0, y: h))                       // bottom-left (square)
		p.addLine(to: CGPoint(x: 0, y: cr))                    // up the left edge
		p.addArc(center: CGPoint(x: cr, y: cr), radius: cr,
		         startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)  // top-left corner
		p.addLine(to: CGPoint(x: cx - nr, y: 0))               // top edge to notch
		p.addArc(center: CGPoint(x: cx, y: 0), radius: nr,
		         startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)      // concave notch (dips in)
		p.addLine(to: CGPoint(x: w - cr, y: 0))                // top edge after notch
		p.addArc(center: CGPoint(x: w - cr, y: cr), radius: cr,
		         startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)     // top-right corner
		p.addLine(to: CGPoint(x: w, y: h))                     // down the right edge
		p.closeSubpath()                                       // flat bottom
		return p
	}
}
