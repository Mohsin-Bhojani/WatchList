//
//  PhoneAddSearchView.swift
//  WatchList
//
//  The iPhone Search tab, which is also where titles get added. One search
//  field does what the iPad Add sheet splits into three modes (AddEntryView.swift):
//    - type a title    -> TMDb search results, each addable in one tap
//    - paste a link    -> the IMDb or TMDb title behind it, ready to add
//    - add manually    -> offered up front, under every result list, and in
//                         place of results when TMDb has nothing
//
//  Matching titles already in the library are listed first, so this also
//  takes over from the library-only Search the old dock had.
//

import SwiftUI
import SwiftData

/// One addable title, whether it came from a text search or a pasted link.
struct AddCandidate: Identifiable, Equatable {
	let kind: MediaKind
	let tmdbID: Int
	let title: String
	let year: String
	let posterURL: String

	/// Kind + id: TMDb numbers films and shows separately, so the same id can
	/// arrive as both.
	var id: String { Self.key(kind, tmdbID) }

	static func key(_ kind: MediaKind, _ tmdbID: Int) -> String { kind.key(tmdbID: tmdbID) }
}

extension AddCandidate {
	init(_ item: TMDbSearchItem) {
		self.init(kind: item.media_type == "tv" ? .show : .film,
		          tmdbID: item.id,
		          title: item.displayTitle,
		          year: String((item.release_date ?? item.first_air_date ?? "").prefix(4)),
		          posterURL: TMDbConfig.poster(item.poster_path))
	}
}

struct PhoneAddSearchView: View {
	@Environment(\.modelContext) private var ctx
	@StateObject private var importer = ImportCoordinator()

	@Query(sort: \Show.dateAdded, order: .reverse) private var libraryShows: [Show]
	@Query(sort: \Film.dateAdded, order: .reverse) private var libraryFilms: [Film]

	@State private var query = ""
	/// The trimmed query whose results are on screen. While it trails the
	/// field, a lookup is pending and "no results" would be premature.
	@State private var settledQuery = ""

	@State private var results: [AddCandidate] = []
	@State private var searchError: String?
	@State private var linkMatch: AddCandidate?
	@State private var linkError: String?

	@State private var addingID: String?
	@State private var addedIDs: Set<String> = []
	@State private var importError: String?
	@State private var confirmation: Confirmation?
	@State private var manualDraft: ManualDraft?

	/// "Added X" stays up until the search text changes.
	private struct Confirmation {
		let title: String
		let query: String
	}

	private struct ManualDraft: Identifiable {
		let id = UUID()
		let title: String
		let imdb: String
	}

	private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
	private var isSettled: Bool { settledQuery == trimmedQuery }

	/// Everything already imported, keyed like `AddCandidate.id`. Titles added
	/// by hand have no `tmdbID` and so cannot be matched — they are skipped.
	private var libraryIDs: Set<String> {
		var ids = Set(libraryShows.compactMap { $0.tmdbID.map { AddCandidate.key(.show, $0) } })
		ids.formUnion(libraryFilms.compactMap { $0.tmdbID.map { AddCandidate.key(.film, $0) } })
		return ids
	}

	var body: some View {
		NavigationStack {
			ZStack {
				GlassBackground()
				ScrollView {
					VStack(alignment: .leading, spacing: 14) {
						// Like the other tabs: the name on the left, the profile on the right.
						ScreenHeader(title: "Search")
						VStack(alignment: .leading, spacing: 18) {
							banners
							content
						}
						.padding(.horizontal, 18)
						.padding(.bottom, 18)
					}
				}
				.scrollDismissesKeyboard(.interactively)
			}
			// Not shown, but it names the back button on a title opened from here.
			.navigationTitle("Search")
			// On an iPad the bar shows, and the search field is in it.
			.screenBar("Search")
			.searchable(text: $query, prompt: "Title, IMDb or TMDb link")
			.task(id: trimmedQuery) { await refresh() }
			.sheet(item: $manualDraft) { draft in
				PhoneManualEntryView(title: draft.title, imdb: draft.imdb) { saved in
					confirmation = Confirmation(title: saved, query: trimmedQuery)
				}
			}
		}
	}

	// MARK: - Content

	@ViewBuilder private var banners: some View {
		if let confirmation, confirmation.query == trimmedQuery {
			statusRow(icon: "checkmark.circle.fill", tint: Glass.watched,
			          text: "Added \u{201C}\(confirmation.title)\u{201D} to your library.")
		}
		if let importError {
			statusRow(icon: "xmark.octagon.fill", tint: .red, text: importError)
		}
	}

