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

	/// View state only — the page always opens on Details. An episode has no
	/// meaningful "similar", so there are only ever two tabs here.
	@State private var tab: DetailTab = .details
	@State private var castIsEmpty = false

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
						StatusPicker(status: $episode.status)
						EpisodeTierPicker(tier: $episode.episodeTier)
					}
					.frame(width: sideWidth)
				}
				tabBar
				tabContent
				Color.clear.frame(height: 20)
			}
		} else {
			VStack(alignment: .leading, spacing: 20) {
				header
				IMDbLinkButton(imdbID: episode.imdbID)
				StatusPicker(status: $episode.status)
				EpisodeTierPicker(tier: $episode.episodeTier)
				tabBar
				tabContent
				Color.clear.frame(height: 20)
			}
		}
	}

	// MARK: - Tabs

	private var tabItems: [DetailTabItem] {
		var items = [DetailTabItem(tab: .details, title: "Details")]
		guard episode.tmdbShowID != nil, !castIsEmpty else { return items }
		items.append(DetailTabItem(tab: .cast, title: "In this episode"))
		return items
	}

	@ViewBuilder
	private var tabBar: some View {
		if tabItems.count > 1 {
			DetailTabBar(items: tabItems, selection: $tab)
		}
	}

	@ViewBuilder
	private var tabContent: some View {
		switch tab {
		case .details:
			VStack(alignment: .leading, spacing: 20) {
				SynopsisSection(text: episode.synopsis)
				triviaSection
				SpecsSection(specs: episode.specs)
			}
		case .cast:
			// An episode that hasn't aired yet has no credits, so the tab
			// removes itself once we know that.
			if let showID = episode.tmdbShowID {
				CastTabView(source: .episode(tvID: showID,
				                             season: episode.seasonNumber,
				                             episode: episode.episodeNumber)) { found in
					guard !found else { return }
					withAnimation(Glass.smooth) {
						castIsEmpty = true
						tab = .details
					}
				}
			}
		case .similar:
			EmptyView()
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

	private var triviaSection: some View {
		TriviaSection(trivia: episode.trivia, isLoading: loadingTrivia,
		              hasIMDb: !(episode.imdbID ?? "").isEmpty || episode.tmdbShowID != nil)
	}
}
