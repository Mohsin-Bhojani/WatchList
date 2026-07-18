//
//  StatsView.swift
//  WatchList
//
//  A light overview of the whole library. Status and rating rows are tappable
//  and open a sheet listing the actual titles in that bucket.
//

import SwiftUI
import SwiftData

/// Identifies a tapped stats bucket so it can drive the drill-down sheet.
struct StatFilter: Identifiable {
	enum Criterion: Equatable {
		case status(WatchStatus)
		case rating(Rating)
		case unrated
	}
	let kind: MediaKind
	let criterion: Criterion

	var id: String {
		switch criterion {
		case .status(let s): return "\(kind.rawValue)-status-\(s.rawValue)"
		case .rating(let r): return "\(kind.rawValue)-rating-\(r.rawValue)"
		case .unrated:       return "\(kind.rawValue)-unrated"
		}
	}

	var title: String {
		let noun = kind == .show ? "Shows" : "Films"
		switch criterion {
		case .status(let s): return "\(s.rawValue) · \(noun)"
		case .rating(let r): return "\(r.rawValue) · \(noun)"
		case .unrated:       return "Unrated · \(noun)"
		}
	}
}

struct StatsView: View {
	@Query private var shows: [Show]
	@Query private var films: [Film]

	@State private var filter: StatFilter?

	private var totalEpisodes: Int { shows.reduce(0) { $0 + $1.episodeCount } }
	private var watchedEpisodes: Int { shows.reduce(0) { $0 + $1.watchedEpisodeCount } }

	private func count<T>(_ items: [T], _ keyPath: KeyPath<T, WatchStatus>, _ status: WatchStatus) -> Int {
		items.filter { $0[keyPath: keyPath] == status }.count
	}

	private func count<T>(_ items: [T], _ keyPath: KeyPath<T, Rating?>, _ rating: Rating) -> Int {
		items.filter { $0[keyPath: keyPath] == rating }.count
	}

	private func unratedCount<T>(_ items: [T], _ keyPath: KeyPath<T, Rating?>) -> Int {
		items.filter { $0[keyPath: keyPath] == nil }.count
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

						breakdown(.show, "Shows", to: count(shows, \.status, .toWatch),
						          watching: count(shows, \.status, .watching),
						          watched: count(shows, \.status, .watched))
						breakdown(.film, "Films", to: count(films, \.status, .toWatch),
						          watching: count(films, \.status, .watching),
						          watched: count(films, \.status, .watched))

						ratingBreakdown(.show, "Show Ratings", items: shows, keyPath: \.rating)
						ratingBreakdown(.film, "Film Ratings", items: films, keyPath: \.rating)
					}
					.padding(18)
				}
			}
			.navigationTitle("Stats")
			.toolbarBackground(.hidden, for: .navigationBar)
			.sheet(item: $filter) { StatItemsSheet(filter: $0) }
		}
	}

	// MARK: - Status breakdown

	@ViewBuilder private func breakdown(_ kind: MediaKind, _ title: String, to: Int, watching: Int, watched: Int) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: title)
			VStack(spacing: 10) {
				statusRow(kind, .toWatch, to)
				Divider().opacity(0.4)
				statusRow(kind, .watching, watching)
				Divider().opacity(0.4)
				statusRow(kind, .watched, watched)
			}
			.padding(16)
			.glass(cornerRadius: 18)
		}
	}

	private func statusRow(_ kind: MediaKind, _ status: WatchStatus, _ value: Int) -> some View {
		drillRow(value: value, filter: StatFilter(kind: kind, criterion: .status(status))) {
			StatusBadge(status: status)
		}
	}

	// MARK: - Rating breakdown

	@ViewBuilder private func ratingBreakdown<T>(_ kind: MediaKind, _ title: String, items: [T], keyPath: KeyPath<T, Rating?>) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: title)
			VStack(spacing: 10) {
				ForEach(Rating.allCases) { rating in
					drillRow(value: count(items, keyPath, rating),
					         filter: StatFilter(kind: kind, criterion: .rating(rating))) {
						RatingBadge(rating: rating)
					}
					Divider().opacity(0.4)
				}
				drillRow(value: unratedCount(items, keyPath),
				         filter: StatFilter(kind: kind, criterion: .unrated)) {
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

/// Lists the titles that fall into a tapped stats bucket, scoped to one media
/// kind, each linking to its detail page.
struct StatItemsSheet: View {
	@Environment(\.dismiss) private var dismiss
	@Query(sort: \Show.dateAdded, order: .reverse) private var shows: [Show]
	@Query(sort: \Film.dateAdded, order: .reverse) private var films: [Film]

	let filter: StatFilter

	private func matches(status: WatchStatus, rating: Rating?) -> Bool {
		switch filter.criterion {
		case .status(let s): return status == s
		case .rating(let r): return rating == r
		case .unrated:       return rating == nil
		}
	}

	private var matchingShows: [Show] {
		guard filter.kind == .show else { return [] }
		return shows.filter { matches(status: $0.status, rating: $0.rating) }
	}
	private var matchingFilms: [Film] {
		guard filter.kind == .film else { return [] }
		return films.filter { matches(status: $0.status, rating: $0.rating) }
	}

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
