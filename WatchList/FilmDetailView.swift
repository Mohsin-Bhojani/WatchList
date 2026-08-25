//
//  FilmDetailView.swift
//  WatchList
//
//  A Film's page: poster + title, status, rating, and the same tabbed body the
//  Show page uses — Details (synopsis, technical specs, notes), Cast, Similar
//  and Images, all from TMDb.
//

import SwiftUI
import SwiftData
import UIKit

struct FilmDetailView: View {
	@Bindable var film: Film

	/// View state only — the page always opens on Details.
	@State private var tab: DetailTab = .details
	/// Tabs TMDb turned out to have nothing for. Only known after the first
	/// fetch, since nothing is fetched until its tab is opened.
	@State private var emptyTabs: Set<DetailTab> = []

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
		.navigationTitle(film.title)
		.navigationBarTitleDisplayMode(.inline)
		.toolbarBackground(.hidden, for: .navigationBar)
	}

	// MARK: - Layouts

	/// On a wide iPad the poster sits beside the IMDb link / status / rating,
	/// with the tabs running full-width underneath. iPhone (and narrow iPad
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
						IMDbLinkButton(imdbID: film.imdbID)
						statusSection
						ratingSection
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
				IMDbLinkButton(imdbID: film.imdbID)
				statusSection
				ratingSection
				tabBar
				tabContent
				Color.clear.frame(height: 20)
			}
		}
	}

	// MARK: - Tabs

	/// Cast, Similar and Images all need a TMDb id, so a hand-added film keeps
	/// the single-column page it has today.
	private var tabItems: [DetailTabItem] {
		var items = [DetailTabItem(tab: .details, title: "Details")]
		guard film.tmdbID != nil else { return items }
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
				SynopsisSection(text: film.synopsis)
				SpecsSection(specs: film.specs)
				notesSection
			}
		case .cast:
			if let tmdbID = film.tmdbID {
				CastTabView(source: .movie(movieID: tmdbID)) { found in
					if !found { drop(.cast) }
				}
			}
		case .similar:
			if let tmdbID = film.tmdbID {
				SimilarTitlesTab(source: .movie(movieID: tmdbID), parentGenres: film.genre) { found in
					if !found { drop(.similar) }
				}
			}
		case .images:
			if let tmdbID = film.tmdbID {
				ImagesTabView(source: .movie(movieID: tmdbID)) { found in
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
			posterURL: film.posterURL,
			backdropURL: film.backdropURL,
			title: film.title,
			subtitle: [film.year, film.genre].filter { !$0.isEmpty }.joined(separator: "  ·  "),
			meta: "",
			placeholder: "film"
		)
	}

	private var statusSection: some View {
		VStack(alignment: .leading, spacing: 10) {
			SectionLabel(text: "Status")
			StatusPicker(status: $film.status)
		}
	}

	private var ratingSection: some View {
		VStack(alignment: .leading, spacing: 10) {
			SectionLabel(text: "Rating", systemImage: "star.fill")
			RatingPicker(rating: $film.rating)
		}
	}

	@ViewBuilder
	private var notesSection: some View {
		if !film.notes.isEmpty {
			VStack(alignment: .leading, spacing: 12) {
				SectionLabel(text: "Notes", systemImage: "note.text")
				Text(film.notes)
					.font(.system(size: 15, weight: .regular, design: .rounded))
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(16).glass(cornerRadius: 18)
			}
		}
	}
}
