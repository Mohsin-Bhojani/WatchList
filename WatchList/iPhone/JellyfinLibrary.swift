//
//  JellyfinLibrary.swift
//  WatchList
//
//  On your server: everything on your Jellyfin server, whether or not it's in
//  your WatchList library or on TMDb — home videos, concerts, anything.
//    - a card on the Collections tab, with the server's name, how many films
//      and shows it has, and a fan of their posters
//    - its page: Films or Shows, as a grid of posters, each marked once
//      watched or with how far you got; a film plays on a tap, a show opens
//    - a show's page: its seasons, each episode a row that plays on a tap
//  Played through, a title that is also in your library is marked Watched
//  there too, as a page's own Play button does.
//

import SwiftUI
import SwiftData

// MARK: - Playing

enum ServerPlayback {
	/// Plays an item from the server; played through, it's marked Watched in
	/// the library too, when it's there. `onClose` follows, to show the new
	/// resume points.
	static func play(_ item: JellyfinItem, series: JellyfinItem? = nil, in ctx: ModelContext,
	                 onClose: @escaping () -> Void) async throws {
		let name = item.name ?? "Untitled"
		let subtitle: String? = if let series {
			[series.name, ServerLabels.code(item)].compactMap { $0 }.joined(separator: " · ")
		} else {
			item.productionYear.map(String.init)
		}
		let stream = try await JellyfinSession.shared.stream(for: item, title: name, subtitle: subtitle)
		MediaPlayer.play(stream) { watched in
			if watched { markWatched(item, series: series, in: ctx) }
			onClose()
		}
	}

	private static func markWatched(_ item: JellyfinItem, series: JellyfinItem?, in ctx: ModelContext) {
		if let series {
			let shows = (try? ctx.fetch(FetchDescriptor<Show>())) ?? []
			guard let episode = ServerMatch.episode(in: shows, series: series, item: item),
			      episode.status != .watched else { return }
			withAnimation(Glass.smooth) { episode.markWatched() }
		} else {
			let films = (try? ctx.fetch(FetchDescriptor<Film>())) ?? []
			guard let film = ServerMatch.film(in: films, item: item), film.status != .watched else { return }
			withAnimation(Glass.smooth) { film.mark(.watched) }
		}
	}
}

/// The library's own copy of something on the server, by TMDb id, else IMDb.
enum ServerMatch {
	static func film(in films: [Film], item: JellyfinItem) -> Film? {
		matching(films, item, tmdb: \.tmdbID, imdb: \.imdbID)
	}

	static func episode(in shows: [Show], series: JellyfinItem, item: JellyfinItem) -> Episode? {
		guard let show = matching(shows, series, tmdb: \.tmdbID, imdb: \.imdbID),
		      let season = item.parentIndexNumber, let first = item.indexNumber else { return nil }
		let numbers = first...max(first, item.indexNumberEnd ?? first)
		return show.seasons.flatMap(\.episodes).first {
			$0.seasonNumber == season && numbers.contains($0.episodeNumber)
		}
	}

	private static func matching<T>(_ titles: [T], _ item: JellyfinItem,
	                                tmdb: KeyPath<T, Int?>, imdb: KeyPath<T, String?>) -> T? {
		if let id = item.providerID("Tmdb").flatMap(Int.init),
		   let found = titles.first(where: { $0[keyPath: tmdb] == id }) { return found }
		if let id = item.providerID("Imdb")?.lowercased(), !id.isEmpty {
			return titles.first { $0[keyPath: imdb]?.lowercased() == id }
		}
		return nil
	}
}

enum ServerLabels {
	/// "S01E03", or "S01E03–E04" for a double episode.
	static func code(_ episode: JellyfinItem) -> String {
		guard let number = episode.indexNumber else { return "" }
		let season = String(format: "S%02d", episode.parentIndexNumber ?? 0)
		if let end = episode.indexNumberEnd, end > number {
			return season + String(format: "E%02d–E%02d", number, end)
		}
		return season + String(format: "E%02d", number)
	}

