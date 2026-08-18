//
//  SeasonDetailView.swift
//  WatchList
//
//  A Season's page: overview + the list of episodes (each links to its own
//  page). Episodes can be added manually.
//

import SwiftUI
import SwiftData
import UIKit

struct SeasonDetailView: View {
	@Environment(\.modelContext) private var ctx
	@Bindable var season: Season

	@State private var showingAddEpisode = false

	/// View state only — the page always opens on Details.
	@State private var tab: DetailTab = .details
	/// Tabs TMDb turned out to have nothing for. Only known after the first
	/// fetch, since nothing is fetched until its tab is opened.
	@State private var emptyTabs: Set<DetailTab> = []

	private var posterURL: String { season.posterURL.isEmpty ? (season.show?.posterURL ?? "") : season.posterURL }

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
		.navigationTitle(season.displayName)
		.navigationBarTitleDisplayMode(.inline)
		.toolbarBackground(.hidden, for: .navigationBar)
		.sheet(isPresented: $showingAddEpisode) { AddEpisodeSheet(season: season) }
	}

	// MARK: - Layouts

	/// On a wide iPad the poster sits beside the status / synopsis, with the
	/// episode list running full-width underneath. iPhone (and narrow iPad
	/// multitasking widths) keep the original single column.
	@ViewBuilder
	private func layout(width: CGFloat) -> some View {
		let isWideiPad = UIDevice.current.userInterfaceIdiom == .pad && width >= 820
		if isWideiPad {
			// Cap the side column so the landscape poster keeps the larger share.
			let sideWidth = min(max((width - 36) * 0.34, 300), 380)
			VStack(alignment: .leading, spacing: 20) {
				HStack(alignment: .top, spacing: 20) {
					header
						.frame(maxWidth: .infinity)
					VStack(alignment: .leading, spacing: 20) {
						IMDbLinkButton(imdbID: season.show?.imdbID, seasonNumber: season.seasonNumber)
						StatusPicker(status: $season.status)
						RatingPicker(rating: $season.rating)
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
				IMDbLinkButton(imdbID: season.show?.imdbID, seasonNumber: season.seasonNumber)
				StatusPicker(status: $season.status)
				RatingPicker(rating: $season.rating)
				tabBar
				tabContent
				Color.clear.frame(height: 20)
			}
		}
	}

	// MARK: - Tabs

	private var tabItems: [DetailTabItem] {
		var items = [DetailTabItem(tab: .details, title: "Details")]
		guard season.show?.tmdbID != nil else { return items }
		if !emptyTabs.contains(.cast) { items.append(DetailTabItem(tab: .cast, title: "Cast")) }
		if !emptyTabs.contains(.similar) { items.append(DetailTabItem(tab: .similar, title: "Similar")) }
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
				if !season.overview.isEmpty {
					SynopsisSection(text: season.overview)
				}
				episodesSection
			}
		case .cast:
			if let tmdbID = season.show?.tmdbID {
				CastTabView(source: .season(tvID: tmdbID, season: season.seasonNumber)) { found in
					if !found { drop(.cast) }
				}
			}
		case .similar:
			// TMDb has no per-season similarity, so a season shows the series'
			// list — the same call the Show page makes, off the same cache.
			if let tmdbID = season.show?.tmdbID {
				SimilarTitlesTab(tvID: tmdbID, parentGenres: season.show?.genre ?? "") { found in
					if !found { drop(.similar) }
				}
			}
		case .images:
			// The season's own posters, not the series' — TMDb keeps artwork per
			// season, and a season without any drops the tab.
			if let tmdbID = season.show?.tmdbID {
				ImagesTabView(source: .season(tvID: tmdbID, season: season.seasonNumber)) { found in
					if !found { drop(.images) }
				}
			}
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
			posterURL: posterURL,
			backdropURL: season.show?.backdropURL ?? "",
			title: season.displayName,
			subtitle: season.show?.title ?? "",
			meta: "\(season.episodes.count) episodes · \(season.watchedCount) watched",
			placeholder: "tv"
		)
	}

	@ViewBuilder
	private var episodesSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				SectionLabel(text: "Episodes", systemImage: "list.and.film")
				Spacer()
				Button { showingAddEpisode = true } label: {
					Image(systemName: "plus.circle.fill")
						.font(.system(size: 20, weight: .semibold))
						.foregroundStyle(Glass.accent)
				}
			}
			if season.episodes.isEmpty {
				Text("No episodes yet. Tap + to add one.")
					.font(.system(size: 14, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(16).glass(cornerRadius: 18)
			} else {
				ForEach(season.sortedEpisodes) { ep in
					NavigationLink { EpisodeDetailView(episode: ep) } label: {
						GlassRow(
							title: "\(ep.episodeNumber). \(ep.displayTitle)",
							subtitle: ep.synopsis,
							thumbURL: ep.stillURL,
							thumbPlaceholder: "film",
							status: ep.status,
							episodeTier: ep.episodeTier
						)
					}
					.buttonStyle(.pressable)
					.contextMenu {
						Button { ep.status = .watched } label: { Label("Mark Watched", systemImage: "checkmark.circle") }
						Button(role: .destructive) { withAnimation { ctx.delete(ep) } } label: { Label("Delete", systemImage: "trash") }
					}
				}
			}
		}
	}
}

