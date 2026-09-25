//
//  PhoneEpisodeView.swift
//  WatchList
//
//  The iPhone episode page, in the "Show view" design's language:
//    - the still, where it sits in the show, the title and a meta line
//    - a To watch / Watched switch
//    - Play, when the episode is on your Jellyfin server or in its show's
//      linked put.io folder (PlayButton)
//    - your rating: Skip, Watch or Rewatch
//    - synopsis, Everyone on WatchList, details — ending in Open in… (IMDb,
//      TMDb, Trakt) and Share — and who's in it
//    - a status menu in the bar: status, rating, share, artwork, remove
//    - on an iPad, the show page's layout (PadTitlePage): the still behind the
//      show's poster, and who's in it beside Details
//    - a swipe sideways for the next or previous episode, running on across
//      the show's seasons (a special's, among the specials), each page on its
//      own colour
//
//  Everything it changes is a field Episode already has.
//

import SwiftUI
import SwiftData

/// The episode opened, with the show's others a swipe either side of it
/// (ShowFacts.swipeRun). The bar — the title once the page scrolls, and the
/// status menu — is for the page in view.
struct PhoneEpisodeView: View {
	/// The episodes a swipe goes through, in order.
	private let run: [Episode]

	@Environment(\.modelContext) private var ctx
	@Environment(\.dismiss) private var dismiss

	/// The page in view.
	@State private var currentID: UUID?
	/// Each page's colour, once it's in, for the bar to take.
	@State private var themes: [UUID: UIColor] = [:]
	/// The pages scrolled up past their title, for the bar to turn solid on.
	@State private var pastTitle: Set<UUID> = []
	@State private var showingArtwork = false
	@State private var confirmingRemove = false

	init(episode: Episode) {
		run = ShowFacts.swipeRun(around: episode)
		_currentID = State(initialValue: episode.id)
	}

	var body: some View {
		let episode = run.first { $0.id == currentID } ?? run[0]
		let show = episode.season?.show
		ScrollView(.horizontal) {
			LazyHStack(spacing: 0) {
				ForEach(run) { each in
					EpisodePage(episode: each) { themes[each.id] = $0 } onPastTitle: { past in
						withAnimation(.easeInOut(duration: 0.2)) {
							if past { pastTitle.insert(each.id) } else { pastTitle.remove(each.id) }
						}
					}
					.containerRelativeFrame(.horizontal)
				}
			}
			.scrollTargetLayout()
		}
		.scrollTargetBehavior(.paging)
		.scrollPosition(id: $currentID)
		.scrollIndicators(.hidden)
		// One episode has nowhere to go, so it doesn't give sideways at all.
		.scrollBounceBehavior(.basedOnSize, axes: .horizontal)
		.titlePage(color: themes[episode.id] ?? PageTheme.cached(EpisodePage.artURL(of: episode)),
		           compactBar: pastTitle.contains(episode.id))
		.toolbar {
			ToolbarItem(placement: .principal) {
				if pastTitle.contains(episode.id) {
					PageCompactTitle(posterURL: show?.posterURL ?? "", placeholder: "tv",
					                 title: episode.displayTitle,
					                 subtitle: [show?.title ?? "", ShowFacts.code(episode)]
						.filter { !$0.isEmpty }.joined(separator: " · "))
						.transition(.opacity)
				}
			}
			ToolbarItem(placement: .topBarTrailing) { statusMenu(episode) }
		}
		.sheet(isPresented: $showingArtwork) {
			if let tmdbShowID = episode.showTMDbID {
				// An episode is drawn from its still, which is landscape.
				ArtworkSheet(source: .episode(tvID: tmdbShowID, season: episode.seasonNumber,
				                              episode: episode.episodeNumber),
				             target: ArtworkTarget(id: episode.id,
				                                   current: [.landscape: episode.stillURL],
				                                   apply: [.landscape: { episode.stillURL = $0 }]))
			}
		}
		.confirmationDialog("Remove \u{201C}\(episode.displayTitle)\u{201D}?", isPresented: $confirmingRemove,
		                    titleVisibility: .visible) {
			Button("Remove Episode", role: .destructive) { ctx.delete(episode, afterLeaving: dismiss) }
		} message: {
			Text("Its rating is removed with it.")
		}
	}

