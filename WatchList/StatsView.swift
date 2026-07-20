//
//  StatsView.swift
//  WatchList
//
//  A light overview of the whole library. Shows and Films are combined: Status
//  covers what's left to get through (To Watch / Watching), and Ratings covers
//  everything watched (the four verdicts plus Unrated). Every row is tappable
//  and opens a sheet listing the actual titles.
//

import SwiftUI
import SwiftData

/// Identifies a tapped stats bucket so it can drive the drill-down sheet.
struct StatFilter: Identifiable {
	enum Criterion: Equatable {
		case status(WatchStatus)   // To Watch / Watching
		case rating(Rating)         // watched + this rating
		case unratedWatched         // watched + no rating
	}
	let criterion: Criterion

	var id: String {
		switch criterion {
		case .status(let s): return "status-\(s.rawValue)"
		case .rating(let r): return "rating-\(r.rawValue)"
		case .unratedWatched: return "unrated"
		}
	}

	var title: String {
		switch criterion {
		case .status(let s): return s.rawValue
		case .rating(let r): return r.rawValue
		case .unratedWatched: return "Unrated"
		}
	}
}

struct StatsView: View {
	@Query private var shows: [Show]
	@Query private var films: [Film]

	@State private var filter: StatFilter?

	private var totalEpisodes: Int { shows.reduce(0) { $0 + $1.episodeCount } }
	private var watchedEpisodes: Int { shows.reduce(0) { $0 + $1.watchedEpisodeCount } }

	// Combined Shows + Films counts.
	private func statusCount(_ status: WatchStatus) -> Int {
		shows.filter { $0.status == status }.count + films.filter { $0.status == status }.count
	}
	private func ratingCount(_ rating: Rating) -> Int {
		shows.filter { $0.status == .watched && $0.rating == rating }.count +
		films.filter { $0.status == .watched && $0.rating == rating }.count
	}
	private var unratedWatchedCount: Int {
		shows.filter { $0.status == .watched && $0.rating == nil }.count +
		films.filter { $0.status == .watched && $0.rating == nil }.count
	}

	var body: some View {
		NavigationStack {
			ZStack {
				GlassBackground()
				ScrollView {
					VStack(spacing: 16) {
						HStack(spacing: 10) {
							StatChip(label: "Shows", value: "\(shows.count)", systemImage: "tv", tint: Glass.accent)
							StatChip(label: "Films", value: "\(films.count)", systemImage: "film", tint: Glass.accent2)
						}
						HStack(spacing: 10) {
							StatChip(label: "Episodes", value: "\(totalEpisodes)", systemImage: "list.and.film", tint: Glass.accent3)
							StatChip(label: "Eps Watched", value: "\(watchedEpisodes)", systemImage: "checkmark.circle.fill", tint: Glass.watched)
						}

						statusCard
						ratingsCard
					}
					.padding(18)
				}
			}
			.navigationTitle("Stats")
			.toolbarBackground(.hidden, for: .navigationBar)
			.sheet(item: $filter) { StatItemsSheet(filter: $0) }
		}
	}

	// MARK: - Status (what's left to watch)

	private var statusCard: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "Status")
			VStack(spacing: 10) {
				drillRow(value: statusCount(.toWatch), filter: StatFilter(criterion: .status(.toWatch))) {
					StatusBadge(status: .toWatch)
				}
				Divider().opacity(0.4)
				drillRow(value: statusCount(.watching), filter: StatFilter(criterion: .status(.watching))) {
					StatusBadge(status: .watching)
				}
			}
			.padding(16)
			.glass(cornerRadius: 18)
		}
	}

	// MARK: - Ratings (everything watched)

	private var ratingsCard: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "Ratings")
			VStack(spacing: 10) {
				ForEach(Rating.allCases) { rating in
					drillRow(value: ratingCount(rating), filter: StatFilter(criterion: .rating(rating))) {
						RatingBadge(rating: rating)
					}
					Divider().opacity(0.4)
				}
				drillRow(value: unratedWatchedCount, filter: StatFilter(criterion: .unratedWatched)) {
					unratedBadge
				}
			}
			.padding(16)
			.glass(cornerRadius: 18)
		}
	}

	private var unratedBadge: some View {
		HStack(spacing: 5) {
			Image(systemName: "minus.circle").font(.system(size: 12, weight: .bold))
			Text("Unrated").font(.system(size: 12, weight: .semibold))
		}
		.foregroundStyle(.secondary)
		.padding(.horizontal, 11).padding(.vertical, 6)
		.background(Color.secondary.opacity(0.12), in: Capsule())
		.overlay(Capsule().strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1))
	}

	// MARK: - Shared tappable row

	private func drillRow<Badge: View>(value: Int, filter: StatFilter, @ViewBuilder badge: () -> Badge) -> some View {
		Button {
			Haptics.tap()
			self.filter = filter
		} label: {
			HStack(spacing: 10) {
				badge()
				Spacer()
				Text("\(value)")
					.font(.system(size: 18, weight: .bold, design: .rounded))
					.foregroundStyle(.primary)
				Image(systemName: "chevron.right")
					.font(.system(size: 12, weight: .bold))
					.foregroundStyle(.tertiary)
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.pressable)
	}
}

// MARK: - Drill-down sheet

/// Lists the titles (Shows + Films combined) that fall into a tapped bucket,
/// each linking to its detail page.
struct StatItemsSheet: View {
	@Environment(\.dismiss) private var dismiss
	@Query(sort: \Show.dateAdded, order: .reverse) private var shows: [Show]
	@Query(sort: \Film.dateAdded, order: .reverse) private var films: [Film]

	let filter: StatFilter

	private func matches(status: WatchStatus, rating: Rating?) -> Bool {
		switch filter.criterion {
		case .status(let s):    return status == s
		case .rating(let r):    return status == .watched && rating == r
		case .unratedWatched:   return status == .watched && rating == nil
		}
	}

	private var matchingShows: [Show] { shows.filter { matches(status: $0.status, rating: $0.rating) } }
	private var matchingFilms: [Film] { films.filter { matches(status: $0.status, rating: $0.rating) } }

	var body: some View {
		NavigationStack {
			ZStack {
				GlassBackground()
				ScrollView {
					VStack(alignment: .leading, spacing: 12) {
						if matchingShows.isEmpty && matchingFilms.isEmpty {
							EmptyState(icon: "tray", title: "Nothing here",
							           subtitle: "No titles match \u{201C}\(filter.title)\u{201D} yet.")
								.padding(.top, 44)
						} else {
							ForEach(matchingShows) { show in
								NavigationLink { ShowDetailView(show: show) } label: {
									GlassRow(title: show.title, subtitle: show.subtitle,
									         thumbURL: show.posterURL, thumbPlaceholder: "tv",
									         status: show.status, rating: show.rating)
								}
								.buttonStyle(.pressable)
							}
							ForEach(matchingFilms) { film in
								NavigationLink { FilmDetailView(film: film) } label: {
									GlassRow(title: film.title,
									         subtitle: [film.year, film.genre].filter { !$0.isEmpty }.joined(separator: " · "),
									         thumbURL: film.posterURL, thumbPlaceholder: "film",
									         status: film.status, rating: film.rating)
								}
								.buttonStyle(.pressable)
							}
						}
					}
					.padding(18)
				}
			}
			.navigationTitle(filter.title)
			.navigationBarTitleDisplayMode(.inline)
			.toolbarBackground(.hidden, for: .navigationBar)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") { dismiss() }
				}
			}
		}
	}
}
