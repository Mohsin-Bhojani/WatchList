//
//  DetailTabs.swift
//  WatchList
//
//  The Cast and Similar tabs shown on Show, Season and Episode pages. Each one
//  fetches the first time it is opened and reads from CreditsLoader's session
//  cache after that, so switching tabs costs nothing.
//
//  A page that comes back with nothing to show tells its parent through
//  `onLoaded`, which drops the tab rather than leaving an empty one behind.
//
//  Nothing here touches the dock's Similar tab (SimilarView / SimilarLoader).
//

import SwiftUI
import SwiftData

// MARK: - Cast

/// Which credits a Cast tab is showing. The three pages differ only in the
/// endpoint behind them and the flag each can raise.
enum CastSource: Hashable {
	case series(tvID: Int)
	case season(tvID: Int, season: Int)
	case episode(tvID: Int, season: Int, episode: Int)
}

struct CastTabView: View {
	let source: CastSource
	/// Reports whether the first fetch found anything worth a tab.
	var onLoaded: (Bool) -> Void = { _ in }

	@State private var entries: [CastEntry] = []
	@State private var episodeCredits = EpisodeCredits()
	@State private var loading = true

	private var isEpisode: Bool {
		if case .episode = source { return true }
		return false
	}

	private var sectionTitle: String {
		switch source {
		case .series:  return "Series Cast"
		case .season:  return "Cast This Season"
		case .episode: return "Appearing"
		}
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			if isEpisode {
				let rows = crewRows
				if !rows.isEmpty { SpecRowsCard(rows: rows) }
			}

			HStack {
				SectionLabel(text: sectionTitle, systemImage: "person.2.fill")
				Spacer()
				if !isEpisode && !entries.isEmpty {
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

	private var people: [CastEntry] { isEpisode ? episodeCredits.people : entries }

	private var crewRows: [(String, String)] {
		var rows: [(String, String)] = []
		if !episodeCredits.directedBy.isEmpty { rows.append(("Directed by", episodeCredits.directedBy)) }
		if !episodeCredits.writtenBy.isEmpty { rows.append(("Written by", episodeCredits.writtenBy)) }
		return rows
	}

	private func load() async {
		switch source {
		case .series(let tvID):
			entries = await CreditsLoader.seriesCast(tvID: tvID)
		case .season(let tvID, let season):
			entries = await CreditsLoader.seasonCast(tvID: tvID, season: season)
		case .episode(let tvID, let season, let episode):
			episodeCredits = await CreditsLoader.episodeCredits(tvID: tvID, season: season, episode: episode)
		}
		loading = false
		onLoaded(isEpisode ? !episodeCredits.isEmpty : !entries.isEmpty)
	}
}

// MARK: - Similar

/// Titles TMDb considers similar to this show, each addable to the library as
/// To Watch. A season shows its series' list — TMDb has no per-season notion of
/// similarity.
struct SimilarTitlesTab: View {
	let tvID: Int
	let parentGenres: String
	var onLoaded: (Bool) -> Void = { _ in }

	@Environment(\.modelContext) private var ctx
	@Query private var shows: [Show]

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
					           inLibrary: inLibrary(entry),
					           isAdding: adding.contains(entry.id)) {
						add(entry)
					}
				}
			}
		}
		.task {
			entries = await CreditsLoader.similar(tvID: tvID, parentGenres: parentGenres)
			loading = false
			onLoaded(!entries.isEmpty)
		}
	}

	private func inLibrary(_ entry: SimilarEntry) -> Bool {
		shows.contains { $0.tmdbID == entry.id }
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
			let imported = await importer.importFromTMDb(id: entry.id, kind: .show, into: ctx)
			withAnimation(Glass.smooth) { _ = adding.remove(entry.id) }
			imported == nil ? Haptics.warning() : Haptics.success()
		}
	}
}