	/// "12 films · 3 shows".
	static func counts(films: Int, shows: Int) -> String {
		"\(films) \(films == 1 ? "film" : "films") · \(shows) \(shows == 1 ? "show" : "shows")"
	}

	/// How far into it you are, 0…1; nil when unstarted or watched.
	static func progress(_ item: JellyfinItem) -> Double? {
		guard let resume = item.resumeSeconds, let ticks = item.runTimeTicks, ticks > 0 else { return nil }
		return min(1, resume / JellyfinTicks.seconds(ticks))
	}
}

// MARK: - The server's page

struct JellyfinServerView: View {
	private enum Kind: String, CaseIterable, Identifiable {
		case films = "Films", shows = "Shows"
		var id: Self { self }
		var type: String { self == .films ? "Movie" : "Series" }
	}

	@Environment(\.modelContext) private var ctx
	@Environment(\.horizontalSizeClass) private var sizeClass
	@State private var kind: Kind = .films
	@State private var items: [Kind: [JellyfinItem]] = [:]
	@State private var failure: String?
	@State private var starting: String?
	@State private var playFailure: String?
	@State private var compactBar = false

	private var session: JellyfinSession { .shared }

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				Picker("Kind", selection: $kind) {
					ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
				}
				.pickerStyle(.segmented)
				.padding(.top, 8)
				content
			}
			.padding(.horizontal, 18)
			.padding(.bottom, 32)
			.readableColumn()
		}
		.onScrollGeometryChange(for: Bool.self) { geometry in
			geometry.contentOffset.y + geometry.contentInsets.top > 8
		} action: { _, scrolled in
			withAnimation(.easeInOut(duration: 0.2)) { compactBar = scrolled }
		}
		.navigationTitle(session.account?.serverName ?? "Your server")
		.titlePage(color: nil, compactBar: compactBar)
		.task(id: kind) { await load(kind) }
		.refreshable { await load(kind) }
		.alert("Can't play this", isPresented: Binding(get: { playFailure != nil }, set: { if !$0 { playFailure = nil } })) {
			Button("OK", role: .cancel) {}
		} message: {
			Text(playFailure ?? "")
		}
	}

	@ViewBuilder private var content: some View {
		if let list = items[kind] {
			if list.isEmpty {
				ServerNote(text: kind == .films
					? "No films on the server yet. Add video files to its Movies library and they show up here."
					: "No shows on the server yet. Add them to its Shows library, a folder per show and one per season.")
			} else {
				LazyVGrid(columns: [GridItem(.adaptive(minimum: sizeClass == .regular ? 150 : 104), spacing: 12,
				                             alignment: .top)], spacing: 18) {
					ForEach(list) { item in tile(item) }
				}
			}
		} else if let failure {
			ServerNote(text: failure)
		} else {
			ProgressView()
				.tint(.white)
				.frame(maxWidth: .infinity)
				.padding(.top, 40)
		}
	}

	@ViewBuilder private func tile(_ item: JellyfinItem) -> some View {
		if kind == .shows {
			NavigationLink { JellyfinShowView(series: item) } label: { ServerPosterTile(item: item, loading: false) }
				.buttonStyle(.pressable)
		} else {
			Button {
				Haptics.tap()
				starting = item.id
				Task {
					do {
						try await ServerPlayback.play(item, in: ctx) { Task { await load(.films) } }
					} catch {
						playFailure = error.localizedDescription
					}
					starting = nil
				}
			} label: {
				ServerPosterTile(item: item, loading: starting == item.id)
			}
			.buttonStyle(.pressable)
			.disabled(starting != nil)
			.accessibilityHint("Plays it")
		}
	}

	private func load(_ kind: Kind) async {
		do {
			let list = try await session.items(ofType: kind.type)
			failure = nil
			withAnimation(Glass.smooth) { items[kind] = list }
		} catch is CancellationError {
		} catch {
			if items[kind] == nil { failure = "Couldn't reach the server: \(error.localizedDescription)" }
		}
	}
}