	@ViewBuilder private var content: some View {
		let text = trimmedQuery
		if text.isEmpty {
			startOptions
		} else if let link = SearchLink.parse(text) {
			linkSection(link)
		} else if SearchLink.looksLikeLink(text) {
			unsupportedLinkSection
		} else if text.count >= 2 {
			librarySection(for: text)
			tmdbSection(for: text)
		}
	}

	/// Before anything is typed: the three ways in.
	private var startOptions: some View {
		VStack(alignment: .leading, spacing: 10) {
			SectionLabel(text: "Ways to add", systemImage: "plus")
			optionRow(icon: "magnifyingglass", title: "Search TMDb",
			          subtitle: "Type a film or show in the search field. A show brings every season and episode with it.") {
				EmptyView()
			}
			optionRow(icon: "link", title: "Paste a link",
			          subtitle: "An IMDb or TMDb title link adds that exact title.") {
				PasteButton(payloadType: String.self) { strings in
					guard let first = strings.first else { return }
					Task { @MainActor in query = first }
				}
				.labelStyle(.iconOnly)
				.buttonBorderShape(.circle)
				.tint(Glass.accent)
			}
			Button { openManual() } label: {
				optionRow(icon: "square.and.pencil", title: "Add manually",
				          subtitle: "For anything TMDb doesn't have, or when you'd rather type it in.") {
					Image(systemName: "chevron.right")
						.font(.system(size: 13, weight: .bold))
						.foregroundStyle(.tertiary)
				}
			}
			.buttonStyle(.pressable)

			if !TMDbConfig.isConfigured {
				Label("No TMDb API key, so search and links are off — see README.md. Adding manually still works.",
				      systemImage: "exclamationmark.triangle.fill")
					.font(.system(size: 13, weight: .semibold, design: .rounded))
					.foregroundStyle(.orange)
					.padding(14)
					.glass(cornerRadius: 16)
			}
		}
	}

