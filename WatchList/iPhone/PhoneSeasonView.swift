//
//  PhoneSeasonView.swift
//  WatchList
//
//  The iPhone season page, in the "Show view" design's language:
//    - the season's poster, name, show and a meta line
//    - a To watch / Watched switch; marking Watched asks how it was
//    - your verdict, once watched or rated
//    - the episodes, each opening its page, with a watched tick and its rating
//    - the season's synopsis and cast
//    - a status menu in the bar: status, rating, share, artwork, remove
//
//  Everything it changes is a field Season and Episode already have.
//

import SwiftUI
import SwiftData

struct PhoneSeasonView: View {
	@Bindable var season: Season

	@Environment(\.modelContext) private var ctx
	@Environment(\.dismiss) private var dismiss
	@AppStorage("autoMarkEpisodesWatched") private var cascadeWatched = true

	@State private var compactBar = false
	@State private var ratingPopup: RatingPopup.Mode?
	@State private var showingArtwork = false
	@State private var confirmingRemove = false
	@State private var theme: UIColor?
	@State private var cast: [CastEntry] = []

	init(season: Season) {
		_season = Bindable(season)
		_theme = State(initialValue: PageTheme.cached(Self.posterURL(of: season)))
	}

	private static func posterURL(of season: Season) -> String {
		season.posterURL.isEmpty ? (season.show?.posterURL ?? "") : season.posterURL
	}

	private var show: Show? { season.show }
	private var pageColor: Color { Color(uiColor: theme ?? PageTheme.fallback) }
	private var pageDeep: Color { Color(uiColor: ArtworkBand.deeper(theme ?? PageTheme.fallback)) }
	private var nextEpisode: Episode? { season.sortedEpisodes.first { $0.status != .watched } }
	private var shownStars: Double? { season.shownStars }

	var body: some View {
		ScrollView {
			TitlePageColumns {
				header
				statusSwitch
				if season.status == .watched || season.rating != nil { verdictCard }
			} rest: {
				episodesSection
				if !season.overview.isEmpty { PageSynopsisCard(text: season.overview) }
				if !cast.isEmpty { PageSection(title: "Cast this season") { PageCastRow(cast: cast) } }
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
				RatingPopup(subject: RatingSubject(season: season), mode: mode, tint: pageColor) {
					withAnimation(Glass.smooth) { ratingPopup = nil }
				}
				.transition(.opacity.combined(with: .scale(scale: 0.96)))
			}
		}
		.titlePage(color: theme, compactBar: compactBar)
		.toolbar {
			ToolbarItem(placement: .principal) {
				if compactBar {
					PageCompactTitle(posterURL: Self.posterURL(of: season), placeholder: "tv",
					                 title: season.displayName,
					                 subtitle: [show?.title ?? "",
					                            ShowFacts.progressLine(watched: season.watchedCount,
					                                                   total: season.episodes.count)]
						.filter { !$0.isEmpty }.joined(separator: " · "))
						.transition(.opacity)
				}
			}
			ToolbarItem(placement: .topBarTrailing) { statusMenu }
		}
		.sheet(isPresented: $showingArtwork) {
			if let tmdbID = show?.tmdbID {
				// A season is drawn from its poster alone.
				ArtworkSheet(source: .season(tvID: tmdbID, season: season.seasonNumber),
				             target: ArtworkTarget(id: season.id,
				                                   current: [.poster: season.posterURL],
				                                   apply: [.poster: { season.posterURL = $0 }]))
			}
		}
		.confirmationDialog("Remove \(season.displayName)?", isPresented: $confirmingRemove,
		                    titleVisibility: .visible) {
			Button("Remove Season", role: .destructive, action: remove)
		} message: {
			Text("Its episodes and their ratings are removed with it.")
		}
		.task(id: Self.posterURL(of: season)) {
			guard let sampled = await PageTheme.load(Self.posterURL(of: season)), !Task.isCancelled,
			      sampled != theme else { return }
			withAnimation(.easeOut(duration: 0.4)) { theme = sampled }
		}
		.task(id: show?.tmdbID) {
			guard let tmdbID = show?.tmdbID else { return }
			cast = Array(await CreditsLoader.seasonCast(tvID: tmdbID, season: season.seasonNumber).prefix(15))
		}
	}

	// MARK: Header

	private var header: some View {
		PagePosterHeader(
			posterURL: Self.posterURL(of: season), placeholder: "tv", title: season.displayName,
			subtitle: show?.title, voteAverage: nil,
			metaParts: [season.airYear.isEmpty ? nil : season.airYear,
			            ShowFacts.episodes(season.episodes.count),
			            season.episodes.isEmpty ? nil : "\(season.watchedCount) watched"].compactMap { $0 })
	}

	// MARK: Status

	private var statusSwitch: some View {
		var options = [
			PageSwitchOption(title: "To watch", selected: season.status == .toWatch, fill: .white) {
				setStatus(.toWatch)
			},
			PageSwitchOption(title: "Watched", systemImage: season.status == .watched ? "checkmark" : nil,
			                 selected: season.status == .watched, fill: PhoneFilmDetailView.teal) {
				markWatched()
			},
		]
		if season.status == .watching {
			options.append(PageSwitchOption(title: nextEpisode.map { "Watching · E\($0.episodeNumber)" } ?? "Watching",
			                                systemImage: "play.fill", selected: true,
			                                fill: PhoneShowDetailView.watchingFill) {})
		}
		return PageSwitch(options: options, selectedText: pageDeep)
			.padding(.top, 2)
	}

