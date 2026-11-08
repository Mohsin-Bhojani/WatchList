//
//  PhoneStatsView.swift
//  WatchList
//
//  Stats on iPhone, in the app's paper theme — following light and dark and
//  your accent colour, like the tabs: the same overview as the shared StatsView
//  — totals, what's left to watch, ratings, each row opening the titles behind
//  it. The status and rating badges keep their colours; they carry the meaning.
//

import SwiftUI
import SwiftData
import WatchListCore
import WatchListLibrary

/// A tapped Stats row, which drives the drill-down sheet.
struct StatFilter: Identifiable {
	enum Criterion: Equatable {
		case status(WatchStatus)   // To Watch / Watching
		case rating(Rating)        // watched + this rating
		case unratedWatched        // watched + no rating
	}

	let criterion: Criterion

	var id: String {
		switch criterion {
		case .status(let status): return "status-\(status.rawValue)"
		case .rating(let rating): return "rating-\(rating.rawValue)"
		case .unratedWatched:     return "unrated"
		}
	}

	var title: String {
		switch criterion {
		case .status(let status): return status.rawValue
		case .rating(let rating): return rating.rawValue
		case .unratedWatched:     return "Unrated"
		}
	}
}

struct PhoneStatsView: View {
	@Query private var shows: [Show]
	@Query private var films: [Film]

	@State private var filter: StatFilter?

	private var totalEpisodes: Int { shows.reduce(0) { $0 + $1.episodeCount } }
	private var watchedEpisodes: Int { shows.reduce(0) { $0 + $1.watchedEpisodeCount } }

	// Shows and films counted together.
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

	@Environment(\.dismiss) private var dismissStats

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(spacing: 12) {
					// How far through, as rings (design B of the alternatives).
					HStack(spacing: 12) {
						ring("Shows finished", done: shows.filter { $0.status == .watched }.count, of: shows.count,
						     tint: Glass.watched)
						ring("Films watched", done: films.filter { $0.status == .watched }.count, of: films.count,
						     tint: Glass.watched)
					}
					HStack(spacing: 12) {
						ring("Episodes watched", done: watchedEpisodes, of: totalEpisodes, tint: Glass.watching)
						ring("Watched and rated", done: ratedWatchedCount, of: watchedTitleCount, tint: Glass.accent)
					}
					statusCard
						.padding(.top, 12)
					ratingsCard
						.padding(.top, 12)
				}
				.padding(18)
			}
			.background(GlassBackground())
			.navigationTitle("Stats")
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Button(role: .close) { dismissStats() }
				}
			}
			.sheet(item: $filter) { PhoneStatItemsSheet(filter: $0) }
		}
	}

	private var watchedTitleCount: Int {
		shows.filter { $0.status == .watched }.count + films.filter { $0.status == .watched }.count
	}

	private var ratedWatchedCount: Int { watchedTitleCount - unratedWatchedCount }

	/// A share as a ring with its percentage in it, the counts under it.
	private func ring(_ label: String, done: Int, of total: Int, tint: Color) -> some View {
		let fraction = total == 0 ? 0 : Double(done) / Double(total)
		return VStack(spacing: 10) {
			ZStack {
				Circle().stroke(Glass.ink.opacity(0.12), lineWidth: 8)
				Circle()
					.trim(from: 0, to: fraction)
					.stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
					.rotationEffect(.degrees(-90))
				Text(total == 0 ? "–" : "\(Int((fraction * 100).rounded()))%")
					.font(.system(.body, design: .serif, weight: .bold))
					.foregroundStyle(Glass.ink)
			}
			.frame(width: 78, height: 78)
			VStack(spacing: 2) {
				Text(label)
					.font(.system(.subheadline, weight: .semibold))
					.foregroundStyle(Glass.ink)
				Text("\(done) of \(total)")
					.font(.system(.caption, weight: .medium))
					.foregroundStyle(.secondary)
			}
			.multilineTextAlignment(.center)
		}
		.frame(maxWidth: .infinity)
		.padding(16)
		.glass(cornerRadius: 22)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("\(label): \(done) of \(total)")
	}

	private func tile(_ label: String, value: Int, systemImage: String) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 6) {
				Image(systemName: systemImage)
					.font(.system(.footnote, weight: .bold))
					.foregroundStyle(Glass.accent)
				Text(label)
					.font(.system(.footnote, weight: .semibold))
					.foregroundStyle(.secondary)
			}
			Text("\(value)")
				.font(.system(.title, design: .rounded, weight: .bold))
				.foregroundStyle(Glass.ink)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(16)
		.glass(cornerRadius: 22)
		.accessibilityElement(children: .combine)
	}

	// MARK: Status — what's left to watch

	private var statusCard: some View {
		VStack(alignment: .leading, spacing: 10) {
			SectionLabel(text: "Status")
			VStack(spacing: 0) {
				drillRow(value: statusCount(.toWatch), filter: StatFilter(criterion: .status(.toWatch))) {
					StatusBadge(status: .toWatch)
				}
				rowDivider
				drillRow(value: statusCount(.watching), filter: StatFilter(criterion: .status(.watching))) {
					StatusBadge(status: .watching)
				}
			}
			.padding(.horizontal, 16)
			.glass(cornerRadius: 22)
		}
	}

	// MARK: Ratings — everything watched

	private var ratingsCard: some View {
		VStack(alignment: .leading, spacing: 10) {
			SectionLabel(text: "Ratings")
			VStack(spacing: 0) {
				ForEach(Rating.allCases) { rating in
					drillRow(value: ratingCount(rating), filter: StatFilter(criterion: .rating(rating))) {
						RatingBadge(rating: rating)
					}
					rowDivider
				}
				drillRow(value: unratedWatchedCount, filter: StatFilter(criterion: .unratedWatched)) {
					unratedBadge
				}
			}
			.padding(.horizontal, 16)
			.glass(cornerRadius: 22)
		}
	}

	private var rowDivider: some View {
		Rectangle()
			.fill(Glass.hairline.opacity(0.12))
			.frame(height: 1)
	}

	private var unratedBadge: some View {
		HStack(spacing: 5) {
			Image(systemName: "minus.circle")
				.font(.system(.caption, weight: .bold))
			Text("Unrated")
				.font(.system(.caption, weight: .semibold))
		}
		.foregroundStyle(.secondary)
		.padding(.horizontal, 11)
		.padding(.vertical, 6)
		.background(Glass.hairline.opacity(0.06), in: Capsule())
		.overlay(Capsule().strokeBorder(Glass.hairline.opacity(0.25), lineWidth: 1))
	}

	private func drillRow<Badge: View>(value: Int, filter: StatFilter,
	                                   @ViewBuilder badge: () -> Badge) -> some View {
		Button {
			self.filter = filter
		} label: {
			HStack(spacing: 10) {
				badge()
				Spacer()
				Text("\(value)")
					.font(.system(.body, design: .rounded, weight: .bold))
					.foregroundStyle(Glass.ink)
				Image(systemName: "chevron.right")
					.font(.system(.caption, weight: .bold))
					.foregroundStyle(.tertiary)
			}
			.padding(.vertical, 13)
			.contentShape(Rectangle())
		}
		.buttonStyle(.pressable)
	}
}

