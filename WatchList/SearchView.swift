//
//  SearchView.swift
//  WatchList
//
//  Searches the local library (shows + films) and links straight to detail
//  pages. Empty queries show a gentle prompt.
//

import SwiftUI
import SwiftData

struct SearchView: View {
	@Query(sort: \Show.dateAdded, order: .reverse) private var shows: [Show]
	@Query(sort: \Film.dateAdded, order: .reverse) private var films: [Film]

	@State private var query = ""

	private var matchedShows: [Show] {
		guard !query.isEmpty else { return [] }
		return shows.filter {
			$0.title.localizedCaseInsensitiveContains(query) ||
			$0.genre.localizedCaseInsensitiveContains(query) ||
			$0.overview.localizedCaseInsensitiveContains(query)
		}
	}
	private var matchedFilms: [Film] {
		guard !query.isEmpty else { return [] }
		return films.filter {
			$0.title.localizedCaseInsensitiveContains(query) ||
			$0.genre.localizedCaseInsensitiveContains(query) ||
			$0.synopsis.localizedCaseInsensitiveContains(query)
		}
	}

	var body: some View {
		NavigationStack {
			ZStack {
				GlassBackground()
				ScrollView {
					VStack(alignment: .leading, spacing: 14) {
						if query.isEmpty {
							EmptyState(icon: "magnifyingglass", title: "Search your library",
							           subtitle: "Find any show or film by title, genre or synopsis.")
								.padding(.top, 40)
						} else if matchedShows.isEmpty && matchedFilms.isEmpty {
							EmptyState(icon: "questionmark.circle", title: "No matches",
							           subtitle: "Nothing in your library matches \u{201C}\(query)\u{201D}.")
								.padding(.top, 40)
						} else {
							if !matchedShows.isEmpty {
								SectionLabel(text: "Shows", systemImage: "tv")
								ForEach(matchedShows) { show in
									NavigationLink { ShowDetailView(show: show) } label: {
										GlassRow(title: show.title, subtitle: show.subtitle,
										         thumbURL: show.posterURL, thumbPlaceholder: "tv",
										         status: show.status)
									}
									.buttonStyle(.pressable)
								}
							}
							if !matchedFilms.isEmpty {
								SectionLabel(text: "Films", systemImage: "film")
									.padding(.top, 4)
								ForEach(matchedFilms) { film in
									NavigationLink { FilmDetailView(film: film) } label: {
										GlassRow(title: film.title,
										         subtitle: [film.year, film.genre].filter { !$0.isEmpty }.joined(separator: " · "),
										         thumbURL: film.posterURL, thumbPlaceholder: "film",
										         status: film.status)
									}
									.buttonStyle(.pressable)
								}
							}
						}
					}
					.padding(18)
				}
			}
			.navigationTitle("Search")
			.toolbarBackground(.hidden, for: .navigationBar)
			.searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
			            prompt: "Shows & films")
		}
	}
}