	// MARK: Menu

	private func statusMenu(_ episode: Episode) -> some View {
		Menu {
			StatusMenuSection(current: episode.status, choose: episode.setStatus)
			Section("Rate") {
				ForEach(EpisodeTier.allCases) { tier in
					Toggle(tier.rawValue, isOn: Binding(get: { episode.episodeTier == tier }, set: { isOn in
						Haptics.selection()
						withAnimation(Glass.smooth) { episode.episodeTier = isOn ? tier : nil }
					}))
				}
			}
			Section("Other") {
				EpisodeShareLink(episode: episode) { Label("Share", systemImage: "square.and.arrow.up") }
				Button { showingArtwork = true } label: {
					Label("Artwork", systemImage: "photo.on.rectangle")
				}
				.disabled(episode.showTMDbID == nil)
				Button(role: .destructive) { confirmingRemove = true } label: {
					Label("Remove episode", systemImage: "trash")
				}
			}
		} label: {
			HStack(spacing: 6) {
				if let tier = episode.episodeTier {
					Image(systemName: tier.systemImage)
						.font(.system(size: 11, weight: .bold))
						.foregroundStyle(Glass.tint(tier))
					Text(tier.rawValue)
				} else {
					Image(systemName: episode.status.systemImage)
						.font(.system(size: 12, weight: .semibold))
					Text(episode.status.rawValue)
				}
				Image(systemName: "chevron.down")
					.font(.system(size: 11, weight: .bold))
			}
			.font(.system(size: 14, weight: .semibold))
			.foregroundStyle(.white)
		}
	}
}

// MARK: - Page

/// One episode's page, on its own colour and scrolling on its own.
private struct EpisodePage: View {
	@Bindable var episode: Episode
	/// Receives the page's colour once its artwork is in.
	let onTheme: (UIColor) -> Void
	/// Whether the page has scrolled up past its title.
	let onPastTitle: (Bool) -> Void

	@State private var theme: UIColor?
	@State private var credits = TitleCredits()
	@Environment(\.horizontalSizeClass) private var sizeClass

	init(episode: Episode, onTheme: @escaping (UIColor) -> Void, onPastTitle: @escaping (Bool) -> Void) {
		_episode = Bindable(episode)
		self.onTheme = onTheme
		self.onPastTitle = onPastTitle
		_theme = State(initialValue: PageTheme.cached(Self.artURL(of: episode)))
	}

	static func artURL(of episode: Episode) -> String {
		episode.stillURL.isEmpty ? (episode.season?.show?.posterURL ?? "") : episode.stillURL
	}

	private var show: Show? { episode.season?.show }
	private var pageDeep: Color { Color(uiColor: ArtworkBand.deeper(theme ?? PageTheme.fallback)) }

	var body: some View {
		let pad = PadTitleLayout.applies(sizeClass)
		ScrollView {
			if pad {
				padPage
			} else {
				TitlePageColumns {
					header
					statusSwitch
						.frame(maxWidth: .infinity)
					playButton
					ratingSection
				} rest: {
					if !episode.synopsis.isEmpty { PageSynopsisCard(text: episode.synopsis) }
					community
					PageSection(title: "Details") { detailsCard }
					castSection
				}
			}
		}
		.onScrollGeometryChange(for: Bool.self) { geometry in
			geometry.contentOffset.y + geometry.contentInsets.top > (pad ? PadTitleLayout.compactBarOffset : 260)
		} action: { _, pastTitle in
			onPastTitle(pastTitle)
		}
		.background(PageTheme.backdrop(theme).ignoresSafeArea())
		.task(id: Self.artURL(of: episode)) {
			guard let sampled = await PageTheme.load(Self.artURL(of: episode)), !Task.isCancelled else { return }
			onTheme(sampled)
			guard sampled != theme else { return }
			withAnimation(.easeOut(duration: 0.4)) { theme = sampled }
		}
		.task(id: episode.id) {
			guard let tmdbShowID = episode.showTMDbID else { return }
			credits = await CreditsLoader.episodeCredits(tvID: tmdbShowID, season: episode.seasonNumber,
			                                             episode: episode.episodeNumber)
		}
	}

