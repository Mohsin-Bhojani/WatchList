//
//  PhoneFilmDetailView.swift
//  WatchList
//
//  The film page, after the "Film view" design, built from TitlePageKit:
//    - the poster, title and a meta line: TMDb stars and votes, year, runtime
//    - a To watch / Watched switch; marking Watched asks how it was
//    - Play, when the film is on your Jellyfin server (PlayButton)
//    - once watched, your rating: verdict, stars, date and private note
//    - trailer, synopsis, Everyone on WatchList, Details — ending in Open in…
//      (IMDb, TMDb, Letterboxd and more; TitleSites) and Share — and Cast
//    - a status menu in the bar: status, rating, share, artwork, collections,
//      refresh, remove
//    - a compact bar with the poster and title once the title scrolls away
//  A rating is a verdict, half-star stars or both, each setting the other
//  (StarRating). Refresh metadata takes TMDb's latest (FilmRefresh); Share
//  with friends sends it as a WatchList link (FriendShare).
//
//  The page takes its colour from the film's own poster (PageTheme), so no two
//  films look the same.
//

import SwiftUI
import SwiftData

struct PhoneFilmDetailView: View {
	@Bindable var film: Film

	@Environment(\.modelContext) private var ctx
	@Environment(\.dismiss) private var dismiss
	@Environment(\.horizontalSizeClass) private var sizeClass
	@Query(sort: \TitleCollection.created) private var collections: [TitleCollection]

	@State private var compactBar = false
	@State private var ratingPopup: RatingPopup.Mode?
	@State private var showingArtwork = false
	@State private var confirmingRemove = false
	@State private var namingCollection = false
	@State private var cast: [CastEntry] = []
	@State private var theme: UIColor?
	@State private var refreshing = false
	@State private var refreshNote: String?

	/// The design's teal, for Watched and Save rating.
	static let teal = Color(.pageWatched)

	init(film: Film) {
		_film = Bindable(film)
		_theme = State(initialValue: PageTheme.cached(Self.artURL(of: film)))
	}

	/// The poster, or the backdrop when there's no poster.
	private static func artURL(of film: Film) -> String {
		film.posterURL.isEmpty ? film.backdropURL : film.posterURL
	}

	private var pageColor: Color { Color(uiColor: theme ?? PageTheme.fallback) }
	private var pageDeep: Color { Color(uiColor: ArtworkBand.deeper(theme ?? PageTheme.fallback)) }
	private var shownStars: Double? { film.shownStars }

	var body: some View {
		let pad = PadTitleLayout.applies(sizeClass)
		ScrollView {
			if pad {
				padPage
			} else {
				TitlePageColumns {
					header
					statusSwitch
					playButton
					if film.status == .watched { verdictCard }
				} rest: {
					PageTrailerCard(source: film.tmdbID.map { .movie(movieID: $0) }, backdropURL: film.backdropURL)
					if !film.synopsis.isEmpty { PageSynopsisCard(text: film.synopsis) }
					community
					PageSection(title: "Details") { detailsCard }
					if !cast.isEmpty { PageSection(title: "Cast") { PageCastRow(cast: cast) } }
				}
			}
		}
		// The bar turns solid, with the poster and title, once the title is gone.
		.onScrollGeometryChange(for: Bool.self) { geometry in
			geometry.contentOffset.y + geometry.contentInsets.top > (pad ? PadTitleLayout.compactBarOffset : 290)
		} action: { _, pastTitle in
			withAnimation(.easeInOut(duration: 0.2)) { compactBar = pastTitle }
		}
		.blur(radius: ratingPopup == nil ? 0 : 10)
		.overlay {
			if let mode = ratingPopup {
				RatingPopup(film: film, mode: mode, tint: pageColor) {
					withAnimation(Glass.smooth) { ratingPopup = nil }
				}
				.transition(.opacity.combined(with: .scale(scale: 0.96)))
			}
		}
		.titlePage(color: theme, compactBar: compactBar)
		.toolbar {
			ToolbarItem(placement: .principal) {
				if compactBar {
					PageCompactTitle(posterURL: film.posterURL, placeholder: "film", title: film.title,
					                 subtitle: [film.year, FilmFacts.runtime(film.specs?.runtimeMinutes) ?? ""]
						.filter { !$0.isEmpty }.joined(separator: " · "))
						.transition(.opacity)
				}
			}
			ToolbarItem(placement: .topBarTrailing) { statusMenu }
		}
		.sheet(isPresented: $showingArtwork) {
			if let tmdbID = film.tmdbID {
				ArtworkSheet(source: .movie(movieID: tmdbID),
				             target: ArtworkTarget(id: film.id,
				                                   current: [.poster: film.posterURL, .landscape: film.backdropURL],
				                                   apply: [.poster: { film.posterURL = $0 },
				                                           .landscape: { film.backdropURL = $0 }]))
			}
		}
		.newCollectionAlert(isPresented: $namingCollection, adding: film.id)
		.alert("Refresh metadata", isPresented: Binding(get: { refreshNote != nil },
		                                                 set: { if !$0 { refreshNote = nil } })) {
			Button("OK", role: .cancel) {}
		} message: {
			Text(refreshNote ?? "")
		}
		.confirmationDialog("Remove \u{201C}\(film.title)\u{201D}?", isPresented: $confirmingRemove,
		                    titleVisibility: .visible) {
			Button("Remove from Library", role: .destructive) {
				ctx.delete(film, afterLeaving: dismiss)
			}
		} message: {
			Text("Its rating and note are removed with it.")
		}
		.task(id: film.tmdbID) { await loadCast() }
		.task(id: Self.artURL(of: film)) {
			guard let sampled = await PageTheme.load(Self.artURL(of: film)), !Task.isCancelled,
			      sampled != theme else { return }
			withAnimation(.easeOut(duration: 0.4)) { theme = sampled }
		}
	}

