//
//  EpisodeDetailView.swift
//  WatchList
//
//  An Episode's own page: still + title, status, synopsis (TMDb), technical
//  specs (TMDb) and trivia (scraped lazily from IMDb).
//

import SwiftUI
import SwiftData
import UIKit

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
			GeometryReader { geo in
				ScrollView {
					layout(width: geo.size.width)
						.padding(18)
				}
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

	// MARK: - Layouts

	/// On a wide iPad the still sits beside the IMDb link / status / synopsis,
	/// with trivia and technical specs running full-width underneath. iPhone
	/// (and narrow iPad multitasking widths) keep the original single column.
	@ViewBuilder
	private func layout(width: CGFloat) -> some View {
		let isWideiPad = UIDevice.current.userInterfaceIdiom == .pad && width >= 820
		if isWideiPad {
			let sideWidth = min(max((width - 36) * 0.34, 300), 380)
			VStack(alignment: .leading, spacing: 20) {
				HStack(alignment: .top, spacing: 20) {
					header
						.frame(maxWidth: .infinity)
					VStack(alignment: .leading, spacing: 20) {
						IMDbLinkButton(imdbID: episode.imdbID)
						statusSection
						SynopsisSection(text: episode.synopsis)
					}
					.frame(width: sideWidth)
				}
				triviaSection
				SpecsSection(specs: episode.specs)
				Color.clear.frame(height: 20)
			}
		} else {
			VStack(alignment: .leading, spacing: 20) {
				header
				IMDbLinkButton(imdbID: episode.imdbID)
				statusSection
				SynopsisSection(text: episode.synopsis)
				triviaSection
				SpecsSection(specs: episode.specs)
				Color.clear.frame(height: 20)
			}
		}
	}

	// MARK: - Sections

	private var header: some View {
		DetailHeader(
			posterURL: episode.stillURL,
			backdropURL: episode.stillURL,
			title: episode.displayTitle,
			subtitle: subtitle,
			meta: episode.season?.show?.title ?? "",
			placeholder: "film"
		)
	}

	private var statusSection: some View {
		VStack(alignment: .leading, spacing: 10) {
			SectionLabel(text: "Status")
			StatusPicker(status: $episode.status)
		}
	}

	private var triviaSection: some View {
		TriviaSection(trivia: episode.trivia, isLoading: loadingTrivia,
		              hasIMDb: !(episode.imdbID ?? "").isEmpty || episode.tmdbShowID != nil)
	}
}
