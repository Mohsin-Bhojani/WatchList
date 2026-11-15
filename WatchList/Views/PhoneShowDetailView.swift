//
//  PhoneShowDetailView.swift
//  WatchList
//
//  The iPhone show page, after the "Show view" design:
//    - the poster, title and a meta line: TMDb stars and votes, year, seasons
//    - a To watch / Watched switch, with a third Watching side while in progress;
//      marking Watched asks how it was
//    - Watching: Up next — the episode you're on, how far through, Mark watched
//    - Watched: your verdict — verdict, stars, when you finished, private note
//    - Seasons, each opening its page and rated from its chip
//    - trailer, synopsis and Everyone on WatchList
//    - a status menu in the bar: status, rating, share, artwork, refresh, remove
//    - a compact bar with the poster, title and where you are, once scrolled
//  Add to collection uses your own collections (TitleCollection). The community
//  verdict, the trailer and sharing with friends aren't built yet; each keeps
//  its place with a placeholder.
//
//  Everything it changes is a field Show, Season and Episode already have, so
//  the library store is untouched.
//

import SwiftUI
import SwiftData
import WatchListCore
import WatchListLibrary

struct PhoneShowDetailView: View {
	@Bindable var show: Show

	@Environment(\.modelContext) private var ctx
	@Environment(\.dismiss) private var dismiss
	@AppStorage("autoMarkEpisodesWatched") private var cascadeWatched = true

	@State private var compactBar = false
	@State private var ratingPopup: RatingPopup.Mode?
	/// The season the Seasons tabs are on, once one is picked.
	@State private var pickedSeason: UUID?
	@State private var ratingEpisode: Episode?
	@State private var showingArtwork = false
	@State private var confirmingRemove = false
	@State private var refreshing = false
	@State private var refreshNote: String?
	@State private var linkingYouTube = false
	@AppStorage(ExperimentalFeatures.youTubeEpisodes) private var youTubeEpisodes = false
	@State private var youtubeNote: String?
	@State private var namingCollection = false
	@State private var theme: UIColor?
	@State private var votes: Votes?

	private struct Votes { let average: Double; let count: Int }
	/// TMDb's figures by show, fetched once a session: Show doesn't keep them.
	private static var voteCache: [Int: Votes] = [:]

	/// Watching's side of the switch.
	static let watchingFill = Color(.pageWatching)

	init(show: Show) {
		_show = Bindable(show)
		_theme = State(initialValue: PageTheme.cached(show.posterURL.isEmpty ? show.backdropURL : show.posterURL))
		_votes = State(initialValue: show.tmdbID.flatMap { Self.voteCache[$0] })
	}

	private var artURL: String { show.posterURL.isEmpty ? show.backdropURL : show.posterURL }
	private var pageColor: Color { Color(uiColor: theme ?? PageTheme.fallback) }
	private var pageDeep: Color { Color(uiColor: ArtworkBand.deeper(theme ?? PageTheme.fallback)) }
	private var next: Episode? { HomeFeed.nextEpisode(of: show) }
	private var shownStars: Double? { show.shownStars }