	private func linkSection(_ link: SearchLink) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			sectionHeader("\(link.sourceName) link", systemImage: "link")
			if !isSettled {
				loadingRow("Looking up the title\u{2026}")
			} else if let linkMatch {
				candidateRow(linkMatch, inLibrary: libraryIDs.contains(linkMatch.id))
			} else {
				statusRow(icon: "xmark.octagon.fill", tint: .red,
				          text: linkError ?? "TMDb has no film or show for this link.")
				manualCapsule(label: "Add it manually", title: "", imdb: link.imdbID ?? "")
			}
		}
	}

	private var unsupportedLinkSection: some View {
		VStack(alignment: .leading, spacing: 10) {
			sectionHeader("Link", systemImage: "link")
			statusRow(icon: "questionmark.circle", tint: Color.secondary,
			          text: "That isn't a film or show link. Paste an IMDb title link (imdb.com/title/tt\u{2026}) or a TMDb one (themoviedb.org/movie/\u{2026} or /tv/\u{2026}).")
			manualCapsule(label: "Add manually instead", title: "", imdb: "")
		}
	}

	@ViewBuilder private func librarySection(for text: String) -> some View {
		let shows = libraryShows.filter { $0.title.localizedCaseInsensitiveContains(text) }
		let films = libraryFilms.filter { $0.title.localizedCaseInsensitiveContains(text) }
		if !shows.isEmpty || !films.isEmpty {
			VStack(alignment: .leading, spacing: 10) {
				sectionHeader("In your library", systemImage: "books.vertical")
				ForEach(shows) { show in
					NavigationLink { PhoneShowDetailView(show: show) } label: {
						GlassRow(title: show.title, subtitle: show.subtitle,
						         thumbURL: show.posterURL, thumbPlaceholder: "tv",
						         status: show.status, rating: show.rating)
					}
					.buttonStyle(.pressable)
				}
				ForEach(films) { film in
					NavigationLink { PhoneFilmDetailView(film: film) } label: {
						GlassRow(title: film.title,
						         subtitle: [film.year, film.genre].filter { !$0.isEmpty }.joined(separator: " · "),
						         thumbURL: film.posterURL, thumbPlaceholder: "film",
						         status: film.status, rating: film.rating)
					}
					.buttonStyle(.pressable)
				}
			}
		}
	}

	private func tmdbSection(for text: String) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			sectionHeader("From TMDb", systemImage: "magnifyingglass", busy: !isSettled && !results.isEmpty)
			if !results.isEmpty {
				resultList
				manualFooter(for: text)
			} else if !isSettled {
				loadingRow("Searching TMDb\u{2026}")
			} else if let searchError {
				statusRow(icon: "xmark.octagon.fill", tint: .red, text: searchError)
				manualCapsule(label: "Add \u{201C}\(text)\u{201D} manually", title: text, imdb: "")
			} else {
				noResults(for: text)
			}
		}
	}

	/// Built once per pass, not once per row: `libraryIDs` walks the whole library.
	private var resultList: some View {
		let owned = libraryIDs
		return VStack(spacing: 10) {
			ForEach(results) { candidateRow($0, inLibrary: owned.contains($0.id)) }
		}
	}

	private func noResults(for text: String) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("No results on TMDb for \u{201C}\(text)\u{201D}.")
				.font(.system(size: 15, weight: .semibold, design: .rounded))
				.foregroundStyle(.primary)
			Text("Check the spelling, or add it yourself — details and a poster can be filled in by hand.")
				.font(.system(size: 13, weight: .medium, design: .rounded))
				.foregroundStyle(.secondary)
			manualCapsule(label: "Add \u{201C}\(text)\u{201D} manually", title: text, imdb: "")
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(16)
		.glass(cornerRadius: 16)
	}

	// MARK: - Lookups

	private func refresh() async {
		let text = trimmedQuery
		guard text != settledQuery else { return }
		importError = nil

		guard !text.isEmpty else {
			results = []; searchError = nil; linkMatch = nil; linkError = nil
			settledQuery = text
			return
		}

		// Debounce rapid typing; a new keystroke cancels this task first.
		try? await Task.sleep(nanoseconds: 350_000_000)
		if Task.isCancelled { return }

		if let link = SearchLink.parse(text) {
			await lookUp(link)
		} else if text.count >= 2, !SearchLink.looksLikeLink(text) {
			await search(text)
		} else {
			results = []; searchError = nil; linkMatch = nil; linkError = nil
		}
		if Task.isCancelled { return }
		settledQuery = text
	}

	private func search(_ text: String) async {
		do {
			let items = try await TMDbService.shared.multiSearch(query: text)
			if Task.isCancelled { return }
			results = items.map { AddCandidate($0) }
			searchError = nil
		} catch {
			if Task.isCancelled { return }
			results = []
			searchError = Self.message(for: error)
		}
		linkMatch = nil; linkError = nil
	}

	private func lookUp(_ link: SearchLink) async {
		do {
			let match = try await Self.resolve(link)
			if Task.isCancelled { return }
			linkMatch = match
			linkError = nil
		} catch {
			if Task.isCancelled { return }
			linkMatch = nil
			linkError = Self.message(for: error)
		}
		results = []; searchError = nil
	}

	/// The title behind a link, or nil when TMDb has none.
	private static func resolve(_ link: SearchLink) async throws -> AddCandidate? {
		switch link {
		case .imdb(let imdbID):
			let found = try await TMDbService.shared.find(imdbID: imdbID)
			// Same precedence as ImportCoordinator.importFromIMDb: a show wins.
			if let tv = found.tv_results.first { return try await details(.show, tv.id) }
			if let movie = found.movie_results.first { return try await details(.film, movie.id) }
			return nil
		case .tmdb(let kind, let id):
			do {
				return try await details(kind, id)
			} catch TMDbError.http(404) {
				return nil
			}
		}
	}

	private static func details(_ kind: MediaKind, _ id: Int) async throws -> AddCandidate {
		switch kind {
		case .show:
			let tv = try await TMDbService.shared.tv(id: id)
			return AddCandidate(kind: .show, tmdbID: tv.id, title: tv.name ?? "Untitled",
			                    year: String((tv.first_air_date ?? "").prefix(4)),
			                    posterURL: TMDbConfig.poster(tv.poster_path))
		case .film:
			let movie = try await TMDbService.shared.movie(id: id)
			return AddCandidate(kind: .film, tmdbID: movie.id, title: movie.title ?? "Untitled",
			                    year: String((movie.release_date ?? "").prefix(4)),
			                    posterURL: TMDbConfig.poster(movie.poster_path))
		}
	}

	private static func message(for error: Error) -> String {
		(error as? LocalizedError)?.errorDescription ?? error.localizedDescription
	}

	// MARK: - Adding

	private func add(_ candidate: AddCandidate) {
		addingID = candidate.id
		importError = nil
		Haptics.tap(.medium)
		Task {
			let result = await importer.importFromTMDb(id: candidate.tmdbID, kind: candidate.kind, into: ctx)
			addingID = nil
			if result != nil {
				Haptics.success()
				addedIDs.insert(candidate.id)
				confirmation = Confirmation(title: candidate.title, query: trimmedQuery)
			} else {
				Haptics.warning()
				if case .failed(let message) = importer.phase { importError = message }
			}
		}
	}

	private func openManual(title: String = "", imdb: String = "") {
		Haptics.tap()
		manualDraft = ManualDraft(title: title, imdb: imdb)
	}

	// MARK: - Rows

	private func candidateRow(_ candidate: AddCandidate, inLibrary: Bool) -> some View {
		let isShow = candidate.kind == .show
		// Added just now reads differently from "you already had this".
		let addedNow = addedIDs.contains(candidate.id)
		let owned = addedNow || inLibrary
		let tag = addedNow ? "Added" : (inLibrary ? "In your library" : "")
		let subtitle = [isShow ? "TV Series" : "Film", candidate.year, tag]
			.filter { !$0.isEmpty }.joined(separator: " · ")
		return Button { add(candidate) } label: {
			HStack(spacing: 12) {
				PosterImage(urlString: candidate.posterURL, systemPlaceholder: isShow ? "tv" : "film")
					.frame(width: 46, height: 69)
					.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
				VStack(alignment: .leading, spacing: 3) {
					Text(candidate.title)
						.font(.system(size: 15, weight: .bold, design: .serif))
						.foregroundStyle(.primary)
						.lineLimit(2)
					Text(subtitle)
						.font(.system(size: 12, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
				}
				Spacer(minLength: 0)
				if addingID == candidate.id {
					ProgressView()
				} else {
					Image(systemName: owned ? "checkmark.circle.fill" : "plus.circle.fill")
						.font(.system(size: 22, weight: .semibold))
						.foregroundStyle(owned ? Glass.watched : Glass.accent)
				}
			}
			.padding(10)
			.glass(cornerRadius: 16)
		}
		.buttonStyle(.pressable)
		.disabled(importer.isWorking || owned)
		.opacity(owned ? 0.6 : 1)
	}

	private func optionRow<Trailing: View>(icon: String, title: String, subtitle: String,
	                                       @ViewBuilder trailing: () -> Trailing) -> some View {
		HStack(spacing: 12) {
			Image(systemName: icon)
				.font(.system(size: 16, weight: .semibold))
				.foregroundStyle(Glass.accent)
				.frame(width: 34, height: 34)
				.background(Glass.accent.opacity(0.12), in: Circle())
			VStack(alignment: .leading, spacing: 3) {
				Text(title)
					.font(.system(size: 15, weight: .semibold, design: .rounded))
					.foregroundStyle(.primary)
				Text(subtitle)
					.font(.system(size: 12, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
					.fixedSize(horizontal: false, vertical: true)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			trailing()
		}
		.padding(12)
		.glass(cornerRadius: 16)
	}

	private func manualCapsule(label: String, title: String, imdb: String) -> some View {
		Button { openManual(title: title, imdb: imdb) } label: {
			HStack(spacing: 8) {
				Image(systemName: "square.and.pencil")
				Text(label).lineLimit(1)
			}
			.font(.system(size: 15, weight: .bold, design: .rounded))
			.foregroundStyle(.white)
			.frame(maxWidth: .infinity)
			.padding(.vertical, 14)
			.padding(.horizontal, 16)
			.background(
				Capsule().fill(LinearGradient(colors: [Glass.accent, Glass.accent2],
				                              startPoint: .leading, endPoint: .trailing))
			)
		}
		.buttonStyle(.pressable)
	}

	/// Under a result list: quieter than the capsule, since a match may be there.
	private func manualFooter(for text: String) -> some View {
		Button { openManual(title: text) } label: {
			HStack(spacing: 8) {
				Image(systemName: "square.and.pencil")
				Text("Not listed? Add \u{201C}\(text)\u{201D} manually")
					.lineLimit(1)
				Spacer(minLength: 0)
				Image(systemName: "chevron.right")
					.font(.system(size: 12, weight: .bold))
					.foregroundStyle(.tertiary)
			}
			.font(.system(size: 14, weight: .semibold, design: .rounded))
			.foregroundStyle(Glass.accent)
			.padding(14)
			.glass(cornerRadius: 16)
		}
		.buttonStyle(.pressable)
	}

	private func sectionHeader(_ text: String, systemImage: String, busy: Bool = false) -> some View {
		HStack {
			SectionLabel(text: text, systemImage: systemImage)
			Spacer()
			if busy { ProgressView().controlSize(.small) }
		}
	}

	private func loadingRow(_ text: String) -> some View {
		HStack(spacing: 10) {
			ProgressView()
			Text(text)
				.font(.system(size: 13, weight: .medium, design: .rounded))
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(14)
		.glass(cornerRadius: 16)
	}

	private func statusRow(icon: String, tint: Color, text: String) -> some View {
		HStack(spacing: 8) {
			Image(systemName: icon).foregroundStyle(tint)
			Text(text)
				.font(.system(size: 13, weight: .medium, design: .rounded))
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(14)
		.glass(cornerRadius: 16)
	}
}