/// A poster, its name and year, and whether you've watched it or how far you got.
private struct ServerPosterTile: View {
	let item: JellyfinItem
	let loading: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			PosterImage(urlString: JellyfinSession.shared.imageURL(item), systemPlaceholder: "film")
				.aspectRatio(2 / 3, contentMode: .fit)
				.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
				.overlay(alignment: .topTrailing) {
					if item.userData?.played == true {
						Image(systemName: "checkmark.circle.fill")
							.font(.system(size: 18, weight: .semibold))
							.symbolRenderingMode(.palette)
							.foregroundStyle(.white, PhoneFilmDetailView.teal)
							.padding(6)
							.accessibilityLabel("Watched")
					}
				}
				.overlay(alignment: .bottom) {
					if let progress = ServerLabels.progress(item) { ServerProgressBar(progress: progress).padding(6) }
				}
				.overlay {
					if loading {
						ZStack {
							Color.black.opacity(0.4)
							ProgressView().tint(.white)
						}
						.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
					}
				}
			Text(item.name ?? "Untitled")
				.font(.system(size: 13, weight: .semibold))
				.foregroundStyle(.white)
				.lineLimit(2)
			if let year = item.productionYear {
				Text(String(year))
					.font(.system(size: 12, weight: .medium))
					.foregroundStyle(.white.opacity(0.6))
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.contentShape(Rectangle())
		.accessibilityElement(children: .combine)
	}
}

private struct ServerProgressBar: View {
	let progress: Double

	var body: some View {
		GeometryReader { geometry in
			Capsule().fill(.white.opacity(0.3))
				.overlay(alignment: .leading) {
					Capsule().fill(.white).frame(width: geometry.size.width * progress)
				}
		}
		.frame(height: 4)
		.accessibilityLabel("\(Int(progress * 100))% watched")
	}
}

private struct ServerNote: View {
	let text: String

	var body: some View {
		Text(text)
			.font(.system(size: 14, weight: .medium))
			.foregroundStyle(.white.opacity(0.75))
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(16)
			.liquidCard(cornerRadius: 20)
	}
}

// MARK: - A show's page

struct JellyfinShowView: View {
	let series: JellyfinItem

	@Environment(\.modelContext) private var ctx
	@State private var episodes: [JellyfinItem]?
	@State private var failure: String?
	@State private var starting: String?
	@State private var playFailure: String?
	@State private var compactBar = false

	private var seasons: [(number: Int, episodes: [JellyfinItem])] {
		Dictionary(grouping: episodes ?? []) { $0.parentIndexNumber ?? 0 }
			.sorted { $0.key < $1.key }
			.map { ($0.key, $0.value.sorted { ($0.indexNumber ?? 0) < ($1.indexNumber ?? 0) }) }
	}

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				HStack(alignment: .top, spacing: 14) {
					PosterImage(urlString: JellyfinSession.shared.imageURL(series), systemPlaceholder: "tv")
						.frame(width: 96, height: 144)
						.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
					VStack(alignment: .leading, spacing: 6) {
						Text(series.name ?? "Untitled")
							.font(.system(size: 24, weight: .bold))
							.foregroundStyle(.white)
							.accessibilityAddTraits(.isHeader)
						if let year = series.productionYear {
							Text(String(year))
								.font(.system(size: 14, weight: .medium))
								.foregroundStyle(.white.opacity(0.7))
						}
						if let overview = series.overview, !overview.isEmpty {
							Text(overview)
								.font(.system(size: 13, weight: .medium))
								.foregroundStyle(.white.opacity(0.75))
								.lineLimit(5)
						}
					}
				}
				.padding(.top, 8)

