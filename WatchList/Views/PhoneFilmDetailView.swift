//
//  PhoneFilmDetailView.swift
//  WatchList
//
//  The film page, after the "Film view" design, built from TitlePageKit:
//    - the poster, title and a meta line: TMDb stars and votes, year, runtime
//    - a To watch / Watched switch; marking Watched asks how it was
//    - once watched, your rating: verdict, stars, date and private note
//    - trailer, synopsis, Everyone on WatchList, Details and Cast
//    - a status menu in the bar: status, rating, share, artwork, collections,
//      remove
//    - a compact bar with the poster and title once the title scrolls away
//  A rating is a verdict, half-star stars or both, each setting the other
//  (StarRating). Community ratings, the trailer, where to watch, sharing with
//  friends and refreshing metadata aren't built yet; each keeps its place with
//  a placeholder.
//
//  The page takes its colour from the film's own poster (PageTheme), so no two
//  films look the same.
//

import SwiftUI
import SwiftData
import WatchListCore
import WatchListLibrary

struct PhoneFilmDetailView: View {
	@Bindable var film: Film
	/// False when opened from its own series' page, which needs no link back.
	private let showsSeriesLink: Bool

	@Environment(\.modelContext) private var ctx
	@Environment(\.dismiss) private var dismiss
	@Query(sort: \TitleCollection.created) private var collections: [TitleCollection]

	@State private var showingMoreDetails = false
	@State private var compactBar = false
	@State private var ratingPopup: RatingPopup.Mode?
	@State private var showingArtwork = false
	@State private var confirmingRemove = false
	@State private var namingCollection = false
	@State private var cast: [CastEntry] = []
	@State private var theme: UIColor?

	/// The design's teal, for Watched and Save rating.
	static let teal = Color(.pageWatched)

	init(film: Film, showsSeriesLink: Bool = true) {
		_film = Bindable(film)
		self.showsSeriesLink = showsSeriesLink
		_theme = State(initialValue: PageTheme.cached(Self.artURL(of: film)))
	}

	/// The poster, or the backdrop when there's no poster.
	private static func artURL(of film: Film) -> String {
		film.posterURL.isEmpty ? film.backdropURL : film.posterURL
	}

	private var pageColor: Color { Color(uiColor: theme ?? PageTheme.fallback) }
	private var pageDeep: Color { Color(uiColor: ArtworkBand.deeper(theme ?? PageTheme.fallback)) }
	private var shownStars: Double? { film.shownStars }

	private var trailer: some View {
		TitleTrailerSection(kind: .film, tmdbID: film.tmdbID, backdropURL: film.backdropURL, titled: false)
	}

