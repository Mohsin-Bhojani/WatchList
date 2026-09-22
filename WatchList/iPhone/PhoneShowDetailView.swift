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

struct PhoneShowDetailView: View {
	@Bindable var show: Show

	@Environment(\.modelContext) private var ctx
	@Environment(\.dismiss) private var dismiss
	@AppStorage("autoMarkEpisodesWatched") private var cascadeWatched = true

	@State private var compactBar = false
	@State private var ratingPopup: RatingPopup.Mode?
	@State private var ratingEpisode: Episode?
	@State private var showingArtwork = false
	@State private var confirmingRemove = false
	@State private var refreshing = false
	@State private var refreshNote: String?
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
			} rest: {
				seasonsSection
				PageSection(title: "Trailer") { PageTrailerCard(backdropURL: show.backdropURL) }
				if !show.overview.isEmpty { PageSynopsisCard(text: show.overview) }
				if let tmdbID = show.tmdbID {
					CommunitySection(title: .show(tmdbID: tmdbID), scale: .verdict, yours: show.rating?.rawValue)
				}
			}
		}
		.onScrollGeometryChange(for: Bool.self) { geometry in
			geometry.contentOffset.y + geometry.contentInsets.top > 290
		} action: { _, pastTitle in
			withAnimation(.easeInOut(duration: 0.2)) { compactBar = pastTitle }
		}
		.blur(radius: ratingPopup == nil ? 0 : 10)
		.overlay {
			if let mode = ratingPopup {
				RatingPopup(subject: RatingSubject(show: show), mode: mode, tint: pageColor) {
					withAnimation(Glass.smooth) { ratingPopup = nil }
				}
				.transition(.opacity.combined(with: .scale(scale: 0.96)))
			}
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

	// MARK: Up next

	private var upNextSection: some View {
		PageSection(title: "Up next") {
			VStack(alignment: .leading, spacing: 12) {
				if let next {
					HStack(spacing: 12) {
						NavigationLink { PhoneEpisodeView(episode: next) } label: {
							HStack(spacing: 12) {
								PosterImage(urlString: next.stillURL.isEmpty ? show.backdropURL : next.stillURL,
								            systemPlaceholder: "film")
									.frame(width: 88, height: 50)
									.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
									.overlay {
										Image(systemName: "play.fill")
											.font(.system(size: 12, weight: .bold))
											.foregroundStyle(.white.opacity(0.85))
									}
								VStack(alignment: .leading, spacing: 3) {
									Text("\(ShowFacts.code(next)) · \(next.displayTitle)")
										.font(.system(size: 13, weight: .bold))
										.foregroundStyle(.white)
										.lineLimit(2)
									Text(ShowFacts.progressLine(watched: show.watchedEpisodeCount,
									                            total: show.episodeCount))
										.font(.system(size: 11, weight: .medium))
										.foregroundStyle(.white.opacity(0.6))
								}
								Spacer(minLength: 0)
							}
							.contentShape(Rectangle())
						}
						.buttonStyle(.plain)
						Button("Mark watched") { ratingEpisode = next }
							.font(.system(size: 12, weight: .semibold))
							.foregroundStyle(.white)
							.padding(.horizontal, 14)
							.frame(height: GlassControl.height)
							.glassEffect(.regular.tint(Self.watchingFill.opacity(0.25)), in: Capsule())
					}
				} else {
					HStack {
						Text(show.episodeCount == 0 ? "No episodes tracked yet"
						                            : "All \(ShowFacts.episodes(show.episodeCount)) watched")
							.font(.system(size: 14, weight: .semibold))
							.foregroundStyle(.white)
						Spacer()
						Button("Mark show watched", action: markWatched)
							.font(.system(size: 12, weight: .semibold))
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

	private var seasonsSection: some View {
		PageSection(title: "Seasons") {
			if show.seasons.isEmpty {
				Text(show.tmdbID == nil ? "No seasons yet."
				                        : "No seasons yet. Refresh metadata from the menu to look again.")
					.font(.system(size: 14, weight: .medium))
					.foregroundStyle(.white.opacity(0.7))
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(14)
					.liquidCard(cornerRadius: 20)
			} else {
				ScrollView(.horizontal) {
					HStack(alignment: .top, spacing: 10) {
						ForEach(show.sortedSeasons) { seasonCard($0) }
					}
					.padding(.horizontal, 18)
				}
				.scrollIndicators(.hidden)
				.padding(.horizontal, -18)
			}
		}
	}

	private func seasonCard(_ season: Season) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			NavigationLink { PhoneSeasonView(season: season) } label: {
				PosterImage(urlString: seasonArt(season), systemPlaceholder: "tv")
					.frame(width: 132, height: 76)
					.overlay {
						LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
					}
					.overlay(alignment: .bottomLeading) {
						VStack(alignment: .leading, spacing: 0) {
							Text(season.displayName)
								.font(.system(size: 12, weight: .bold))
								.lineLimit(1)
							Text(ShowFacts.episodes(season.episodes.count))
								.font(.system(size: 10, weight: .medium))
								.foregroundStyle(.white.opacity(0.75))
						}
						.foregroundStyle(.white)
						.padding(7)
					}
					.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
			}
			.buttonStyle(.pressable)
			Menu {
				VerdictMenuSection(item: season)
			} label: {
				VerdictChip(rating: season.rating, emptyLabel: "Rate")
			}
		}
		.padding(6)
		.liquidCard(cornerRadius: 14)
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

	// MARK: Sharing and removal

	/// IMDb's page when there is one, else TMDb's, else just the title.
	private func shareLink<Label: View>(@ViewBuilder label: @escaping () -> Label) -> some View {
		TitleShareLink(title: show.title,
		               links: [show.imdbID.flatMap(IMDb.titleURL), TitleLinks.tmdbTV(show.tmdbID)],
		               label: label)
	}

	private func remove() {
		ctx.delete(show, afterLeaving: dismiss)
	}
}
