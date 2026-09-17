//
//  PhoneShowsView.swift
//  WatchList
//
//  The iPhone Shows tab: your TV shows and films, browsed Library-style — a
//  poster grid, each poster fading into a strip of its verdict's colour and
//  opening its page. Tapping Shows again once the grid is at its top opens
//  Filter & Sort: type and status as segmented controls, the order as segments
//  that reverse when the chosen one is tapped again, and genres as tiles, any
//  number picked. The header names the type, and a line under it says what else
//  is set.
//

import SwiftUI
import SwiftData

struct PhoneShowsView: View {
	/// Whether the grid is on screen at its top, for the tab bar to read.
	@Binding var atTop: Bool
	@Binding var showingFilters: Bool

	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Query(sort: \Show.dateAdded, order: .reverse) private var shows: [Show]
	@Query(sort: \Film.dateAdded, order: .reverse) private var films: [Film]

	@State private var kind: BrowseKind = .all
	@State private var status: StatusFilter = .all
	@State private var pickedGenres: Set<String> = []
	@State private var order = BrowseOrder()

	/// Two columns, or as many poster-sized ones as fit in a landscape Plus/Max.
	private var columns: [GridItem] {
		if horizontalSizeClass == .regular {
			return [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 16)]
		}
		return [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]
	}

	private var availableGenres: [String] {
		BrowseFilter.genres(in: (kind.includesShows ? shows.map(\.genre) : [])
			+ (kind.includesFilms ? films.map(\.genre) : []))
	}

	/// What passes the filters, in the chosen order — shows and films
	/// interleaved when both are listed.
	private var displayed: [WatchedTitle] {
		let listed = (kind.includesShows ? shows.map(WatchedTitle.show) : [])
			+ (kind.includesFilms ? films.map(WatchedTitle.film) : [])
		let matching = listed.filter {
			BrowseFilter.matches(status: $0.status, genres: $0.genre, statusFilter: status, picked: pickedGenres)
		}
		return BrowseFilter.sorted(matching, by: order)
	}

	private var nothingOfThisKind: Bool {
		(!kind.includesShows || shows.isEmpty) && (!kind.includesFilms || films.isEmpty)
	}

	/// The status, genres and order, while any of them isn't the default.
	private var filterSummary: String? {
		var parts: [String] = []
		if status != .all { parts.append(status.title) }
		switch pickedGenres.count {
		case 0:    break
		case 1, 2: parts.append(pickedGenres.sorted().joined(separator: ", "))
		default:   parts.append("\(pickedGenres.count) genres")
		}
		if order != BrowseOrder() { parts.append(order.summary) }
		return parts.isEmpty ? nil : parts.joined(separator: " · ")
	}

	var body: some View {
		NavigationStack {
			ZStack {
				GlassBackground()
				ScrollView {
					VStack(alignment: .leading, spacing: 14) {
						ScreenHeader(title: kind.title)
						if let filterSummary {
							FilterSummaryButton(summary: filterSummary) { showingFilters = true }
								.padding(.horizontal, 20)
						}
						grid
							.padding(.horizontal, 20)
							.padding(.top, 4)
					}
					.padding(.bottom, 18)
				}
				.reportsListAtTop($atTop)
			}
			.screenBar(kind.title)
			// Genres the new type doesn't have would hide everything.
			.onChange(of: kind) { pickedGenres.formIntersection(availableGenres) }
			.sheet(isPresented: $showingFilters) { filterSheet }
		}
	}

	private var filterSheet: some View {
		FilterSheet(title: "Filter & Sort",
		            canReset: kind != .all || status != .all || !pickedGenres.isEmpty || order != BrowseOrder()) {
			kind = .all
			status = .all
			pickedGenres = []
			order = BrowseOrder()
		} content: {
			SegmentedFilter(title: "Type", options: BrowseKind.allCases, selection: $kind) { $0.label }
			SegmentedFilter(title: "Status", options: StatusFilter.allCases, selection: $status) { $0.title }
			SortSegments(title: "Sort", order: $order)
			let genres = availableGenres
			if !genres.isEmpty {
				TileFilter(title: "Genre", options: genres, picked: $pickedGenres)
			}
		}
	}

	// MARK: Grid

	@ViewBuilder private var grid: some View {
		let items = displayed
		if nothingOfThisKind {
			EmptyState(icon: kind.systemImage,
			           title: kind == .films ? "No films yet" : kind == .shows ? "No TV shows yet" : "Nothing here yet",
			           subtitle: "Open Search to find a title on TMDb, paste a link or add one manually.")
				.padding(.top, 30)
		} else if items.isEmpty {
			EmptyState(icon: "line.3.horizontal.decrease.circle", title: "No matches",
			           subtitle: "Nothing fits these filters. Try another status or genre.")
				.padding(.top, 30)
		} else {
			LazyVGrid(columns: columns, spacing: 16) {
				ForEach(items) { item in
					NavigationLink { item.destination } label: {
						FadedPosterCard(item: item)
					}
					.buttonStyle(.pressable)
				}
			}
		}
	}
}