	var body: some View {
		ScrollView {
			TitlePageColumns {
				header
				statusSwitch
				if show.status == .watched { verdictSection }
				if show.status == .watching { upNextSection }
				// On a wide iPad the trailer sits under the poster.
				PageColumnsReader { twoColumns in
					if twoColumns { trailer }
				}
			} rest: {
				// On a phone: above the seasons, unless Up next is there to lead.
				PageColumnsReader { twoColumns in
					if !twoColumns && show.status != .watching { trailer }
				}
				seasonsSection
				PageColumnsReader { twoColumns in
					if !twoColumns && show.status == .watching { trailer }
				}
				if !show.overview.isEmpty { PageSynopsisCard(text: show.overview) }
				WhereToWatchSection(kind: .show, tmdbID: show.tmdbID)
				if let tmdbID = show.tmdbID {
					CommunitySection(title: .show(tmdbID: tmdbID), scale: .verdict, yours: show.rating?.rawValue)
				}
				ReviewsSection(kind: .show, tmdbID: show.tmdbID)
			}
		}
		.onScrollGeometryChange(for: Bool.self) { geometry in
			geometry.contentOffset.y + geometry.contentInsets.top > 290
		} action: { _, pastTitle in
			withAnimation(.easeInOut(duration: 0.2)) { compactBar = pastTitle }
		}
		.sheet(item: $ratingPopup) { mode in
			RatingPopup(subject: RatingSubject(show: show), mode: mode, tint: pageColor) { ratingPopup = nil }
		}
		.titlePage(color: theme, compactBar: compactBar)
		.toolbar {
			ToolbarItem(placement: .principal) {
				if compactBar {
					PageCompactTitle(posterURL: show.posterURL, placeholder: "tv", title: show.title,
					                 subtitle: ShowFacts.listLine(status: show.status,
					                                              watched: show.watchedEpisodeCount,
					                                              total: show.episodeCount,
					                                              nextCode: next.map(ShowFacts.code)))
						.transition(.opacity)
				}
			}
			ToolbarItem(placement: .topBarTrailing) { statusMenu }
		}
		.sheet(item: $ratingEpisode) { EpisodeRatingSheet(episode: $0) }
		.sheet(isPresented: $showingArtwork) {
			if let tmdbID = show.tmdbID {
				ArtworkSheet(source: .series(tvID: tmdbID),
				             target: ArtworkTarget(id: show.id,
				                                   current: [.poster: show.posterURL, .landscape: show.backdropURL],
				                                   apply: [.poster: { show.posterURL = $0 },
				                                           .landscape: { show.backdropURL = $0 }]))
			}
		}
		.newCollectionAlert(isPresented: $namingCollection, adding: show.id)
		.confirmationDialog("Remove \u{201C}\(show.title)\u{201D}?", isPresented: $confirmingRemove,
		                    titleVisibility: .visible) {
			Button("Remove from Library", role: .destructive, action: remove)
		} message: {
			Text("Its seasons, episodes, ratings and note are removed with it.")
		}
		.alert("Refresh metadata", isPresented: Binding(get: { refreshNote != nil },
		                                                 set: { if !$0 { refreshNote = nil } })) {
			Button("OK", role: .cancel) {}
		} message: {
			Text(refreshNote ?? "")
		}
		.task(id: artURL) { await loadTheme() }
		.task(id: show.tmdbID) { await loadVotes() }
		// A linked playlist is looked over for new uploads every few hours.
		.task(id: show.id) {
			if youTubeEpisodes { await YouTubeLinker.refreshIfDue(show, context: ctx) }
		}
		.sheet(isPresented: $linkingYouTube) {
			YouTubePlaylistSheet(mode: .link(show)) { youtubeNote = $0 }
		}
		.alert("YouTube", isPresented: Binding(get: { youtubeNote != nil },
		                                        set: { if !$0 { youtubeNote = nil } })) {
			Button("OK", role: .cancel) {}
		} message: {
			Text(youtubeNote ?? "")
		}
	}

	// MARK: Header

	/// The design's community verdict ("52% Perfection") isn't built, so it's
	/// left out of the meta line; Everyone on WatchList keeps its place.
	private var header: some View {
		PagePosterHeader(
			posterURL: show.posterURL, placeholder: "tv", title: show.title, voteAverage: votes?.average,
			metaParts: [votes.flatMap { $0.average > 0 ? FilmFacts.count($0.count) : nil },
			            show.firstAirYear.isEmpty ? nil : show.firstAirYear,
			            show.seasons.isEmpty ? nil : ShowFacts.seasons(show.seasons.count)].compactMap { $0 })
	}

	private func loadTheme() async {
		guard let sampled = await PageTheme.load(artURL), !Task.isCancelled, sampled != theme else { return }
		withAnimation(.easeOut(duration: 0.4)) { theme = sampled }
	}