// MARK: - Drill-down

/// The titles behind a tapped Stats row — shows and films together — each
/// opening its page.
struct PhoneStatItemsSheet: View {
	@Environment(\.dismiss) private var dismiss
	@Query(sort: \Show.dateAdded, order: .reverse) private var shows: [Show]
	@Query(sort: \Film.dateAdded, order: .reverse) private var films: [Film]

	let filter: StatFilter

	private func matches(status: WatchStatus, rating: Rating?) -> Bool {
		switch filter.criterion {
		case .status(let wanted): return status == wanted
		case .rating(let wanted): return status == .watched && rating == wanted
		case .unratedWatched:     return status == .watched && rating == nil
		}
	}

	private var matchingShows: [Show] { shows.filter { matches(status: $0.status, rating: $0.rating) } }
	private var matchingFilms: [Film] { films.filter { matches(status: $0.status, rating: $0.rating) } }

	var body: some View {
		NavigationStack {
			List {
				if matchingShows.isEmpty && matchingFilms.isEmpty {
					EmptyState(icon: "tray", title: "Nothing here",
					           subtitle: "No titles match \u{201C}\(filter.title)\u{201D} yet.")
						.padding(.top, 44)
						.listRowBackground(Color.clear)
						.listRowSeparator(.hidden)
				} else {
					ForEach(matchingShows) { show in
						NavigationLink { PhoneShowDetailView(show: show) } label: {
							row(title: show.title, subtitle: show.subtitle, posterURL: show.posterURL,
							    placeholder: "tv", status: show.status, rating: show.rating)
						}
						.titleRow(.show(show))
					}
					ForEach(matchingFilms) { film in
						NavigationLink { PhoneFilmDetailView(film: film) } label: {
							row(title: film.title,
							    subtitle: [film.year, film.genre].filter { !$0.isEmpty }.joined(separator: " · "),
							    posterURL: film.posterURL, placeholder: "film",
							    status: film.status, rating: film.rating)
						}
						.titleRow(.film(film))
					}
				}
			}
			.listStyle(.plain)
			.scrollContentBackground(.hidden)
			.background(GlassBackground())
			.navigationTitle(filter.title)
			.navigationBarTitleDisplayMode(.inline)
			.toolbarBackground(.hidden, for: .navigationBar)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") { dismiss() }
						.tint(Glass.accent)
				}
			}
		}
	}

	private func row(title: String, subtitle: String, posterURL: String, placeholder: String,
	                 status: WatchStatus, rating: Rating?) -> some View {
		HStack(spacing: 12) {
			if !posterURL.isEmpty {
				PosterImage(urlString: posterURL, systemPlaceholder: placeholder)
					.frame(width: 54, height: 76)
					.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
			}
			VStack(alignment: .leading, spacing: 3) {
				Text(title)
					.font(.system(.callout, weight: .semibold))
					.foregroundStyle(Glass.ink)
					.lineLimit(2)
				if !subtitle.isEmpty {
					Text(subtitle)
						.font(.system(.footnote, weight: .medium))
						.foregroundStyle(.secondary)
						.lineLimit(2)
				}
			}
			Spacer(minLength: 6)
			if let rating { RatingBadge(rating: rating, compact: true) }
			StatusBadge(status: status, compact: true)
			Image(systemName: "chevron.right")
				.font(.system(.footnote, weight: .bold))
				.foregroundStyle(.tertiary)
		}
		.padding(.vertical, 11)
		.padding(.horizontal, 14)
		.glass(cornerRadius: 20)
	}
}

private extension View {
	/// A glass card as a plain List row, with swipe and long-press actions.
	func titleRow(_ item: WatchedTitle) -> some View {
		navigationLinkIndicatorVisibility(.hidden)
			.listRowBackground(Color.clear)
			.listRowSeparator(.hidden)
			.listRowInsets(EdgeInsets(top: 5, leading: 18, bottom: 5, trailing: 18))
			.titleSwipeActions(item)
			.titleQuickActions(item)
	}
}