// MARK: - Add Episode sheet

struct AddEpisodeSheet: View {
	@Environment(\.modelContext) private var ctx
	@Environment(\.dismiss) private var dismiss
	@Bindable var season: Season

	@State private var number = ""
	@State private var title = ""
	@State private var synopsis = ""
	@State private var imdb = ""

	private var suggestedNumber: Int { (season.episodes.map { $0.episodeNumber }.max() ?? 0) + 1 }

	var body: some View {
		NavigationStack {
			ZStack {
				GlassBackground()
				ScrollView {
					VStack(alignment: .leading, spacing: 16) {
						SectionLabel(text: "Episode number")
						TextField("\(suggestedNumber)", text: $number)
							.keyboardType(.numberPad)
							.font(.system(size: 15, weight: .medium, design: .rounded))
							.padding(15).glass(cornerRadius: 16)
						SectionLabel(text: "Title")
						TextField("Episode title", text: $title)
							.font(.system(size: 15, weight: .medium, design: .rounded))
							.padding(15).glass(cornerRadius: 16)
						SectionLabel(text: "Synopsis (optional)")
						TextField("What happens?", text: $synopsis, axis: .vertical)
							.lineLimit(3...6)
							.font(.system(size: 15, weight: .medium, design: .rounded))
							.padding(15).glass(cornerRadius: 16)
						SectionLabel(text: "Episode IMDb link/id (optional, for trivia)")
						TextField("tt...", text: $imdb)
							.textInputAutocapitalization(.never).autocorrectionDisabled()
							.font(.system(size: 15, weight: .medium, design: .rounded))
							.padding(15).glass(cornerRadius: 16)

						Button {
							let n = Int(number) ?? suggestedNumber
							let ep = Episode(episodeNumber: n, seasonNumber: season.seasonNumber,
							                 title: title, synopsis: synopsis, imdbID: IMDb.id(from: imdb))
							ep.season = season
							ctx.insert(ep)
							Haptics.success(); dismiss()
						} label: {
							Text("Add Episode").font(.system(size: 16, weight: .bold, design: .rounded))
								.foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 15)
								.background(Capsule().fill(LinearGradient(colors: [Glass.accent, Glass.accent2],
								                                         startPoint: .leading, endPoint: .trailing)))
						}
						.buttonStyle(.pressable)
						.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
						.opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
					}
					.padding(18)
				}
			}
			.navigationTitle("New Episode")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
		}
	}
}
