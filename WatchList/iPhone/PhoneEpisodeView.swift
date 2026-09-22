//
//  PhoneEpisodeView.swift
//  WatchList
//
//  The iPhone episode page, in the "Show view" design's language:
//    - the still, where it sits in the show, the title and a meta line
//    - a To watch / Watched switch
//    - your rating: Skip, Watch or Rewatch
//    - synopsis, Everyone on WatchList, details and who's in it
//    - a status menu in the bar: status, rating, share, artwork, remove
//
//  Everything it changes is a field Episode already has. Community ratings
//  aren't built yet and keep a placeholder.
//

import SwiftUI
import SwiftData

struct PhoneEpisodeView: View {
	@Bindable var episode: Episode

	@Environment(\.modelContext) private var ctx
	@Environment(\.dismiss) private var dismiss

	@State private var compactBar = false
	@State private var showingArtwork = false
	@State private var confirmingRemove = false
	@State private var theme: UIColor?
	@State private var credits = TitleCredits()

	init(episode: Episode) {
		_episode = Bindable(episode)
		_theme = State(initialValue: PageTheme.cached(Self.artURL(of: episode)))
	}

	private static func artURL(of episode: Episode) -> String {
		episode.stillURL.isEmpty ? (episode.season?.show?.posterURL ?? "") : episode.stillURL
	}

	private var show: Show? { episode.season?.show }
	private var pageDeep: Color { Color(uiColor: ArtworkBand.deeper(theme ?? PageTheme.fallback)) }
	private var tmdbShowID: Int? { episode.tmdbShowID ?? show?.tmdbID }

	var body: some View {
		ScrollView {
			TitlePageColumns {
				header
				statusSwitch
				ratingSection
			} rest: {
				if !episode.synopsis.isEmpty { PageSynopsisCard(text: episode.synopsis) }
				if let tmdbShowID {
					CommunitySection(title: .episode(tmdbID: tmdbShowID, season: episode.seasonNumber,
					                                episode: episode.episodeNumber),
					                 scale: .tier, yours: episode.episodeTier?.rawValue)
				}
				PageSection(title: "Details") { detailsCard }
				if !credits.people.isEmpty {
					PageSection(title: "In this episode") { PageCastRow(cast: Array(credits.people.prefix(15))) }
				}
			}
		}
		.onScrollGeometryChange(for: Bool.self) { geometry in
			geometry.contentOffset.y + geometry.contentInsets.top > 260
		} action: { _, pastTitle in
			withAnimation(.easeInOut(duration: 0.2)) { compactBar = pastTitle }
		}
		.titlePage(color: theme, compactBar: compactBar)
		.toolbar {
			ToolbarItem(placement: .principal) {
				if compactBar {
					PageCompactTitle(posterURL: show?.posterURL ?? "", placeholder: "tv",
					                 title: episode.displayTitle,
					                 subtitle: [show?.title ?? "", ShowFacts.code(episode)]
						.filter { !$0.isEmpty }.joined(separator: " · "))
						.transition(.opacity)
				}
			}
			ToolbarItem(placement: .topBarTrailing) { statusMenu }
		}
		.sheet(isPresented: $showingArtwork) {
			if let tmdbShowID {
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
			Button("Remove Episode", role: .destructive, action: remove)
		} message: {
			Text("Its rating is removed with it.")
		}
		.task(id: Self.artURL(of: episode)) {
			guard let sampled = await PageTheme.load(Self.artURL(of: episode)), !Task.isCancelled,
			      sampled != theme else { return }
			withAnimation(.easeOut(duration: 0.4)) { theme = sampled }
		}
		.task(id: episode.id) {
			guard let tmdbShowID else { return }
			credits = await CreditsLoader.episodeCredits(tvID: tmdbShowID, season: episode.seasonNumber,
			                                             episode: episode.episodeNumber)
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
					.font(.system(size: 13, weight: .semibold))
					.foregroundStyle(.white.opacity(0.75))
				Text(episode.displayTitle)
					.font(.system(size: 26, weight: .bold))
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
				setStatus(.toWatch)
			},
			PageSwitchOption(title: "Watched", systemImage: episode.status == .watched ? "checkmark" : nil,
			                 selected: episode.status == .watched, fill: PhoneFilmDetailView.teal) {
				setStatus(.watched)
			},
		], selectedText: pageDeep)
		.frame(maxWidth: .infinity)
	}

	private func setStatus(_ status: WatchStatus) {
		guard episode.status != status else { return }
		withAnimation(Glass.smooth) { status == .watched ? episode.markWatched() : episode.mark(status) }
		if status == .watched { Haptics.success() }
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
				if let id = episode.imdbID, let url = IMDb.titleURL(id) {
					Link(destination: url) {
						HStack(spacing: 5) {
							Text("View on IMDb")
							Image(systemName: "arrow.up.right")
						}
						.titlePageCapsule()
					}
				}
				shareLink { Label("Share", systemImage: "square.and.arrow.up").titlePageCapsule() }
			}
			.padding(.top, rows.isEmpty ? 0 : 12)
		}
		.padding(14)
		.liquidCard(cornerRadius: 20)
	}

	// MARK: Menu

	private var statusMenu: some View {
		Menu {
			StatusMenuSection(current: episode.status, choose: setStatus)
			Section("Rate") {
				ForEach(EpisodeTier.allCases) { tier in
					Toggle(tier.rawValue, isOn: Binding(get: { episode.episodeTier == tier }, set: { isOn in
						Haptics.selection()
						withAnimation(Glass.smooth) { episode.episodeTier = isOn ? tier : nil }
					}))
				}
			}
			Section("Other") {
				shareLink { Label("Share", systemImage: "square.and.arrow.up") }
				Button { showingArtwork = true } label: {
					Label("Artwork", systemImage: "photo.on.rectangle")
				}
				.disabled(tmdbShowID == nil)
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

	/// The episode on IMDb, else its TMDb page, else its name.
	private func shareLink<Label: View>(@ViewBuilder label: @escaping () -> Label) -> some View {
		TitleShareLink(title: [show?.title ?? "", "\(ShowFacts.code(episode)) · \(episode.displayTitle)"]
		               	.filter { !$0.isEmpty }.joined(separator: " · "),
		               links: [episode.imdbID.flatMap(IMDb.titleURL),
		                       TitleLinks.tmdbTV(tmdbShowID, season: episode.seasonNumber, episode: episode.episodeNumber)],
		               label: label)
	}

	private func remove() {
		ctx.delete(episode, afterLeaving: dismiss)
	}
}
