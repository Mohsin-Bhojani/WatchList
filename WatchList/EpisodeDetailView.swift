//
//  EpisodeDetailView.swift
//  WatchList
//
//  An Episode's own page: still + title, status, synopsis (TMDb), technical
//  specs (TMDb) and trivia (scraped lazily from IMDb).
//

import SwiftUI
import SwiftData

struct EpisodeDetailView: View {
	@Bindable var episode: Episode
	@State private var loadingTrivia = false

	private var subtitle: String {
		var parts: [String] = [episode.code]
		if !episode.airDate.isEmpty { parts.append(episode.airDate) }
		if let rt = episode.runtimeMinutes { parts.append("\(rt) min") }
		return parts.joined(separator: "  ·  ")
	}

	var body: some View {
		ZStack {
			GlassBackground()
			ScrollView {
				VStack(alignment: .leading, spacing: 20) {
					DetailHeader(
						posterURL: episode.stillURL,
						backdropURL: episode.stillURL,
						title: episode.displayTitle,
						subtitle: subtitle,
						meta: episode.season?.show?.title ?? "",
						imdbID: episode.imdbID,
						placeholder: "film"
					)

					VStack(alignment: .leading, spacing: 10) {
						SectionLabel(text: "Status")
						StatusPicker(status: $episode.status)
					}

					SynopsisSection(text: episode.synopsis)
					TriviaSection(trivia: episode.trivia, isLoading: loadingTrivia,
					              hasIMDb: !(episode.imdbID ?? "").isEmpty || episode.tmdbShowID != nil)
					SpecsSection(specs: episode.specs)

					Color.clear.frame(height: 20)
				}
				.padding(18)
			}
		}
		.navigationTitle(episode.code)
		.navigationBarTitleDisplayMode(.inline)
		.toolbarBackground(.hidden, for: .navigationBar)
		.task {
			guard !episode.triviaFetched else { return }
			loadingTrivia = true
			await TriviaLoader.loadIfNeeded(for: episode)
			loadingTrivia = false
		}
	}
}
