//
//  StatsView.swift
//  WatchList
//
//  A light overview of the whole library.
//

import SwiftUI
import SwiftData

struct StatsView: View {
	@Query private var shows: [Show]
	@Query private var films: [Film]

	private var totalEpisodes: Int { shows.reduce(0) { $0 + $1.episodeCount } }
	private var watchedEpisodes: Int { shows.reduce(0) { $0 + $1.watchedEpisodeCount } }

	private func count<T>(_ items: [T], _ keyPath: KeyPath<T, WatchStatus>, _ status: WatchStatus) -> Int {
		items.filter { $0[keyPath: keyPath] == status }.count
	}

	private func count<T>(_ items: [T], _ keyPath: KeyPath<T, Rating?>, _ rating: Rating) -> Int {
		items.filter { $0[keyPath: keyPath] == rating }.count
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

						breakdown("Shows", to: count(shows, \.status, .toWatch),
						          watching: count(shows, \.status, .watching),
						          watched: count(shows, \.status, .watched))
						breakdown("Films", to: count(films, \.status, .toWatch),
						          watching: count(films, \.status, .watching),
						          watched: count(films, \.status, .watched))

						ratingBreakdown("Show Ratings", items: shows, keyPath: \.rating)
						ratingBreakdown("Film Ratings", items: films, keyPath: \.rating)
					}
					.padding(18)
				}
			}
			.navigationTitle("Stats")
			.toolbarBackground(.hidden, for: .navigationBar)
		}
	}

	@ViewBuilder private func breakdown(_ title: String, to: Int, watching: Int, watched: Int) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: title)
			VStack(spacing: 10) {
				row(.toWatch, to)
				Divider().opacity(0.4)
				row(.watching, watching)
				Divider().opacity(0.4)
				row(.watched, watched)
			}
			.padding(16)
			.glass(cornerRadius: 18)
		}
	}

	@ViewBuilder private func row(_ status: WatchStatus, _ value: Int) -> some View {
		HStack {
			StatusBadge(status: status)
			Spacer()
			Text("\(value)")
				.font(.system(size: 18, weight: .bold, design: .rounded))
				.foregroundStyle(.primary)
		}
	}

	@ViewBuilder private func ratingBreakdown<T>(_ title: String, items: [T], keyPath: KeyPath<T, Rating?>) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: title)
			VStack(spacing: 10) {
				ForEach(Array(Rating.allCases.enumerated()), id: \.element) { index, rating in
					if index > 0 { Divider().opacity(0.4) }
					HStack {
						RatingBadge(rating: rating)
						Spacer()
						Text("\(count(items, keyPath, rating))")
							.font(.system(size: 18, weight: .bold, design: .rounded))
							.foregroundStyle(.primary)
					}
				}
			}
			.padding(16)
			.glass(cornerRadius: 18)
		}
	}
}