	private func setStatus(_ status: WatchStatus) {
		guard season.status != status else { return }
		withAnimation(Glass.smooth) { season.status = status }
	}

	/// Marks it Watched — its episodes too, when the "Mark all episodes
	/// watched" setting is on — and asks how it was. Already Watched, it opens
	/// the rating to change.
	private func markWatched() {
		if season.status == .watched {
			withAnimation(Glass.smooth) { ratingPopup = .edit }
			return
		}
		withAnimation(Glass.smooth) {
			season.status = .watched
			if cascadeWatched {
				for episode in season.episodes { episode.markWatched() }
			}
			ratingPopup = .justMarked
		}
		Haptics.success()
	}

	private var verdictCard: some View {
		HStack(spacing: 8) {
			VerdictChip(rating: season.rating)
			if let stars = shownStars { StarsLabel(value: stars) }
			Spacer(minLength: 4)
			Button(season.rating == nil ? "Rate" : "Edit") {
				withAnimation(Glass.smooth) { ratingPopup = .edit }
			}
			.font(.system(size: 13, weight: .semibold))
			.foregroundStyle(.white)
		}
		.padding(14)
		.liquidCard(cornerRadius: 20)
	}

	// MARK: Episodes

	private var episodesSection: some View {
		PageSection(title: "Episodes") {
			if season.episodes.isEmpty {
				Text("No episodes yet.")
					.font(.system(size: 14, weight: .medium))
					.foregroundStyle(.white.opacity(0.7))
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(14)
					.liquidCard(cornerRadius: 20)
			} else {
				VStack(spacing: 0) {
					ForEach(Array(season.sortedEpisodes.enumerated()), id: \.element.id) { index, episode in
						if index > 0 { PageRowDivider(inset: 112) }
						episodeRow(episode)
					}
				}
				.padding(.vertical, 4)
				.padding(.horizontal, 10)
				.liquidCard(cornerRadius: 20)
			}
		}
	}

	private func episodeRow(_ episode: Episode) -> some View {
		let watched = episode.status == .watched
		return HStack(spacing: 10) {
			NavigationLink { PhoneEpisodeView(episode: episode) } label: {
				HStack(spacing: 10) {
					PosterImage(urlString: episode.stillURL, systemPlaceholder: "film")
						.frame(width: 92, height: 52)
						.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
						.opacity(watched ? 0.6 : 1)
					VStack(alignment: .leading, spacing: 3) {
						Text("E\(episode.episodeNumber) · \(episode.displayTitle)")
							.font(.system(size: 13, weight: .bold))
							.foregroundStyle(.white)
							.lineLimit(2)
						let meta = [FilmFacts.releaseDate(episode.airDate), FilmFacts.runtime(episode.runtimeMinutes)]
							.compactMap { $0 }
						if !meta.isEmpty {
							Text(meta.joined(separator: " · "))
								.font(.system(size: 11, weight: .medium))
								.foregroundStyle(.white.opacity(0.6))
								.lineLimit(1)
						}
					}
					Spacer(minLength: 0)
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)

			VStack(alignment: .trailing, spacing: 6) {
				Button {
					Haptics.selection()
					withAnimation(Glass.smooth) { watched ? episode.mark(.toWatch) : episode.markWatched() }
				} label: {
					Image(systemName: watched ? "checkmark.circle.fill" : "circle")
						.font(.system(size: 22, weight: .semibold))
						.foregroundStyle(watched ? PhoneFilmDetailView.teal : .white.opacity(0.5))
				}
				.buttonStyle(.plain)
				.accessibilityLabel(watched ? "Watched" : "Mark watched")
				Menu {
					Section("Rate this episode") {
						ForEach(EpisodeTier.allCases) { tier in
							Toggle(tier.rawValue, isOn: tierToggle(episode, tier))
						}
					}
				} label: {
					TierChip(tier: episode.episodeTier)
				}
			}
		}
		.padding(.vertical, 8)
	}

	private func tierToggle(_ episode: Episode, _ tier: EpisodeTier) -> Binding<Bool> {
		Binding(get: { episode.episodeTier == tier }, set: { isOn in
			Haptics.selection()
			withAnimation(Glass.smooth) { episode.episodeTier = isOn ? tier : nil }
		})
	}

	// MARK: Menu

	private var statusMenu: some View {
		Menu {
			StatusMenuSection(current: season.status) { status in
				status == .watched ? markWatched() : setStatus(status)
			}
			VerdictMenuSection(item: season)
			Section("Other") {
				shareLink { Label("Share", systemImage: "square.and.arrow.up") }
				Button { showingArtwork = true } label: {
					Label("Artwork", systemImage: "photo.on.rectangle")
				}
				.disabled(show?.tmdbID == nil)
				Button(role: .destructive) { confirmingRemove = true } label: {
					Label("Remove season", systemImage: "trash")
				}
			}
		} label: {
			PageStatusLabel(status: season.status, rating: season.rating)
		}
	}

	/// The season's IMDb episode list when the show has an id there, else its
	/// TMDb page, else its name.
	private func shareLink<Label: View>(@ViewBuilder label: @escaping () -> Label) -> some View {
		TitleShareLink(title: [show?.title ?? "", season.displayName].filter { !$0.isEmpty }.joined(separator: " · "),
		               links: [show?.imdbID.flatMap { IMDb.seasonURL($0, season: season.seasonNumber) },
		                       TitleLinks.tmdbTV(show?.tmdbID, season: season.seasonNumber)],
		               label: label)
	}

	private func remove() {
		ctx.delete(season, afterLeaving: dismiss)
	}
}