	// MARK: iPad

	/// The iPad's page (PadTitlePage): once watched, your verdict and
	/// Everyone on WatchList come first; before then, Everyone on WatchList
	/// waits at the end.
	private var padPage: some View {
		let average = film.specs?.voteAverage ?? 0
		return VStack(spacing: 0) {
			PadTitleHero(backdropURL: film.backdropURL, posterURL: film.posterURL, placeholder: "film",
			             kindLine: PadTitleLayout.kindLine(["Film", film.year,
			                                                FilmFacts.runtime(film.specs?.runtimeMinutes)]),
			             title: film.title, voteAverage: average,
			             votes: average > 0 ? FilmFacts.count(film.specs?.voteCount) : nil,
			             synopsis: film.synopsis) {
				VStack(spacing: 10) {
					statusSwitch
					playButton
				}
			}
			PadTitleBody {
				if film.status == .watched {
					PageSection(title: "Your verdict") { verdictCard }
					community
				}
			} main: {
				PageTrailerCard(source: film.tmdbID.map { .movie(movieID: $0) }, backdropURL: film.backdropURL,
				                title: "Trailer")
			} side: {
				PageSection(title: "Details") { detailsCard }
			} rest: {
				if !cast.isEmpty { PageSection(title: "Cast") { PageCastRow(cast: cast) } }
				if film.status != .watched { community }
			}
		}
	}

	private var verdictCard: some View {
		PageVerdictCard(rating: film.rating, stars: shownStars,
		                dateLine: film.watchedAt.map { "Watched \(FilmFacts.shortDate($0))" },
		                note: film.notes, share: SharedTitle(film: film)) {
			withAnimation(Glass.smooth) { ratingPopup = .edit }
		}
	}

	@ViewBuilder private var community: some View {
		if let tmdbID = film.tmdbID {
			CommunitySection(title: .film(tmdbID: tmdbID), scale: .verdict, yours: film.rating?.rawValue)
		}
	}

	// MARK: Header and status

	/// TMDb's stars and votes, then year and runtime. The design's community
	/// verdict ("62% Go for it") isn't built, so it's left out of the meta line;
	/// Everyone on WatchList carries the placeholder.
	private var header: some View {
		let average = film.specs?.voteAverage ?? 0
		return PagePosterHeader(
			posterURL: film.posterURL, placeholder: "film", title: film.title, voteAverage: average,
			metaParts: [average > 0 ? FilmFacts.count(film.specs?.voteCount) : nil,
			            film.year.isEmpty ? nil : film.year,
			            FilmFacts.runtime(film.specs?.runtimeMinutes)].compactMap { $0 })
	}

	/// The design's switch has two sides; a film left on Watching lights neither.
	private var statusSwitch: some View {
		PageSwitch(options: [
			PageSwitchOption(title: "To watch", selected: film.status == .toWatch, fill: .white) {
				setStatus(.toWatch)
			},
			PageSwitchOption(title: "Watched", systemImage: film.status == .watched ? "checkmark" : nil,
			                 selected: film.status == .watched, fill: Self.teal) {
				markWatched()
			},
		], selectedText: pageDeep)
		.padding(.top, 2)
	}

	/// Play from your Jellyfin server, when it has the film; watching it
	/// through marks it Watched and asks how it was.
	private var playButton: some View {
		PagePlayButton(title: .film(tmdbID: film.tmdbID, imdbID: film.imdbID), name: film.title,
		               subtitle: film.year.isEmpty ? nil : film.year) {
			if film.status != .watched { markWatched() }
		}
	}

