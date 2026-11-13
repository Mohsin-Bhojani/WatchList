//
//  PhoneFranchiseView.swift
//  WatchList
//
//  A film series opened (Franchises.swift): its backdrop, how many you've
//  seen, and every film in it in release order. Yours open their pages and
//  show whether they're watched; the rest have Add, which puts them in your
//  library to watch.
//

import SwiftUI
import SwiftData
import WatchListCore
import WatchListLibrary

struct PhoneFranchiseView: View {
	let id: Int
	let name: String

	@Query private var films: [Film]
	@Environment(\.modelContext) private var ctx
	@StateObject private var importer = ImportCoordinator()

	@State private var series: TMDbCollection?
	@State private var failed = false
	@State private var adding: Int?

	private var parts: [TMDbCollectionPart] { Franchises.ordered(series?.parts ?? []) }
	private var today: String { AirDate.day(.now) }

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 16) {
				header
				if series == nil {
					Group {
						if failed {
							Text("Couldn't load this series. Check your connection and try again.")
						} else {
							ProgressView().frame(maxWidth: .infinity)
						}
					}
					.font(.system(.subheadline, weight: .medium))
					.foregroundStyle(.white.opacity(0.75))
					.padding(.vertical, 24)
				} else {
					VStack(spacing: 0) {
						ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
							if index > 0 { PageRowDivider(inset: 58) }
							row(part)
						}
					}
					.padding(.horizontal, 14)
					.liquidCard(cornerRadius: 20)
				}
			}
			.padding(18)
		}
		// As the person page does: a film page pushed from here sets its own
		// bar, and an inline title with a forced dark scheme fought it into a
		// layout loop that froze the app.
		.background(GlassBackground())
		// Named for the back button's menu; the page shows the name itself.
		.navigationTitle(name)
		.toolbar(removing: .title)
		.task(id: id) {
			if let loaded = await FranchiseLoader.collection(id: id) { series = loaded } else { failed = true }
		}
	}

	private var header: some View {
		VStack(alignment: .leading, spacing: 6) {
			if let backdrop = series?.backdrop_path {
				PosterImage(urlString: TMDbConfig.backdrop(backdrop), systemPlaceholder: "film")
					.aspectRatio(16 / 9, contentMode: .fit)
					.frame(maxWidth: .infinity)
					.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
					.accessibilityHidden(true)
			}
			Text(name)
				.font(.system(.title, weight: .bold))
				.foregroundStyle(.white)
				.accessibilityAddTraits(.isHeader)
			if series != nil {
				Text(Franchises.progress(parts: parts, films: films, today: today))
					.font(.system(.subheadline, weight: .medium))
					.foregroundStyle(.white.opacity(0.65))
			}
		}
	}

	@ViewBuilder private func row(_ part: TMDbCollectionPart) -> some View {
		let film = films.first { $0.tmdbID == part.id }
		let year = String((part.release_date ?? "").prefix(4))
		let released = (part.release_date).map { !$0.isEmpty && $0 <= today } ?? false
		let content = HStack(spacing: 12) {
			PosterImage(urlString: film?.posterURL ?? TMDbConfig.poster(part.poster_path), systemPlaceholder: "film")
				.frame(width: 44, height: 66)
				.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
			VStack(alignment: .leading, spacing: 3) {
				Text(part.title ?? "Untitled")
					.font(.system(.subheadline, weight: .semibold))
					.foregroundStyle(.white)
					.lineLimit(2)
				Text(released || year.isEmpty
				     ? (year.isEmpty ? "No date yet" : year)
				     : "Coming \(FilmFacts.releaseDate(part.release_date ?? "") ?? year)")
					.font(.system(.caption, weight: .medium))
					.foregroundStyle(.white.opacity(0.6))
			}
			Spacer(minLength: 8)
			trailing(part, film: film)
		}
		.padding(.vertical, 10)
		.contentShape(Rectangle())

		if let film {
			NavigationLink { PhoneFilmDetailView(film: film, showsSeriesLink: false) } label: { content }
				.buttonStyle(.plain)
		} else {
			content
		}
	}

	@ViewBuilder private func trailing(_ part: TMDbCollectionPart, film: Film?) -> some View {
		if let film {
			if film.status == .watched {
				Image(systemName: "checkmark.circle.fill")
					.font(.system(.title2, weight: .semibold))
					.foregroundStyle(PhoneFilmDetailView.teal)
					.accessibilityLabel("Watched")
			} else {
				Text("In your list")
					.font(.system(.caption, weight: .semibold))
					.foregroundStyle(.white.opacity(0.7))
			}
		} else if adding == part.id {
			ProgressView()
		} else {
			Button {
				add(part)
			} label: {
				Label("Add", systemImage: "plus")
					.font(.system(.footnote, weight: .semibold))
					.foregroundStyle(.white)
					.padding(.horizontal, 12)
					.frame(minHeight: 32)
					.glassEffect(.regular.interactive(), in: Capsule())
			}
			.buttonStyle(.plain)
			.disabled(adding != nil)
			.accessibilityLabel("Add \(part.title ?? "film") to your library")
		}
	}

	private func add(_ part: TMDbCollectionPart) {
		adding = part.id
		Haptics.tap(.medium)
		Task {
			let result = await importer.importFromTMDb(id: part.id, kind: .film, into: ctx)
			adding = nil
			result == nil ? Haptics.warning() : Haptics.success()
		}
	}
}

/// On a film's page: the series it's in, opening the series' page.
struct PageFranchiseLink: View {
	let id: Int
	let name: String

	var body: some View {
		NavigationLink { PhoneFranchiseView(id: id, name: name) } label: {
			HStack(spacing: 12) {
				Image(systemName: "rectangle.stack")
					.font(.system(.body, weight: .semibold))
					.frame(width: 36, height: 36)
					.background(.white.opacity(0.1), in: Circle())
				VStack(alignment: .leading, spacing: 2) {
					Text("Part of a series")
						.font(.system(.caption, weight: .medium))
						.foregroundStyle(.white.opacity(0.6))
					Text(name)
						.font(.system(.subheadline, weight: .semibold))
						.lineLimit(1)
				}
				Spacer(minLength: 8)
				Image(systemName: "chevron.right")
					.font(.system(.caption, weight: .bold))
					.foregroundStyle(.white.opacity(0.5))
			}
			.foregroundStyle(.white)
			.padding(14)
			.liquidCard(cornerRadius: 20)
			.contentShape(Rectangle())
		}
		.buttonStyle(.pressable)
		.accessibilityLabel("Part of the \(name) series")
	}
}
