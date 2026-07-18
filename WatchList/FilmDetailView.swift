//
//  FilmDetailView.swift
//  WatchList
//
//  A Film's page: poster + title, status, synopsis (TMDb), trivia (scraped
//  lazily from IMDb) and technical specs (TMDb).
//

import SwiftUI
import SwiftData

struct FilmDetailView: View {
	@Bindable var film: Film
	@State private var loadingTrivia = false

	var body: some View {
		ZStack {
			GlassBackground()
			ScrollView {
				VStack(alignment: .leading, spacing: 20) {
					DetailHeader(
						posterURL: film.posterURL,
						backdropURL: film.backdropURL,
						title: film.title,
						subtitle: [film.year, film.genre].filter { !$0.isEmpty }.joined(separator: "  ·  "),
						meta: "",
						imdbID: film.imdbID,
						placeholder: "film"
					)

					VStack(alignment: .leading, spacing: 10) {
						SectionLabel(text: "Status")
						StatusPicker(status: $film.status)
					}

					SynopsisSection(text: film.synopsis)
					TriviaSection(trivia: film.trivia, isLoading: loadingTrivia,
					              hasIMDb: !(film.imdbID ?? "").isEmpty)
					SpecsSection(specs: film.specs)

					if !film.notes.isEmpty {
						VStack(alignment: .leading, spacing: 12) {
							SectionLabel(text: "Notes", systemImage: "note.text")
							Text(film.notes)
								.font(.system(size: 15, weight: .regular, design: .rounded))
								.frame(maxWidth: .infinity, alignment: .leading)
								.padding(16).glass(cornerRadius: 18)
						}
					}

					Color.clear.frame(height: 20)
				}
				.padding(18)
			}
		}
		.navigationTitle(film.title)
		.navigationBarTitleDisplayMode(.inline)
		.toolbarBackground(.hidden, for: .navigationBar)
		.task {
			guard !film.triviaFetched else { return }
			loadingTrivia = true
			await TriviaLoader.loadIfNeeded(for: film)
			loadingTrivia = false
		}
	}
}
