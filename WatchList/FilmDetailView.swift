//
//  FilmDetailView.swift
//  WatchList
//
//  A Film's page: poster + title, status, synopsis (TMDb), trivia (scraped
//  lazily from IMDb) and technical specs (TMDb).
//

import SwiftUI
import SwiftData
import UIKit

struct FilmDetailView: View {
	@Bindable var film: Film
	@State private var loadingTrivia = false

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
		.task {
			guard !film.triviaFetched else { return }
			loadingTrivia = true
			await TriviaLoader.loadIfNeeded(for: film)
			loadingTrivia = false
		}
	}

	// MARK: - Layouts

	/// On a wide iPad the poster sits beside the IMDb link / status / synopsis,
	/// with trivia, specs, and notes running full-width underneath. iPhone (and
	/// narrow iPad multitasking widths) keep the original single column.
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
						IMDbLinkButton(imdbID: film.imdbID)
						statusSection
						ratingSection
						SynopsisSection(text: film.synopsis)
					}
					.frame(width: sideWidth)
				}
				triviaSection
				SpecsSection(specs: film.specs)
				notesSection
				Color.clear.frame(height: 20)
			}
		} else {
			VStack(alignment: .leading, spacing: 20) {
				header
				IMDbLinkButton(imdbID: film.imdbID)
				statusSection
				ratingSection
				SynopsisSection(text: film.synopsis)
				triviaSection
				SpecsSection(specs: film.specs)
				notesSection
				Color.clear.frame(height: 20)
			}
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
			StatusPicker(status: Binding(
				get: { film.status },
				set: { film.status = $0; film.personalUpdatedAt = .now }
			))
		}
	}

	private var ratingSection: some View {
		VStack(alignment: .leading, spacing: 10) {
			SectionLabel(text: "Rating", systemImage: "star.fill")
			RatingPicker(rating: Binding(
				get: { film.rating },
				set: { film.rating = $0; film.personalUpdatedAt = .now }
			))
		}
	}

	private var triviaSection: some View {
		TriviaSection(trivia: film.trivia, isLoading: loadingTrivia,
		              hasIMDb: !(film.imdbID ?? "").isEmpty)
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
