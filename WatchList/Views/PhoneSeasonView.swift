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
import WatchListCore
import WatchListLibrary

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
				if season.watchedCount > 0 { watchedDateButton }
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
		.sheet(item: $ratingPopup) { mode in
			RatingPopup(subject: RatingSubject(season: season), mode: mode, tint: pageColor) { ratingPopup = nil }
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
			season.markWatched()
			if cascadeWatched {
				for episode in season.episodes { episode.markWatched() }
			}
			ratingPopup = .justMarked
		}
		Haptics.success()
	}

	/// When the season's episodes were watched — the latest of them — and a
	/// menu that moves every watched episode to one day, for a season binged
	/// before it was marked.
	private var watchedDateButton: some View {
		let watched = season.episodes.filter { $0.status == .watched }
		return WatchedDateButton(date: watched.compactMap(\.watchedAt).max(),
		                         prompt: "Set for \(ShowFacts.episodes(watched.count)) watched") { date in
			for episode in watched { episode.setWatchedDate(date) }
		}
	}

	private var verdictCard: some View {
		HStack(spacing: 8) {
			VerdictChip(rating: season.rating)
			if let stars = shownStars { StarsLabel(value: stars) }
			Spacer(minLength: 4)
			Button(season.rating == nil ? "Rate" : "Edit") {
				withAnimation(Glass.smooth) { ratingPopup = .edit }
			}
			.font(.system(.footnote, weight: .semibold))
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
					.font(.system(.subheadline, weight: .medium))
					.foregroundStyle(.white.opacity(0.7))
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(14)
					.liquidCard(cornerRadius: 20)
			} else {
				VStack(spacing: 0) {
					ForEach(Array(season.sortedEpisodes.enumerated()), id: \.element.id) { index, episode in
						if index > 0 { PageRowDivider(inset: 106) }
						episodeRow(episode)
							.contextMenu {
								EpisodeWatchedMenuItems(episode: episode)
								Section("Rate") {
									ForEach(EpisodeTier.allCases) { tier in
										Toggle(tier.rawValue, isOn: tierToggle(episode, tier))
									}
								}
							}
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
			// The still, with the number in a disc of its rating's colour on its
			// corner (design B); the disc, tapped, rates.
			EpisodeStillLead(episode: episode) { tier in
				withAnimation(Glass.smooth) { episode.episodeTier = tier }
			}
			NavigationLink { PhoneEpisodeView(episode: episode) } label: {
				HStack(spacing: 10) {
					VStack(alignment: .leading, spacing: 3) {
						Text(episode.displayTitle)
							.font(.system(.subheadline, weight: .bold))
							.foregroundStyle(.white.opacity(watched ? 0.75 : 1))
							.lineLimit(2)
						let meta = [FilmFacts.releaseDate(episode.airDate), FilmFacts.runtime(episode.runtimeMinutes)]
							.compactMap { $0 }
						HStack(spacing: 0) {
							if let tier = episode.episodeTier {
								Text(tier.rawValue).foregroundStyle(Glass.tint(tier))
								if !meta.isEmpty { Text(" · ") }
							}
							Text(meta.joined(separator: " · "))
						}
						.font(.system(.caption2, weight: .medium))
						.foregroundStyle(.white.opacity(0.6))
						.lineLimit(1)
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
						.font(.system(.title2, weight: .semibold))
						.foregroundStyle(watched ? PhoneFilmDetailView.teal : .white.opacity(0.5))
				}
				.buttonStyle(.plain)
				.accessibilityLabel(watched ? "Watched" : "Mark watched")
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

/// An episode's number in a disc of its rating's colour — dashed while it has
/// none — after design B of the alternatives.
struct EpisodeNumberDisc: View {
	let number: Int
	let tier: EpisodeTier?
	var size: CGFloat = 34
	/// On a still the unrated disc needs a dark fill to read.
	var onArt = false

	var body: some View {
		Text("\(number)")
			.font(.system(size: size * 0.44, weight: .bold, design: .rounded))
			.foregroundStyle(tier == nil ? .white : Glass.onTint)
			.frame(width: size, height: size)
			.background {
				if let tier {
					Circle().fill(Glass.tint(tier))
				} else {
					Circle().fill(onArt ? .black.opacity(0.6) : .white.opacity(0.08))
					Circle().strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
				}
			}
	}
}

/// An episode row's lead: its still, which opens the episode, with its number
/// disc on the corner, which rates it.
struct EpisodeStillLead: View {
	let episode: Episode
	let rate: (EpisodeTier?) -> Void

	var body: some View {
		let watched = episode.status == .watched
		ZStack(alignment: .bottomLeading) {
			NavigationLink { PhoneEpisodeView(episode: episode) } label: {
				PosterImage(urlString: episode.stillURL, systemPlaceholder: "film")
					.frame(width: 96, height: 54)
					.clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
					.opacity(watched ? 0.6 : 1)
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Open \(episode.displayTitle)")
			Menu {
				Section("Rate this episode") {
					ForEach(EpisodeTier.allCases) { tier in
						Toggle(tier.rawValue, isOn: Binding(get: { episode.episodeTier == tier }, set: { isOn in
							Haptics.selection()
							rate(isOn ? tier : nil)
						}))
					}
				}
			} label: {
				EpisodeNumberDisc(number: episode.episodeNumber, tier: episode.episodeTier, size: 26, onArt: true)
					.padding(4)
			}
			.accessibilityLabel("Episode \(episode.episodeNumber), \(episode.episodeTier?.rawValue ?? "not rated"). Rate it")
		}
	}
}