				if let episodes {
					if episodes.isEmpty {
						ServerNote(text: "No episodes found. Jellyfin wants them in season folders, named like \u{201C}Show S01E01\u{201D}.")
					}
					ForEach(seasons, id: \.number) { season in
						PageSection(title: season.number == 0 ? "Specials" : "Season \(season.number)") {
							VStack(spacing: 0) {
								ForEach(Array(season.episodes.enumerated()), id: \.element.id) { index, episode in
									if index > 0 { PageRowDivider() }
									episodeRow(episode)
								}
							}
							.padding(.vertical, 4)
							.liquidCard(cornerRadius: 20)
						}
					}
				} else if let failure {
					ServerNote(text: failure)
				} else {
					ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 30)
				}
			}
			.padding(.horizontal, 18)
			.padding(.bottom, 32)
			.readableColumn()
		}
		.onScrollGeometryChange(for: Bool.self) { geometry in
			geometry.contentOffset.y + geometry.contentInsets.top > 8
		} action: { _, scrolled in
			withAnimation(.easeInOut(duration: 0.2)) { compactBar = scrolled }
		}
		.navigationTitle(compactBar ? (series.name ?? "") : "")
		.titlePage(color: nil, compactBar: compactBar)
		.task { await load() }
		.refreshable { await load() }
		.alert("Can't play this", isPresented: Binding(get: { playFailure != nil }, set: { if !$0 { playFailure = nil } })) {
			Button("OK", role: .cancel) {}
		} message: {
			Text(playFailure ?? "")
		}
	}

	private func episodeRow(_ episode: JellyfinItem) -> some View {
		Button {
			Haptics.tap()
			starting = episode.id
			Task {
				do {
					try await ServerPlayback.play(episode, series: series, in: ctx) { Task { await load() } }
				} catch {
					playFailure = error.localizedDescription
				}
				starting = nil
			}
		} label: {
			HStack(spacing: 12) {
				PosterImage(urlString: JellyfinSession.shared.imageURL(episode, height: 180), systemPlaceholder: "tv")
					.frame(width: 104, height: 58)
					.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
					.overlay(alignment: .bottom) {
						if let progress = ServerLabels.progress(episode) {
							ServerProgressBar(progress: progress).padding(4)
						}
					}
					.overlay {
						if starting == episode.id {
							ZStack {
								Color.black.opacity(0.4)
								ProgressView().tint(.white)
							}
							.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
						}
					}
				VStack(alignment: .leading, spacing: 3) {
					Text(ServerLabels.code(episode))
						.font(.system(size: 11, weight: .semibold, design: .monospaced))
						.foregroundStyle(.white.opacity(0.6))
					Text(episode.name ?? "Episode \(episode.indexNumber ?? 0)")
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(.white)
						.lineLimit(2)
						.multilineTextAlignment(.leading)
					if let ticks = episode.runTimeTicks, let runtime = FilmFacts.runtime(Int(JellyfinTicks.seconds(ticks) / 60)) {
						Text(runtime)
							.font(.system(size: 12, weight: .medium))
							.foregroundStyle(.white.opacity(0.6))
					}
				}
				Spacer(minLength: 0)
				Image(systemName: episode.userData?.played == true ? "checkmark.circle.fill" : "play.circle")
					.font(.system(size: 22, weight: .regular))
					.foregroundStyle(episode.userData?.played == true ? PhoneFilmDetailView.teal : .white.opacity(0.8))
					.accessibilityLabel(episode.userData?.played == true ? "Watched" : "")
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 10)
			.contentShape(Rectangle())
		}
		.buttonStyle(.pressable)
		.disabled(starting != nil)
		.accessibilityHint("Plays it")
	}

	private func load() async {
		do {
			let list = try await JellyfinSession.shared.episodes(ofSeries: series.id)
			failure = nil
			withAnimation(Glass.smooth) { episodes = list }
		} catch is CancellationError {
		} catch {
			if episodes == nil { failure = "Couldn't reach the server: \(error.localizedDescription)" }
		}
	}
}
