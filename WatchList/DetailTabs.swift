//
//  DetailTabs.swift
//  WatchList
//
//  The Cast, Similar and Images tabs shown on the Show, Season, Episode and
//  Film pages.
//  Each one fetches the first time it is opened and reads from CreditsLoader's
//  session cache after that, so switching tabs costs nothing.
//
//  A page that comes back with nothing to show tells its parent through
//  `onLoaded`, which drops the tab rather than leaving an empty one behind.
//

import SwiftUI
import SwiftData

// MARK: - Cast

/// Which credits a Cast tab is showing. The four pages differ only in the
/// endpoint behind them and the flag each can raise.
enum CastSource: Hashable {
	case series(tvID: Int)
	case season(tvID: Int, season: Int)
	case episode(tvID: Int, season: Int, episode: Int)
	case movie(movieID: Int)
}

struct CastTabView: View {
	let source: CastSource
	/// Reports whether the first fetch found anything worth a tab.
	var onLoaded: (Bool) -> Void = { _ in }

	@State private var entries: [CastEntry] = []
	@State private var credits = TitleCredits()
	@State private var loading = true

	/// Episodes and films come from the plain `/credits` endpoints, which carry
	/// a director and writer but no episode counts. Series and seasons come from
	/// `/aggregate_credits`, which is the other way round.
	private var hasCrewPair: Bool {
		switch source {
		case .episode, .movie:  return true
		case .series, .season:  return false
		}
	}