	// MARK: iPad

	/// The iPad's page (PadTitlePage): the episode's still behind the show's
	/// poster; your rating first, with Everyone on WatchList once it's watched;
	/// who's in it beside Details.
	private var padPage: some View {
		let average = episode.specs?.voteAverage ?? 0
		return VStack(spacing: 0) {
			PadTitleHero(backdropURL: episode.stillURL.isEmpty ? (show?.backdropURL ?? "") : episode.stillURL,
			             posterURL: episode.season?.posterURL.isEmpty == false ? episode.season!.posterURL
			                                                                  : (show?.posterURL ?? ""),
			             placeholder: "tv",
			             kindLine: PadTitleLayout.kindLine([show?.title, HomeFeed.episodeLine(episode),
			                                                FilmFacts.runtime(episode.runtimeMinutes)]),
			             title: episode.displayTitle, voteAverage: average,
			             votes: average > 0 ? FilmFacts.count(episode.specs?.voteCount) : nil,
			             synopsis: episode.synopsis) {
				VStack(spacing: 10) {
					statusSwitch
					playButton
				}
			}
			PadTitleBody {
				ratingSection
				if episode.status == .watched { community }
			} main: {
				castSection
			} side: {
				PageSection(title: "Details") { detailsCard }
			} rest: {
				if episode.status != .watched { community }
			}
		}
	}

	@ViewBuilder private var community: some View {
		if let tmdbShowID = episode.showTMDbID {
			CommunitySection(title: .episode(tmdbID: tmdbShowID, season: episode.seasonNumber,
			                                episode: episode.episodeNumber),
			                 scale: .tier, yours: episode.episodeTier?.rawValue)
		}
	}

	@ViewBuilder private var castSection: some View {
		if !credits.people.isEmpty {
			PageSection(title: "In this episode") { PageCastRow(cast: Array(credits.people.prefix(15))) }
		}
	}

	// MARK: Header

	private var header: some View {
		VStack(alignment: .leading, spacing: 12) {
			PosterImage(urlString: episode.stillURL.isEmpty ? (show?.backdropURL ?? "") : episode.stillURL,
			            systemPlaceholder: "film")
				.aspectRatio(16 / 9, contentMode: .fit)
				.frame(maxWidth: .infinity)
				.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
				.shadow(color: .black.opacity(0.4), radius: 20, y: 10)
				.padding(.top, 6)
				.accessibilityHidden(true)
			VStack(alignment: .leading, spacing: 4) {
				Text([show?.title ?? "", HomeFeed.episodeLine(episode)].filter { !$0.isEmpty }.joined(separator: " · "))
					.font(.system(size: sizeClass == .regular ? 15 : 13, weight: .semibold))
					.foregroundStyle(.white.opacity(0.75))
				Text(episode.displayTitle)
					.font(.system(size: sizeClass == .regular ? 34 : 26, weight: .bold))
					.foregroundStyle(.white)
					.fixedSize(horizontal: false, vertical: true)
					.accessibilityAddTraits(.isHeader)
				let average = episode.specs?.voteAverage ?? 0
				PageMetaLine(voteAverage: average,
				             parts: [average > 0 ? FilmFacts.count(episode.specs?.voteCount) : nil,
				                     FilmFacts.releaseDate(episode.airDate),
				                     FilmFacts.runtime(episode.runtimeMinutes)].compactMap { $0 })
					.frame(maxWidth: .infinity, alignment: .leading)
			}
		}
	}

	// MARK: Status and rating

	private var statusSwitch: some View {
		PageSwitch(options: [
			PageSwitchOption(title: "To watch", selected: episode.status == .toWatch, fill: .white) {
				episode.setStatus(.toWatch)
			},
			PageSwitchOption(title: "Watched", systemImage: episode.status == .watched ? "checkmark" : nil,
			                 selected: episode.status == .watched, fill: PhoneFilmDetailView.teal) {
				episode.setStatus(.watched)
			},
		], selectedText: pageDeep)
	}