	private func loadVotes() async {
		guard let tmdbID = show.tmdbID, votes == nil, TMDbConfig.isConfigured else { return }
		guard let tv = try? await TMDbService.shared.tv(id: tmdbID), !Task.isCancelled else { return }
		let fetched = Votes(average: tv.vote_average ?? 0, count: tv.vote_count ?? 0)
		Self.voteCache[tmdbID] = fetched
		votes = fetched
	}

	// MARK: Status

	private var statusSwitch: some View {
		var options = [
			PageSwitchOption(title: "To watch", selected: show.status == .toWatch, fill: .white) {
				setStatus(.toWatch)
			},
			PageSwitchOption(title: "Watched", systemImage: show.status == .watched ? "checkmark" : nil,
			                 selected: show.status == .watched, fill: PhoneFilmDetailView.teal) {
				markWatched()
			},
		]
		if show.status == .watching {
			options.append(PageSwitchOption(title: next.map { "Watching · \(ShowFacts.code($0))" } ?? "Watching",
			                                systemImage: "play.fill", selected: true, fill: Self.watchingFill) {})
		}
		return PageSwitch(options: options, selectedText: pageDeep)
			.padding(.top, 2)
	}

	private func setStatus(_ status: WatchStatus) {
		guard show.status != status else { return }
		withAnimation(Glass.smooth) { show.mark(status) }
	}

	/// Marks it Watched — every season and episode too, when the "Mark all
	/// episodes watched" setting is on — and asks how it was. Already Watched,
	/// it opens the rating to change.
	private func markWatched() {
		if show.status == .watched {
			withAnimation(Glass.smooth) { ratingPopup = .edit }
			return
		}
		withAnimation(Glass.smooth) {
			show.mark(.watched)
			if cascadeWatched {
				for season in show.seasons {
					season.status = .watched
					for episode in season.episodes { episode.mark(.watched) }
				}
			}
			ratingPopup = .justMarked
		}
		Haptics.success()
	}

	// MARK: Your verdict

	private var verdictSection: some View {
		PageSection(title: "Your verdict") {
			PageVerdictCard(rating: show.rating, stars: shownStars,
			                dateLine: show.watchedAt.map { "Finished \(FilmFacts.shortDate($0))" },
			                note: show.notes, noteLabel: "Private note · show") {
				withAnimation(Glass.smooth) { ratingPopup = .edit }
			}
		}
	}

	private var trailer: some View {
		TitleTrailerSection(kind: .show, tmdbID: show.tmdbID, backdropURL: show.backdropURL)
	}

	// MARK: Up next