	private var sectionTitle: String {
		switch source {
		case .series:  return "Series Cast"
		case .season:  return "Cast This Season"
		case .episode: return "Appearing"
		case .movie:   return "Cast"
		}
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			if hasCrewPair {
				let rows = crewRows
				if !rows.isEmpty { SpecRowsCard(rows: rows) }
			}

			HStack {
				SectionLabel(text: sectionTitle, systemImage: "person.2.fill")
				Spacer()
				if !hasCrewPair && !entries.isEmpty {
					Text("by episode count")
						.font(.system(size: 12, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
				}
			}

			if loading {
				HStack(spacing: 10) {
					ProgressView()
					Text("Pulling cast from TMDb…")
						.font(.system(size: 14, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(16)
				.glass(cornerRadius: 18)
			} else {
				ForEach(people) { CastRow(entry: $0) }
			}
		}
		.task { await load() }
	}

	private var people: [CastEntry] { hasCrewPair ? credits.people : entries }

	private var crewRows: [(String, String)] {
		var rows: [(String, String)] = []
		if !credits.directedBy.isEmpty { rows.append(("Directed by", credits.directedBy)) }
		if !credits.writtenBy.isEmpty { rows.append(("Written by", credits.writtenBy)) }
		return rows
	}

	private func load() async {
		switch source {
		case .series(let tvID):
			entries = await CreditsLoader.seriesCast(tvID: tvID)
		case .season(let tvID, let season):
			entries = await CreditsLoader.seasonCast(tvID: tvID, season: season)
		case .episode(let tvID, let season, let episode):
			credits = await CreditsLoader.episodeCredits(tvID: tvID, season: season, episode: episode)
		case .movie(let movieID):
			credits = await CreditsLoader.movieCast(movieID: movieID)
		}
		loading = false
		onLoaded(hasCrewPair ? !credits.isEmpty : !entries.isEmpty)
	}
}

// MARK: - Similar

/// Which `/similar` list a Similar tab is showing, and therefore what an added
/// row becomes: a Show or a Film.
enum SimilarSource: Hashable {
	case series(tvID: Int)
	case movie(movieID: Int)

	var kind: MediaKind {
		switch self {
		case .series: return .show
		case .movie:  return .film
		}
	}
}

/// Titles TMDb considers similar to this one, each addable to the library as
/// To Watch. A season shows its series' list — TMDb has no per-season notion of
/// similarity.
struct SimilarTitlesTab: View {
	let source: SimilarSource
	let parentGenres: String
	var onLoaded: (Bool) -> Void = { _ in }

	@Environment(\.modelContext) private var ctx
	@Query private var shows: [Show]
	@Query private var films: [Film]

	@State private var entries: [SimilarEntry] = []
	@State private var loading = true
	@State private var adding: Set<Int> = []

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				SectionLabel(text: "Similar to this", systemImage: "square.on.square")
				Spacer()
				Text("via TMDb")
					.font(.system(size: 12, weight: .medium, design: .rounded))
					.foregroundStyle(.tertiary)
			}

			if loading {
				HStack(spacing: 10) {
					ProgressView()
					Text("Pulling similar titles from TMDb…")
						.font(.system(size: 14, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(16)
				.glass(cornerRadius: 18)
			} else {
				ForEach(entries) { entry in
					SimilarRow(entry: entry,
					           placeholder: source.kind == .film ? "film" : "tv",
					           inLibrary: inLibrary(entry),
					           isAdding: adding.contains(entry.id)) {
						add(entry)
					}
				}
			}
		}
		.task {
			switch source {
			case .series(let tvID):
				entries = await CreditsLoader.similar(tvID: tvID, parentGenres: parentGenres)
			case .movie(let movieID):
				entries = await CreditsLoader.similar(movieID: movieID, parentGenres: parentGenres)
			}
			loading = false
			onLoaded(!entries.isEmpty)
		}
	}

	/// TMDb numbers films and shows in separate id spaces, so this only ever
	/// checks the list the row would be added to.
	private func inLibrary(_ entry: SimilarEntry) -> Bool {
		switch source {
		case .series: return shows.contains { $0.tmdbID == entry.id }
		case .movie:  return films.contains { $0.tmdbID == entry.id }
		}
	}

	/// Imported through the normal path, so it lands as To Watch and unrated —
	/// the same as adding it by hand. On success `inLibrary` starts matching it
	/// and the row swaps to the ✓ on its own.
	private func add(_ entry: SimilarEntry) {
		adding.insert(entry.id)
		Haptics.tap(.medium)
		Task {
			let importer = ImportCoordinator()
			// A show pulls every season and episode, so this can take a few
			// seconds — the spinner covers the whole await.
			let imported = await importer.importFromTMDb(id: entry.id, kind: source.kind, into: ctx)
			withAnimation(Glass.smooth) { _ = adding.remove(entry.id) }
			imported == nil ? Haptics.warning() : Haptics.success()
		}
	}
}

// MARK: - Images

/// Which artwork an Images tab is showing. Mirrors CastSource: the four pages
/// differ only in the endpoint behind them.
enum ImageSource: Hashable {
	case series(tvID: Int)
	case season(tvID: Int, season: Int)
	case episode(tvID: Int, season: Int, episode: Int)
	case movie(movieID: Int)
}

/// Every image TMDb holds for this title, season or episode — posters,
/// backdrops, logos and stills, grouped by kind and in every language, since
/// the untitled artwork is usually the point. Tapping one opens it full size,
/// with the rest of the gallery a swipe away.
struct ImagesTabView: View {
	let source: ImageSource
	/// Reports whether the first fetch found anything worth a tab.
	var onLoaded: (Bool) -> Void = { _ in }

	@State private var gallery = ImageGallery()
	@State private var loading = true
	@State private var viewing: ImageEntry?

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			HStack {
				SectionLabel(text: "Images", systemImage: "photo.on.rectangle.angled")
				Spacer()
				Text(loading ? "via TMDb" : "\(gallery.count) via TMDb")
					.font(.system(size: 12, weight: .medium, design: .rounded))
					.foregroundStyle(.tertiary)
			}

			if loading {
				HStack(spacing: 10) {
					ProgressView()
					Text("Pulling artwork from TMDb…")
						.font(.system(size: 14, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(16)
				.glass(cornerRadius: 18)
			} else {
				ForEach(gallery.groups) { group in
					VStack(alignment: .leading, spacing: 10) {
						// Only worth a heading when there's more than one kind —
						// a season's tab is posters and nothing else.
						if gallery.groups.count > 1 { heading(group) }
						grid(group)
					}
				}
			}
		}
		.task { await load() }
		.fullScreenCover(item: $viewing) { entry in
			ImageViewer(entries: gallery.all, start: entry)
		}
	}

	private func heading(_ group: ImageGroup) -> some View {
		HStack(spacing: 6) {
			Text(group.kind.title)
				.font(Glass.serif(15, .semibold))
				.foregroundStyle(.primary)
			Text("\(group.entries.count)")
				.font(.system(size: 12, weight: .semibold, design: .rounded))
				.foregroundStyle(.secondary)
		}
	}

	private func grid(_ group: ImageGroup) -> some View {
		LazyVGrid(columns: columns(for: group.kind), spacing: 10) {
			ForEach(group.entries) { entry in
				Button {
					Haptics.tap()
					viewing = entry
				} label: {
					ImageTile(entry: entry)
				}
				.buttonStyle(.pressable)
			}
		}
	}

	/// Portrait art packs tighter than landscape; the maximums stop a two-poster
	/// group stretching across an iPad.
	private func columns(for kind: ImageEntry.Kind) -> [GridItem] {
		switch kind {
		case .poster:           return [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 10)]
		case .still, .backdrop: return [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 10)]
		case .logo:             return [GridItem(.adaptive(minimum: 130, maximum: 200), spacing: 10)]
		}
	}

	private func load() async {
		switch source {
		case .series(let tvID):
			gallery = await CreditsLoader.seriesImages(tvID: tvID)
		case .season(let tvID, let season):
			gallery = await CreditsLoader.seasonImages(tvID: tvID, season: season)
		case .episode(let tvID, let season, let episode):
			gallery = await CreditsLoader.episodeImages(tvID: tvID, season: season, episode: episode)
		case .movie(let movieID):
			gallery = await CreditsLoader.movieImages(movieID: movieID)
		}
		loading = false
		onLoaded(!gallery.isEmpty)
	}
}