	/// Play from your Jellyfin server, when it has the episode; watching it
	/// through marks it Watched, starting its season and show.
	private var playButton: some View {
		PagePlayButton(title: .episode(showID: show?.id, showTMDbID: episode.showTMDbID, showIMDbID: show?.imdbID,
		                               season: episode.seasonNumber, episode: episode.episodeNumber),
		               name: episode.displayTitle,
		               subtitle: [show?.title ?? "", ShowFacts.code(episode)].filter { !$0.isEmpty }
		               	.joined(separator: " · ")) {
			episode.setStatus(.watched)
		}
	}

	/// The three episode ratings; tapping the chosen one again clears it.
	/// Rating an episode marks it Watched, as Home's sheet does.
	private var ratingSection: some View {
		PageSection(title: "Your rating") {
			HStack(spacing: 10) {
				ForEach(EpisodeTier.allCases) { tier in
					let current = episode.episodeTier == tier
					let tint = Glass.tint(tier)
					let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
					Button {
						Haptics.selection()
						withAnimation(Glass.smooth) {
							episode.episodeTier = current ? nil : tier
							if !current { episode.markWatched() }
						}
					} label: {
						VStack(spacing: 5) {
							Image(systemName: tier.systemImage)
								.font(.system(size: 18, weight: .semibold))
							Text(tier.rawValue)
								.font(.system(size: 14, weight: .semibold))
						}
						.foregroundStyle(current ? .white : tint)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 11)
						.background(shape.fill(tint.opacity(current ? 0.55 : 0.16)))
						.overlay(shape.strokeBorder(.white.opacity(current ? 0.6 : 0.08), lineWidth: current ? 1.5 : 1))
					}
					.buttonStyle(.pressable)
					.accessibilityLabel(tier.rawValue)
					.accessibilityAddTraits(current ? .isSelected : [])
				}
			}
		}
	}

	// MARK: Details

	private var detailsCard: some View {
		VStack(spacing: 0) {
			let rows: [(String, String, String)] = [
				("Aired", "calendar", FilmFacts.releaseDate(episode.airDate) ?? ""),
				("Runtime", "clock", FilmFacts.runtime(episode.runtimeMinutes) ?? ""),
				("Directed by", "megaphone", credits.directedBy),
				("Written by", "pencil", credits.writtenBy),
			].filter { !$0.2.isEmpty }
			ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
				if index > 0 { PageRowDivider() }
				PageDetailRow(row.0, icon: row.1, text: row.2)
			}
			HStack(spacing: 10) {
				let openIn = OpenInMenu(sites: TitleSites.episode(imdbID: episode.imdbID, showTMDbID: episode.showTMDbID,
				                                                  showIMDbID: episode.season?.show?.imdbID,
				                                                  season: episode.seasonNumber,
				                                                  episode: episode.episodeNumber)) {
					OpenInLabel()
				}
				if openIn.hasLinks { openIn }
				EpisodeShareLink(episode: episode) {
					Label("Share", systemImage: "square.and.arrow.up").titlePageCapsule()
				}
			}
			.padding(.top, rows.isEmpty ? 0 : 12)
		}
		.padding(14)
		.liquidCard(cornerRadius: 20)
	}
}

// MARK: - Shared

private extension Episode {
	/// The show's TMDb id, which its community ratings, cast and artwork need.
	var showTMDbID: Int? { tmdbShowID ?? season?.show?.tmdbID }

	/// From the page's switch or the bar's menu. Watched starts its season and
	/// show too.
	func setStatus(_ status: WatchStatus) {
		guard self.status != status else { return }
		withAnimation(Glass.smooth) { status == .watched ? markWatched() : mark(status) }
		if status == .watched { Haptics.success() }
	}
}

/// Shares the episode on IMDb, else its TMDb page, else its name.
private struct EpisodeShareLink<Label: View>: View {
	let episode: Episode
	@ViewBuilder let label: () -> Label

	var body: some View {
		TitleShareLink(title: [episode.season?.show?.title ?? "",
		                       "\(ShowFacts.code(episode)) · \(episode.displayTitle)"]
		               	.filter { !$0.isEmpty }.joined(separator: " · "),
		               links: [episode.imdbID.flatMap(IMDb.titleURL),
		                       TitleLinks.tmdbTV(episode.showTMDbID, season: episode.seasonNumber,
		                                         episode: episode.episodeNumber)],
		               label: label)
	}
}