	private func setStatus(_ status: WatchStatus) {
		guard film.status != status else { return }
		withAnimation(Glass.smooth) { film.mark(status) }
	}

	/// Marks it Watched and asks how it was. Already Watched, it opens the
	/// rating to change.
	private func markWatched() {
		if film.status == .watched {
			withAnimation(Glass.smooth) { ratingPopup = .edit }
			return
		}
		withAnimation(Glass.smooth) {
			film.mark(.watched)
			ratingPopup = .justMarked
		}
		Haptics.success()
	}

	// MARK: Details

	private var detailsCard: some View {
		VStack(spacing: 0) {
			if !film.genre.isEmpty {
				PageDetailRow("Genre", icon: "theatermasks", text: FilmFacts.genres(film.genre))
				PageRowDivider()
			}
			if let runtime = FilmFacts.runtime(film.specs?.runtimeMinutes) {
				PageDetailRow("Runtime", icon: "clock", text: runtime)
				PageRowDivider()
			}
			if let released = FilmFacts.releaseDate(film.specs?.releaseDate) {
				PageDetailRow("Release date", icon: "calendar", text: released)
				PageRowDivider()
			}
			if let tmdbID = film.tmdbID {
				PageDetailRow(label: "Where to watch", icon: "tv") {
					WhereToWatchList(source: .movie(movieID: tmdbID), title: film.title)
				}
				PageRowDivider()
			}
			PageDetailRow("Your rating", icon: "star", text: yourRatingSummary)
			PageRowDivider()
			PageDetailRow("Collections", icon: "rectangle.stack", text: collectionNames)

			HStack(spacing: 10) {
				let openIn = OpenInMenu(sites: TitleSites.film(imdbID: film.imdbID, tmdbID: film.tmdbID, title: film.title)) {
					OpenInLabel()
				}
				if openIn.hasLinks { openIn }
				shareLink { Label("Share", systemImage: "square.and.arrow.up").titlePageCapsule() }
			}
			.padding(.top, 12)
		}
		.padding(14)
		.liquidCard(cornerRadius: 20)
	}

	/// Your collections this film is in, or "None yet".
	private var collectionNames: String {
		let names = collections.filter { $0.contains(film.id) }.map(\.name)
		return names.isEmpty ? "None yet" : names.joined(separator: ", ")
	}

	private var yourRatingSummary: String {
		guard let rating = film.rating else { return "Not rated yet" }
		var parts = [rating.rawValue]
		if let stars = shownStars {
			parts.append("\(StarRating.label(stars)) \(stars == 1 ? "star" : "stars")")
		}
		if let date = film.watchedAt { parts.append(FilmFacts.shortDate(date)) }
		return parts.joined(separator: " · ")
	}

	private func loadCast() async {
		guard let tmdbID = film.tmdbID else { return }
		cast = Array(await CreditsLoader.movieCast(movieID: tmdbID).people.prefix(15))
	}

	// MARK: Refresh

	private func refresh() async {
		refreshing = true
		let outcome = await FilmRefresh.refresh(film)
		refreshing = false
		refreshNote = outcome.message
		if case .updated = outcome { Haptics.success() }
	}

	// MARK: Menu

	/// The design's status menu.
	private var statusMenu: some View {
		Menu {
			StatusMenuSection(current: film.status, statuses: [.toWatch, .watched]) { status in
				status == .watched ? markWatched() : setStatus(status)
			}
			VerdictMenuSection(item: film)
			Section("Other") {
				shareLink { Label("Share", systemImage: "square.and.arrow.up") }
				Button { showingArtwork = true } label: {
					Label("Artwork", systemImage: "photo.on.rectangle")
				}
				.disabled(film.tmdbID == nil)
				AddToCollectionMenu(titleID: film.id) { namingCollection = true }
				Button { Task { await refresh() } } label: {
					Label(refreshing ? "Refreshing…" : "Refresh metadata", systemImage: "arrow.clockwise")
				}
				.disabled(film.tmdbID == nil || refreshing)
				Button(role: .destructive) { confirmingRemove = true } label: {
					Label("Remove from library", systemImage: "trash")
				}
			}
		} label: {
			PageStatusLabel(status: film.status, rating: film.rating)
		}
	}

	/// IMDb's page when there is one, else TMDb's, else just the title.
	private func shareLink<Label: View>(@ViewBuilder label: @escaping () -> Label) -> some View {
		TitleShareLink(title: film.title,
		               links: [film.imdbID.flatMap(IMDb.titleURL), TitleLinks.tmdbMovie(film.tmdbID)],
		               label: label)
	}
}