	private var upNextSection: some View {
		PageSection(title: "Up next") {
			VStack(alignment: .leading, spacing: 12) {
				if let next {
					// After design B: the still large, play-style, with where you are on
					// it; Mark Watched and the season's episodes under it.
					NavigationLink { PhoneEpisodeView(episode: next) } label: {
						PosterImage(urlString: next.stillURL.isEmpty ? show.backdropURL
						            : next.stillURL.replacingOccurrences(of: "/t/p/w300/", with: "/t/p/w780/"),
						            systemPlaceholder: "film")
							.aspectRatio(16 / 9, contentMode: .fit)
							.frame(maxWidth: .infinity)
							.overlay {
								LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
							}
							.overlay(alignment: .bottomLeading) {
								VStack(alignment: .leading, spacing: 4) {
									Text(["UP NEXT", ShowFacts.code(next),
									      (next.runtimeMinutes ?? next.specs?.runtimeMinutes).map { "\($0) min" }]
										.compactMap { $0 }.joined(separator: " · "))
										.font(.system(.caption2, weight: .bold))
										.foregroundStyle(.white.opacity(0.85))
									Text(next.displayTitle)
										.font(.system(.title3, weight: .bold))
										.foregroundStyle(.white)
										.lineLimit(2)
								}
								.padding(14)
							}
							.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
					}
					.buttonStyle(.pressable)
					HStack(spacing: 8) {
						Button { ratingEpisode = next } label: {
							Label("Mark Watched", systemImage: "checkmark")
								.font(.system(.subheadline, weight: .semibold))
								.foregroundStyle(.black)
								.frame(maxWidth: .infinity, minHeight: GlassControl.height)
								.background(.white, in: Capsule())
						}
						.buttonStyle(.pressable)
						if let season = next.season {
							NavigationLink { PhoneSeasonView(season: season) } label: {
								Text("Episodes")
									.font(.system(.subheadline, weight: .semibold))
									.foregroundStyle(.white)
									.padding(.horizontal, 18)
									.frame(minHeight: GlassControl.height)
							}
							.buttonStyle(.plain)
							.glassEffect(.regular.interactive(), in: Capsule())
						}
					}
				} else if let waiting = HomeFeed.nextToAir(of: show) {
					// Caught up: nothing out to mark, and the show isn't finished.
					VStack(alignment: .leading, spacing: 3) {
						Text(AirDate.caughtUpLine(nextAirDate: waiting.airDate))
							.font(.system(.subheadline, weight: .semibold))
							.foregroundStyle(.white)
						Text("\(ShowFacts.code(waiting)) · \(waiting.displayTitle)")
							.font(.system(.caption2, weight: .medium))
							.foregroundStyle(.white.opacity(0.6))
							.lineLimit(1)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.accessibilityElement(children: .combine)
				} else {
					HStack {
						Text(show.episodeCount == 0 ? "No episodes tracked yet"
						                            : "All \(ShowFacts.episodes(show.episodeCount)) watched")
							.font(.system(.subheadline, weight: .semibold))
							.foregroundStyle(.white)
						Spacer()
						Button("Mark show watched", action: markWatched)
							.font(.system(.caption, weight: .semibold))
							.foregroundStyle(.white)
							.padding(.horizontal, 14)
							.frame(height: GlassControl.height)
							.glassEffect(.regular, in: Capsule())
					}
				}
				progressBar
			}
			.padding(14)
			.liquidCard(cornerRadius: 20)
		}
	}

	private var progressBar: some View {
		let fraction = ShowFacts.fraction(watched: show.watchedEpisodeCount, total: show.episodeCount)
		return Capsule()
			.fill(.white.opacity(0.12))
			.frame(height: 4)
			.overlay(alignment: .leading) {
				GeometryReader { proxy in
					Capsule()
						.fill(Self.watchingFill)
						.frame(width: proxy.size.width * fraction)
				}
			}
			.accessibilityElement()
			.accessibilityLabel("Progress")
			.accessibilityValue(ShowFacts.progressLine(watched: show.watchedEpisodeCount, total: show.episodeCount))
	}

	// MARK: Seasons

	/// After design B of the alternatives: the seasons as tabs — each saying
	/// how far through it you are — over the chosen season's episodes, each
	/// numbered in a disc of its rating's colour. The season's own page, with
	/// its verdict and artwork, is a tap on its name.
	private var seasonsSection: some View {
		PageSection(title: "Seasons") {
			if show.seasons.isEmpty {
				Text(show.tmdbID == nil ? "No seasons yet."
				                        : "No seasons yet. Refresh metadata from the menu to look again.")
					.font(.system(.subheadline, weight: .medium))
					.foregroundStyle(.white.opacity(0.7))
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(14)
					.liquidCard(cornerRadius: 20)
			} else {
				let current = shownSeason
				VStack(alignment: .leading, spacing: 10) {
					ScrollView(.horizontal) {
						HStack(spacing: 6) {
							ForEach(show.sortedSeasons) { seasonTab($0, chosen: $0.id == current?.id) }
						}
						.padding(.horizontal, 18)
					}
					.scrollIndicators(.hidden)
					.padding(.horizontal, -18)
					if let current {
						VStack(spacing: 0) {
							ForEach(Array(current.sortedEpisodes.enumerated()), id: \.element.id) { index, episode in
								if index > 0 { PageRowDivider(inset: 106) }
								seasonEpisodeRow(episode)
									.contextMenu { EpisodeWatchedMenuItems(episode: episode) }
							}
							PageRowDivider(inset: 0)
							NavigationLink { PhoneSeasonView(season: current) } label: {
								HStack {
									Text("\(current.displayName) page")
										.font(.system(.subheadline, weight: .semibold))
									Spacer()
									VerdictChip(rating: current.rating, emptyLabel: "Rate")
									Image(systemName: "chevron.right")
										.font(.system(.caption, weight: .bold))
										.foregroundStyle(.white.opacity(0.5))
								}
								.foregroundStyle(.white)
								.padding(.vertical, 12)
								.contentShape(Rectangle())
							}
							.buttonStyle(.plain)
						}
						.padding(.horizontal, 14)
						.padding(.vertical, 4)
						.liquidCard(cornerRadius: 20)
					}
					youtubeLine
				}
			}
		}
	}

	/// Under the episodes: where they play from YouTube, or the way to make
	/// them — the same as the menu's Link YouTube Playlist.
	@ViewBuilder private var youtubeLine: some View {
		if youTubeEpisodes, YouTubeConfig.isConfigured {
			let linked = !YouTubeLibrary.linkedSeasons(of: show).isEmpty
			Button { linkingYouTube = true } label: {
				Label(linked ? "Episodes play from YouTube · Link another playlist"
				             : "Episodes on YouTube? Link a playlist to watch them here",
				      systemImage: "play.rectangle")
					.font(.system(.footnote, weight: .semibold))
					.foregroundStyle(.white.opacity(0.75))
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.horizontal, 4)
					.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
		}
	}

	/// The season the tabs show: the one picked, else the one you're in — where
	/// the next episode is — else the last.
	private var shownSeason: Season? {
		let seasons = show.sortedSeasons
		if let pickedSeason, let picked = seasons.first(where: { $0.id == pickedSeason }) { return picked }
		return next?.season ?? seasons.last { $0.seasonNumber > 0 } ?? seasons.last
	}

	private func seasonTab(_ season: Season, chosen: Bool) -> some View {
		let total = season.episodes.count
		let watched = season.watchedCount
		let label = season.seasonNumber == 0 ? "Specials" : "Season \(season.seasonNumber)"
		let progress = total > 0 && watched == total ? " ✓" : watched > 0 ? " · \(watched)/\(total)" : ""
		return Button {
			Haptics.selection()
			withAnimation(Glass.smooth) { pickedSeason = season.id }
		} label: {
			Text(label + progress)
				.font(.system(.footnote, weight: .semibold))
				.foregroundStyle(chosen ? Color.black : .white)
				.padding(.horizontal, 14)
				.frame(minHeight: 36)
				.background(chosen ? AnyShapeStyle(.white) : AnyShapeStyle(.white.opacity(0.12)), in: Capsule())
		}
		.buttonStyle(.plain)
		.accessibilityAddTraits(chosen ? .isSelected : [])
	}

	private func seasonEpisodeRow(_ episode: Episode) -> some View {
		let watched = episode.status == .watched
		let aired = AirDate.hasAired(episode.airDate, today: AirDate.day(.now)) ?? true
		return HStack(spacing: 10) {
			EpisodeStillLead(episode: episode) { tier in
				withAnimation(Glass.smooth) { episode.episodeTier = tier }
			}
			NavigationLink { PhoneEpisodeView(episode: episode) } label: {
				VStack(alignment: .leading, spacing: 2) {
					Text(episode.displayTitle)
						.font(.system(.subheadline, weight: .semibold))
						.foregroundStyle(.white.opacity(aired ? 1 : 0.7))
						.lineLimit(1)
					Text(watched ? episode.watchedAt.map { "Watched \(FilmFacts.shortDate($0))" } ?? "Watched"
					     : aired ? (FilmFacts.runtime(episode.runtimeMinutes) ?? "Not watched")
					     : AirDate.phrase(episode.airDate).map { "Airs \($0)" } ?? "Coming")
						.font(.system(.caption, weight: .medium))
						.foregroundStyle(.white.opacity(0.6))
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			if aired {
				Button {
					Haptics.selection()
					withAnimation(Glass.smooth) { watched ? episode.mark(.toWatch) : episode.markWatched() }
				} label: {
					Image(systemName: watched ? "checkmark.circle.fill" : "circle")
						.font(.system(.title2, weight: .semibold))
						.foregroundStyle(watched ? PhoneFilmDetailView.teal : .white.opacity(0.5))
				}
				.buttonStyle(.plain)
				.accessibilityLabel(watched ? "Watched" : "Mark watched")
			}
		}
		.padding(.vertical, 9)
	}

	/// A season's card art: its first episode's still, else its poster, else the
	/// show's backdrop.
	private func seasonArt(_ season: Season) -> String {
		if let still = season.sortedEpisodes.first?.stillURL, !still.isEmpty { return still }
		return season.posterURL.isEmpty ? show.backdropURL : season.posterURL
	}

	// MARK: Menu

	/// The design's status menu.
	private var statusMenu: some View {
		Menu {
			StatusMenuSection(current: show.status) { status in
				status == .watched ? markWatched() : setStatus(status)
			}
			VerdictMenuSection(item: show)
			Section("Other") {
				shareLink { Label("Share", systemImage: "square.and.arrow.up") }
				Button { showingArtwork = true } label: {
					Label("Artwork", systemImage: "photo.on.rectangle")
				}
				.disabled(show.tmdbID == nil)
				AddToCollectionMenu(titleID: show.id) { namingCollection = true }
				Button { Task { await refresh() } } label: {
					Label(refreshing ? "Refreshing…" : "Refresh metadata", systemImage: "arrow.clockwise")
				}
				.disabled(show.tmdbID == nil || refreshing)
			}
			if youTubeEpisodes {
				Section("YouTube") {
					Button { linkingYouTube = true } label: {
						Label(YouTubeLibrary.linkedSeasons(of: show).isEmpty ? "Link YouTube Playlist…" : "Link Another Playlist…",
						      systemImage: "play.rectangle")
					}
					if !YouTubeLibrary.linkedSeasons(of: show).isEmpty {
						Button { Task { await updateFromYouTube() } } label: {
							Label("Check YouTube for New Episodes", systemImage: "arrow.clockwise")
						}
						Button(role: .destructive) {
							withAnimation(Glass.smooth) { YouTubeLibrary.linkedSeasons(of: show).forEach(YouTubeLibrary.unlink) }
						} label: {
							Label("Unlink YouTube", systemImage: "link.badge.minus")
						}
					}
				}
			}
			Section {
				Button(role: .destructive) { confirmingRemove = true } label: {
					Label("Remove from library", systemImage: "trash")
				}
			}
		} label: {
			PageStatusLabel(status: show.status, rating: show.rating)
		}
	}

	/// Looks TMDb over for seasons and episodes that aren't here yet. Additive
	/// only: nothing already in the library is changed.
	private func refresh() async {
		refreshing = true
		let report = await LibraryRefresher.refresh(show, into: ctx)
		refreshing = false
		if report.foundSomething {
			refreshNote = report.summary
		} else {
			refreshNote = report.showsFailed > 0 ? "Couldn't reach TMDb. Try again later." : "Everything's up to date."
		}
	}

	/// Looks every linked playlist over now, whenever it was last checked.
	private func updateFromYouTube() async {
		var report = YouTubeLibrary.Report()
		for season in YouTubeLibrary.linkedSeasons(of: show) {
			guard let id = season.youtubePlaylistID else { continue }
			do {
				let playlist = try await YouTubeService.shared.playlist(id: id)
				let found = YouTubeLinker.link(playlist, to: season, context: ctx)
				report.linked += found.linked
				report.added += found.added
			} catch {
				youtubeNote = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
				return
			}
		}
		youtubeNote = report.summary
	}

	// MARK: Sharing and removal

	/// IMDb's page when there is one, else TMDb's, else just the title.
	private func shareLink<Label: View>(@ViewBuilder label: @escaping () -> Label) -> some View {
		TitleShareLink(title: show.title,
		               links: [show.imdbID.flatMap(IMDb.titleURL), TitleLinks.tmdbTV(show.tmdbID)],
		               label: label)
	}

	private func remove() {
		ManualPosterStore.remove(show.posterURL)
		ctx.delete(show, afterLeaving: dismiss)
	}
}
