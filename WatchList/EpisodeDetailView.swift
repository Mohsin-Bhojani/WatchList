//
//  EpisodeDetailView.swift
//  WatchList
//
//  An Episode's own page: still + title, status, synopsis and technical specs
//  (TMDb), plus the episode's cast and stills as tabs.
//

import SwiftUI
import SwiftData
import UIKit

struct EpisodeDetailView: View {
	@Bindable var episode: Episode

	/// View state only — the page always opens on Details. An episode has no
	/// meaningful "similar", so it is Details, the cast and the stills.
	@State private var tab: DetailTab = .details
	/// Tabs TMDb turned out to have nothing for. Only known after the first
	/// fetch, since nothing is fetched until its tab is opened.
	@State private var emptyTabs: Set<DetailTab> = []

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
	}

	// MARK: - Layouts

	/// On a wide iPad the still sits beside the IMDb link / status / synopsis,
	/// with the tabs running full-width underneath. iPhone
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
		guard episode.tmdbShowID != nil else { return items }
		if !emptyTabs.contains(.cast) { items.append(DetailTabItem(tab: .cast, title: "In this episode")) }
		if !emptyTabs.contains(.images) { items.append(DetailTabItem(tab: .images, title: "Images")) }
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
				SpecsSection(specs: episode.specs)
			}
		case .cast:
			// An episode that hasn't aired yet has no credits, so the tab
			// removes itself once we know that.
			if let showID = episode.tmdbShowID {
				CastTabView(source: .episode(tvID: showID,
				                             season: episode.seasonNumber,
				                             episode: episode.episodeNumber)) { found in
					if !found { drop(.cast) }
				}
			}
		case .images:
			// Every still TMDb has for this episode, not just the one used as
			// the thumbnail. Unaired episodes usually have none.
			if let showID = episode.tmdbShowID {
				ImagesTabView(source: .episode(tvID: showID,
				                               season: episode.seasonNumber,
				                               episode: episode.episodeNumber)) { found in
					if !found { drop(.images) }
				}
			}
		case .similar:
			EmptyView()
		}
	}

	private func drop(_ tab: DetailTab) {
		withAnimation(Glass.smooth) {
			emptyTabs.insert(tab)
			if self.tab == tab { self.tab = .details }
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
}