	var body: some View {
		ScrollView {
			TitlePageColumns {
				header
				statusSwitch
				if film.status == .watched {
					WatchedDateButton(date: film.watchedAt) { film.setWatchedDate($0) }
					PageVerdictCard(rating: film.rating, stars: shownStars,
					                dateLine: film.watchedAt.map { "Watched \(FilmFacts.shortDate($0))" },
					                note: film.notes) {
						withAnimation(Glass.smooth) { ratingPopup = .edit }
					}
				}
				// On a wide iPad the trailer sits under the poster.
				PageColumnsReader { twoColumns in
					if twoColumns { trailer }
				}
			} rest: {
				PageColumnsReader { twoColumns in
					if !twoColumns { trailer }
				}
				if !film.synopsis.isEmpty { PageSynopsisCard(text: film.synopsis) }
				WhereToWatchSection(kind: .film, tmdbID: film.tmdbID)
				if showsSeriesLink, let franchiseID = film.franchiseID {
					PageFranchiseLink(id: franchiseID, name: film.franchiseName ?? "Series")
				}
				if let tmdbID = film.tmdbID {
					CommunitySection(title: .film(tmdbID: tmdbID), scale: .verdict, yours: film.rating?.rawValue)
				}
				ReviewsSection(kind: .film, tmdbID: film.tmdbID)
				PageSection(title: "Details") { detailsCard }
				if !cast.isEmpty { PageSection(title: "Cast") { PageCastRow(cast: cast) } }
			}
		}
		// The bar turns solid, with the poster and title, once the title is gone.
		.onScrollGeometryChange(for: Bool.self) { geometry in
			geometry.contentOffset.y + geometry.contentInsets.top > 290
		} action: { _, pastTitle in
			withAnimation(.easeInOut(duration: 0.2)) { compactBar = pastTitle }
		}
		.sheet(item: $ratingPopup) { mode in
			RatingPopup(film: film, mode: mode, tint: pageColor) { ratingPopup = nil }
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
		.confirmationDialog("Remove \u{201C}\(film.title)\u{201D}?", isPresented: $confirmingRemove,
		                    titleVisibility: .visible) {
			Button("Remove from Library", role: .destructive) {
				ManualPosterStore.remove(film.posterURL)
				ctx.delete(film, afterLeaving: dismiss)
			}
		} message: {
			Text("Its rating and note are removed with it.")
		}
		.task(id: film.tmdbID) { await loadCast() }
		.task(id: film.tmdbID) { await checkFranchise() }
		.task(id: Self.artURL(of: film)) {
			guard let sampled = await PageTheme.load(Self.artURL(of: film)), !Task.isCancelled,
			      sampled != theme else { return }
			withAnimation(.easeOut(duration: 0.4)) { theme = sampled }
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

	/// After design B of the alternatives: the facts in one line, genre and
	/// studio as chips, the rest — money, status, your rating, collections —
	/// folded under More, and the ways out.
	private var detailsCard: some View {
		let specs = film.specs
		let line = [FilmFacts.runtime(specs?.runtimeMinutes), FilmFacts.releaseDate(specs?.releaseDate),
		            specs.map { $0.spokenLanguages.prefix(2).joined(separator: ", ") }]
			.compactMap { $0 }.filter { !$0.isEmpty }
		let chips = film.genre.components(separatedBy: ", ").filter { !$0.isEmpty }
			+ (specs?.productionCompanies.prefix(1).map { $0 } ?? [])
		return VStack(alignment: .leading, spacing: 12) {
			if !line.isEmpty {
				Text(line.joined(separator: " · "))
					.font(.subheadline)
					.foregroundStyle(.white)
			}
			if !chips.isEmpty {
				TileFlowLayout(spacing: 6) {
					ForEach(chips, id: \.self) { chip in
						Text(chip)
							.font(.system(.caption, weight: .semibold))
							.foregroundStyle(.white)
							.padding(.horizontal, 10)
							.padding(.vertical, 5)
							.background(.white.opacity(0.12), in: Capsule())
					}
				}
			}
			DisclosureGroup(isExpanded: $showingMoreDetails) {
				VStack(spacing: 0) {
					if let budget = specs?.budget, budget > 0 {
						PageDetailRow("Budget", icon: "banknote", text: Self.money(budget))
						PageRowDivider()
					}
					if let revenue = specs?.revenue, revenue > 0 {
						PageDetailRow("Box office", icon: "chart.line.uptrend.xyaxis", text: Self.money(revenue))
						PageRowDivider()
					}
					if let status = specs?.status, !status.isEmpty {
						PageDetailRow("Status", icon: "info.circle", text: status)
						PageRowDivider()
					}
					PageDetailRow("Your rating", icon: "star", text: yourRatingSummary)
					PageRowDivider()
					PageDetailRow("Collections", icon: "rectangle.stack", text: collectionNames)
				}
				.padding(.top, 6)
			} label: {
				Text("More")
					.font(.system(.subheadline, weight: .semibold))
					.foregroundStyle(.white)
			}
			.tint(.white)

			HStack(spacing: 8) {
				if let id = film.imdbID, let url = IMDb.titleURL(id) {
					Link(destination: url) { Text("IMDb").titlePageCapsule() }
				}
				if let url = TitleLinks.tmdbMovie(film.tmdbID) {
					Link(destination: url) { Text("TMDb").titlePageCapsule() }
				}
				shareLink { Label("Share", systemImage: "square.and.arrow.up").titlePageCapsule() }
			}
		}
		.padding(14)
		.liquidCard(cornerRadius: 20)
	}

	/// "$30M", "$84.9M", "$900K".
	static func money(_ amount: Int) -> String {
		let value = Double(amount)
		if value >= 1_000_000_000 { return "$" + (value / 1_000_000_000).formatted(.number.precision(.fractionLength(0...1))) + "B" }
		if value >= 1_000_000 { return "$" + (value / 1_000_000).formatted(.number.precision(.fractionLength(0...1))) + "M" }
		if value >= 1_000 { return "$" + (value / 1_000).formatted(.number.precision(.fractionLength(0))) + "K" }
		return "$\(amount)"
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

	/// A film added before films kept their series asks TMDb once, here.
	private func checkFranchise() async {
		guard film.needsFranchiseCheck, let id = film.tmdbID, TMDbConfig.isConfigured,
		      let movie = try? await TMDbService.shared.movie(id: id), !Task.isCancelled else { return }
		withAnimation(Glass.smooth) { film.setFranchise(from: movie) }
	}

	private func loadCast() async {
		guard let tmdbID = film.tmdbID else { return }
		cast = await CreditsLoader.movieCast(movieID: tmdbID).people
	}

	// MARK: Menu

	/// The design's status menu. Refresh metadata isn't built, so it's shown but
	/// can't be chosen.
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
				Button {} label: {
					Label("Refresh metadata", systemImage: "arrow.clockwise")
					Text("Placeholder")
				}
				.disabled(true)
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
