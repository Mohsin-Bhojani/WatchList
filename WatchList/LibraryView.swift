//
//  LibraryView.swift
//  WatchList
//
//  Home screen. Splits the library into Shows and Films via an editorial
//  underline tab control, with status stats and a poster grid.
//
//  Bottom dock (iPhone-style): one floating capsule holding Stats, the accented
//  Add (+) button and Settings, then a hairline and Search on the right.
//  Settings opens this app's page in the iOS Settings app, where preferences
//  are stored (see Settings.bundle).
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
				// away smoothly instead of appearing sharply under the dock. The
				// gradient reaches solid paper just above the dock and holds it all
				// the way to the bottom bezel, so nothing shows through behind it.
				LinearGradient(
					stops: [
						.init(color: .clear, location: 0),
						.init(color: Glass.paper, location: 0.45),
						.init(color: Glass.paper, location: 1),
					],
					startPoint: .top, endPoint: .bottom
				)
					.frame(maxWidth: .infinity)
					.frame(height: 100)
					.allowsHitTesting(false)
					// ignoresSafeArea alone leaves the home-indicator strip uncovered
					// here, so pull the gradient past the bezel explicitly. The bottom
					// half is solid paper, so overshooting costs nothing.
					.padding(.bottom, -50)
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
				.sheet(isPresented: $showingSettings) { SettingsView() }
				// Shows gain seasons after they're added; top them up quietly
				// at most once a day. Additive only, so there's nothing to
				// interrupt the user about.
				.task {
					guard LibraryRefresher.autoCheckIsDue else { return }
					_ = await LibraryRefresher.refreshAll(shows: shows, into: ctx)
				}
		}
	}

	// MARK: Bottom dock — [Stats · + · Settings | Search]

	/// A single floating capsule in the iPhone dock idiom: the action group on
	/// the left (Stats, the accented Add button, Settings), a hairline, then
	/// Search on the right. Sits low, just clear of the home indicator.
	private func dock() -> some View {
		HStack(spacing: 0) {
			dockButton("chart.bar.fill", "Stats") { Haptics.tap(); showingStats = true }
			dockButton("plus", "Add", filled: true) { Haptics.tap(.medium); showingAdd = true }
			dockButton("gearshape.fill", "Settings") { Haptics.tap(); showingSettings = true }

			Rectangle()
				.fill(Glass.hairline.opacity(0.14))
				.frame(width: 1, height: 28)
				.padding(.horizontal, 4)

			dockButton("magnifyingglass", "Search") { Haptics.tap(); showingSearch = true }
		}
		.padding(.horizontal, 10)
		.frame(height: 62)
		.background(
			Capsule()
				.fill(Glass.surface)
				.overlay(Capsule().strokeBorder(Glass.hairline.opacity(0.12), lineWidth: 1))
				.shadow(color: .black.opacity(0.10), radius: 12, y: 4)
		)
		// Ride lower, into the bottom safe area but clear of the home indicator.
		.padding(.bottom, -12)
	}

	/// One dock item. `filled` draws the primary action (+) as an accent disc so
	/// it still leads the row now that it sits inline instead of in a notch.
	private func dockButton(_ icon: String, _ label: String,
	                        filled: Bool = false,
	                        _ action: @escaping () -> Void) -> some View {
		Button(action: action) {
			VStack(spacing: 4) {
				Image(systemName: icon)
					.font(.system(size: filled ? 17 : 18, weight: filled ? .bold : .semibold))
					.foregroundStyle(filled ? Color.white : Color.primary.opacity(0.55))
					.frame(width: 32, height: 32)
					.background { if filled { Circle().fill(Glass.accent) } }
				Text(label)
					.font(.system(size: 10, weight: .semibold, design: .rounded))
					.foregroundStyle(filled ? Glass.accent : Color.secondary)
			}
			.frame(width: 58)
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
