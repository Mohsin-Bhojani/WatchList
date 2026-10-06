//
//  PhoneDiscoverView.swift
//  WatchList
//
//  The Discover tab: titles like the ones in your library, one at a time, set
//  out like Home's hero on a page that doesn't scroll, so a swipe up is never
//  taken for a scroll —
//    - the suggestion's big poster over the poster's own colour, and under it
//      its name, TMDb's average as stars with the verdict that comes to,
//      whether it's a TV show or a film, and its synopsis
//    - decided by swiping the card:
//        right: add it to the library as To Watch
//        left:  not interested, never offered again
//        up:    later, to the back of the queue until the fresh ones run out
//      and each library title gets 5 cards decided: with 3 or more of them
//      added it gets 5 more, otherwise the next title takes over (DiscoverRotation)
//    - Compared with your library: a sheet of how alike it is to every title in
//      the library, the closest first
//    - Filter, from a second tap on Discover: TV shows, films or both; any of
//      TMDb's genres, in rows that scroll sideways; and More like, the one
//      library title suggestions come from. A line under the header says
//      what's set
//  What's offered, in what order and how alike: DiscoverFeed.
//

import SwiftUI
import SwiftData

struct PhoneDiscoverView: View {
	/// Whether the page is on screen, for the tab bar to read. It never scrolls,
	/// so a second tap on Discover always opens the filter.
	@Binding var atTop: Bool
	@Binding var showingFilters: Bool

	@Environment(\.modelContext) private var ctx
	@Environment(\.colorScheme) private var systemScheme
	@Query(sort: \Show.dateAdded, order: .reverse) private var shows: [Show]
	@Query(sort: \Film.dateAdded, order: .reverse) private var films: [Film]
	@Query private var decisions: [SuggestionDecision]
	/// Set by the first decision, once the hint under the card has done its job.
	@AppStorage("discoverSwipeLearned") private var swipeLearned = false

	@State private var loader = DiscoverLoader()
	@State private var filter = DiscoverFilter()
	@State private var rotation = DiscoverRotation()
	/// What's typed under Describe, and what asking for it found.
	@State private var describeDraft = ""
	@State private var describe = DescribeSession()
	/// Titles swiped right still being added, kept out of the queue until they're in.
	@State private var adding: Set<String> = []
	/// This session's decisions, applied straight away so the next card comes in
	/// with the same animation; the saved ones can arrive a moment later.
	@State private var turnedDown: Set<String> = []
	@State private var putOffNow: [String: Date] = [:]
	/// The suggestion whose comparison sheet is open.
	@State private var comparing: Suggestion?
	@State private var addError: String?
	@State private var tone: UIColor?
	@State private var width: CGFloat = 0

	/// When the queue needs topping up: the seeds or the filter changed, fewer
	/// cards are ready than Discover wants, or a lookup finished.
	private struct FillTrigger: Equatable {
		let seeds: [UUID]
		let runningLow: Bool
		let fetched: Int
		let filter: DiscoverFilter
	}

	/// What a description is looked up with besides its words.
	private struct DescribeInputs: Equatable {
		let kind: BrowseKind
		let genres: Set<String>
	}

	/// The genre tiles for the chosen type.
	private var genreOptions: [String] {
		DiscoverFilter.genreOptions(for: filter.kind, tv: loader.tvGenres, movie: loader.movieGenres)
	}

	var body: some View {
		let library = shows.map(WatchedTitle.show) + films.map(WatchedTitle.film)
		// The card up, and what's ready behind it — worked out as the watch does.
		// What the library says about taste: each title's suggestions come best fit first.
		let taste = TasteProfile(library)
		let deal = DiscoverDeal(seeds: DiscoverFeed.seeds(shows: shows, films: films), filter: filter,
		                        rotation: rotation, similar: loader.similar, fetched: loader.fetched,
		                        excluded: excludedIDs(library), putOff: putOffDates(), score: taste.score)
		// A description sets the cards aside for its own matches.
		let describing = !filter.describe.isEmpty
		let describedQueue = describing ? describe.results.filter { !deal.skipped.contains($0.id) } : []
		let current = describing ? describedQueue.first : deal.current
		let upcoming = upcomingArtwork(after: current, in: describing ? describedQueue : deal.queue)

		NavigationStack {
			VStack(spacing: 0) {
				ScreenHeader(title: "Discover", onBand: current != nil)
				if let filterSummary = filter.summary(seedTitle: deal.picked?.title) {
					FilterSummaryButton(summary: filterSummary) { showingFilters = true }
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding(.horizontal, 20)
						.padding(.top, 8)
				}
				if let addError { errorBanner(addError) }
				if let current {
					DiscoverCard(suggestion: current,
					             reason: describing ? describe.query.map { "Matches \($0.summary)" }
					                                : DiscoverFeed.reason(for: current, in: library),
					             // The height left over sets its size on a phone; on an
					             // iPad this keeps it from filling the whole width.
					             posterMaxWidth: width > 0 ? width * 0.7 : 250,
					             showsHint: !swipeLearned) { decide($0, on: current) }
						.id(current.id)
						.transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)),
						                        removal: .opacity))
					comparisonButton(current, library: library)
						.padding(.top, 14)
						.padding(.bottom, 12)
				} else {
					placeholder(seeds: deal.drawingSeeds)
					Spacer(minLength: 0)
				}
			}
			.readableColumn()
			.frame(maxHeight: .infinity, alignment: .top)
			.background { backdrop(tinted: current != nil) }
			.environment(\.colorScheme, current == nil ? systemScheme : .dark)
			.screenBar("Discover", onBand: current != nil)
			.onAppear { atTop = true }
			.onDisappear { atTop = false }
			.task { await loader.loadGenres() }
			.task(id: current?.largePosterURL) { await loadTone(current?.largePosterURL) }
			// The next cards' artwork, so each comes in with its poster and colour.
			.task(id: upcoming) {
				for url in upcoming { _ = await PageTheme.load(url) }
			}
			.onChange(of: FillTrigger(seeds: deal.seedOrder, runningLow: deal.ready < DiscoverFeed.readyAhead,
			                          fetched: loader.fetched.count, filter: filter), initial: true) {
				guard filter.describe.isEmpty else { return }
				let matching = filter
				let turn = rotation
				let ordered = deal.ordered
				let skipped = deal.skipped
				let dealing = deal.dealing
				Task {
					await loader.fill(from: ordered, wanted: DiscoverFeed.readyAhead, excluding: skipped,
					                  matching: matching, counting: dealing, rotation: turn)
				}
			}
			// Genres the new type doesn't have would hide everything, and so would
			// a title of the other type.
			.onChange(of: filter.kind) {
				filter.genres.formIntersection(genreOptions)
				if filter.seed != nil && deal.picked == nil { filter.seed = nil }
			}
			// Asking again when the type or genres change, so the matches follow them.
			.onChange(of: DescribeInputs(kind: filter.kind, genres: filter.genres)) {
				if !filter.describe.isEmpty { runDescribe(library: library) }
			}
			// Reset clears the description with the rest of the filter.
			.onChange(of: filter.describe) {
				if filter.describe.isEmpty { describe.clear(); describeDraft = "" }
			}
			.sheet(item: $comparing) { comparisonSheet($0, library: library) }
		}
		// Outside the page's dark colouring, so the filter sheet takes the system's.
		.sheet(isPresented: $showingFilters) { filterSheet(seeds: deal.seeds, library: library) }
		.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
	}

	/// Looks up the description in the filter, then ranks it by the library's taste.
	private func runDescribe(library: [WatchedTitle]) {
		let text = filter.describe
		let kind = filter.kind
		let genres = filter.genres
		let taste = TasteProfile(library)
		Task { await describe.run(text, kind: kind, picked: genres, taste: taste) }
	}

	/// Type, Genre (a dropdown), Describe, then More like — opened tall enough to show them.
	private func filterSheet(seeds: [WatchedTitle], library: [WatchedTitle]) -> some View {
		FilterSheet(title: "Filter", canReset: !filter.isDefault, phoneDetents: [.fraction(0.68), .large]) {
			filter = DiscoverFilter()
		} content: {
			SegmentedFilter(title: "Type", options: BrowseKind.allCases, selection: $filter.kind) { $0.label }
			let genres = genreOptions
			if !genres.isEmpty {
				GenreRowsFilter(options: genres, picked: $filter.genres)
			}
			DescribeFilter(draft: $describeDraft, applied: filter.describe, session: describe) { text in
				filter.describe = text
				if text.isEmpty { describe.clear() } else { runDescribe(library: library) }
			}
			if !seeds.isEmpty {
				MoreLikeFilter(seeds: seeds, picked: $filter.seed)
			}
		}
	}

	// MARK: Queue

	/// When each put-off title was last put off, saved or just now.
	private func putOffDates() -> [String: Date] {
		var dates = putOffNow
		for decision in decisions where decision.choice == .later {
			dates[decision.key] = max(dates[decision.key] ?? .distantPast, decision.decidedAt)
		}
		return dates
	}

	/// In the library, turned down, or on its way in.
	private func excludedIDs(_ library: [WatchedTitle]) -> Set<String> {
		var ids = adding.union(turnedDown)
		for item in library {
			if let tmdbID = item.tmdbID { ids.insert(AddCandidate.key(item.kind, tmdbID)) }
		}
		for decision in decisions where decision.choice == .notInterested { ids.insert(decision.key) }
		return ids
	}

	/// The posters of the cards that can come after `current` — the next from its
	/// title, and the first from another, for when this decision moves on.
	private func upcomingArtwork(after current: Suggestion?, in queue: [Suggestion]) -> [String] {
		guard let current else { return [] }
		let rest = queue.dropFirst()
		let fromAnotherTitle = rest.first { $0.seeds.first != current.seeds.first }
		return [rest.first, fromAnotherTitle].compactMap { $0?.largePosterURL }
	}

	// MARK: Decisions

	/// Acts on a decision once the card has flown off, counting it against the
	/// library title the suggestion came from.
	private func decide(_ decision: CardDecision, on suggestion: Suggestion) {
		swipeLearned = true
		if let seed = suggestion.seeds.first {
			withAnimation(Glass.smooth) { _ = rotation.record(decision, from: seed) }
		}
		switch decision {
		case .add:           add(suggestion)
		case .notInterested: record(.notInterested, for: suggestion)
		case .later:         record(.later, for: suggestion)
		}
	}

	private func record(_ choice: SuggestionChoice, for suggestion: Suggestion) {
		Haptics.tap(.medium)
		let now = Date.now
		withAnimation(Glass.smooth) {
			switch choice {
			case .notInterested: turnedDown.insert(suggestion.id)
			case .later:         putOffNow[suggestion.id] = now
			}
		}
		if let saved = decisions.first(where: { $0.key == suggestion.id }) {
			saved.choice = choice
			saved.decidedAt = now
		} else {
			ctx.insert(SuggestionDecision(key: suggestion.id, choice: choice, decidedAt: now))
		}
	}

	/// Moves on straight away and adds it in the background — a show brings every
	/// episode with it. If that fails, it's back at the front with the reason.
	private func add(_ suggestion: Suggestion) {
		Haptics.success()
		withAnimation(Glass.smooth) {
			addError = nil
			_ = adding.insert(suggestion.id)
		}
		Task {
			let importer = ImportCoordinator()
			let added = await importer.importFromTMDb(id: suggestion.tmdbID, kind: suggestion.kind, into: ctx)
			withAnimation(Glass.smooth) {
				if added == nil {
					Haptics.warning()
					var reason = "try again"
					if case .failed(let message) = importer.phase { reason = message }
					addError = "Couldn't add \(suggestion.title): \(reason)"
				}
				_ = adding.remove(suggestion.id)
			}
		}
	}

	// MARK: Comparison

	/// Opens the comparison sheet, naming the closest title in the library.
	private func comparisonButton(_ suggestion: Suggestion, library: [WatchedTitle]) -> some View {
		let closest = Similarity.closest(to: suggestion, in: library)
		return Button {
			Haptics.tap()
			comparing = suggestion
		} label: {
			HStack(spacing: 12) {
				Image(systemName: "chart.bar.xaxis")
					.font(.system(size: 16, weight: .semibold))
				VStack(alignment: .leading, spacing: 1) {
					Text("Compared with your library")
						.font(.system(size: 15, weight: .semibold))
					if let closest {
						Text("Closest: \(closest.title.title) · \(closest.percent)%")
							.font(.system(size: 12, weight: .medium))
							.foregroundStyle(.white.opacity(0.65))
							.lineLimit(1)
					}
				}
				Spacer(minLength: 0)
				Image(systemName: "chevron.up")
					.font(.system(size: 13, weight: .bold))
					.foregroundStyle(.white.opacity(0.7))
			}
			.foregroundStyle(.white)
			.padding(.horizontal, 18)
			.frame(height: 56)
			.contentShape(Capsule())
		}
		.buttonStyle(.plain)
		.glassEffect(.regular.interactive(), in: Capsule())
		.padding(.horizontal, 20)
		.accessibilityHint("Shows how alike it is to each title in your library")
	}

	private func comparisonSheet(_ suggestion: Suggestion, library: [WatchedTitle]) -> some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 12) {
					Text("How alike \(suggestion.title) is to each title you have, from shared genres, the title it was suggested from, TV or film, and the year.")
						.font(.system(size: 13, weight: .medium))
						.foregroundStyle(.white.opacity(0.65))
						.fixedSize(horizontal: false, vertical: true)
					LazyVStack(spacing: 8) {
						ForEach(Similarity.rows(for: suggestion, in: library)) { row in
							NavigationLink { row.title.destination } label: { similarityRow(row) }
								.buttonStyle(.pressable)
						}
					}
				}
				.padding(.horizontal, 20)
				.padding(.bottom, 24)
			}
			.navigationTitle("Compared with your library")
			.navigationBarTitleDisplayMode(.inline)
		}
		// Closed by dragging its handle down.
		.preferredColorScheme(.dark)
		.presentationDetents([.medium, .large])
		.presentationDragIndicator(.visible)
		.presentationBackground {
			let base = tone ?? PageTheme.fallback
			LinearGradient(colors: [Color(uiColor: ArtworkBand.deeper(base, by: 0.8)),
			                        Color(uiColor: ArtworkBand.deeper(base))],
			               startPoint: .top, endPoint: .bottom)
		}
	}

	private func similarityRow(_ row: SimilarityRow) -> some View {
		let item = row.title
		return HStack(spacing: 12) {
			PosterImage(urlString: item.posterURL, systemPlaceholder: item.placeholder)
				.frame(width: 40, height: 60)
				.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
			VStack(alignment: .leading, spacing: 6) {
				Text(item.title)
					.font(.system(size: 15, weight: .semibold))
					.foregroundStyle(.white)
					.lineLimit(1)
				ProgressView(value: Double(row.percent), total: 100)
					.tint(.white)
				Text("\(item.kindLabel) · \(item.rating?.rawValue ?? "Unrated")")
					.font(.system(size: 12, weight: .medium))
					.foregroundStyle(.white.opacity(0.6))
			}
			Text("\(row.percent)%")
				.font(.system(size: 18, weight: .bold, design: .rounded))
				.monospacedDigit()
				.foregroundStyle(.white)
				.frame(minWidth: 52, alignment: .trailing)
		}
		.padding(10)
		.background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("\(item.title), \(row.percent) percent alike")
	}

	// MARK: Nothing to show

	@ViewBuilder private func placeholder(seeds: [WatchedTitle]) -> some View {
		let waiting = loader.isLoading || seeds.contains { !loader.fetched.contains($0.id) }
		Group {
			if !filter.describe.isEmpty {
				describedPlaceholder
			} else if !TMDbConfig.isConfigured {
				EmptyState(icon: "key", title: "No TMDb key",
				           subtitle: "Discover finds its suggestions on TMDb, so it needs the API key. See README.md.")
			} else if seeds.isEmpty && filter.isDefault {
				EmptyState(icon: "sparkles", title: "Nothing to go on yet",
				           subtitle: "Add a few shows and films from TMDb, or rate the ones you have, and titles like them show up here.")
			} else if waiting {
				VStack(spacing: 12) {
					ProgressView()
						.controlSize(.large)
					Text("Finding titles like yours\u{2026}")
						.font(.system(size: 15, weight: .medium))
						.foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity)
				.padding(.vertical, 60)
			} else if loader.failed {
				VStack(spacing: 14) {
					EmptyState(icon: "wifi.slash", title: "Couldn't reach TMDb",
					           subtitle: "Check your connection, then try again.")
					Button("Try Again") { loader.retry() }
						.buttonStyle(.glass)
						.controlSize(.large)
				}
			} else if !filter.isDefault {
				EmptyState(icon: "line.3.horizontal.decrease.circle", title: "No matches",
				           subtitle: "Nothing suggested fits this filter. Try another type, genre or title.")
			} else {
				EmptyState(icon: "checkmark.seal", title: "You're all caught up",
				           subtitle: "That's every suggestion for now. Rate or add more titles and new ones show up here.")
			}
		}
		.padding(.top, 36)
	}

	/// While a description is being looked up, or when nothing fits it.
	@ViewBuilder private var describedPlaceholder: some View {
		switch describe.phase {
		case .failed(let message):
			EmptyState(icon: "wifi.slash", title: "Couldn\u{2019}t look that up", subtitle: message)
		case .ready:
			EmptyState(icon: "text.magnifyingglass", title: "Nothing matches",
			           subtitle: "Try describing it another way, or loosen the type and genre.")
		default:
			VStack(spacing: 12) {
				ProgressView()
					.controlSize(.large)
				Text("Finding titles that fit\u{2026}")
					.font(.system(size: 15, weight: .medium))
					.foregroundStyle(.secondary)
			}
			.frame(maxWidth: .infinity)
			.padding(.vertical, 60)
		}
	}

	private func errorBanner(_ message: String) -> some View {
		Button {
			withAnimation(Glass.smooth) { addError = nil }
		} label: {
			Label(message, systemImage: "exclamationmark.triangle.fill")
				.font(.system(size: 13, weight: .semibold))
				.foregroundStyle(.white)
				.lineLimit(2)
				.padding(.horizontal, 14)
				.padding(.vertical, 10)
				.background(Glass.ratingSkip.opacity(0.9), in: Capsule())
		}
		.buttonStyle(.plain)
		.padding(.horizontal, 20)
		.padding(.top, 10)
		.accessibilityHint("Dismisses the message")
	}

	// MARK: Colour

	@ViewBuilder private func backdrop(tinted: Bool) -> some View {
		if tinted {
			let base = tone ?? PageTheme.fallback
			LinearGradient(colors: [Color(uiColor: base), Color(uiColor: ArtworkBand.deeper(base))],
			               startPoint: .top, endPoint: .bottom)
				.ignoresSafeArea()
		} else {
			GlassBackground()
		}
	}

	private func loadTone(_ url: String?) async {
		guard let url else { return }
		if let cached = PageTheme.cached(url) {
			withAnimation(.easeOut(duration: 0.3)) { tone = cached }
			return
		}
		guard let loaded = await PageTheme.load(url), !Task.isCancelled else { return }
		withAnimation(.easeOut(duration: 0.4)) { tone = loaded }
	}
}

// MARK: - Card

/// The suggestion on screen. It follows the finger, tilting as it goes and
/// saying what it's about to decide; let go past the threshold and it flies off
/// that way before deciding, short of it and it springs back. The drag is kept
/// in here, so the page around the card isn't redrawn as it moves.
private struct DiscoverCard: View {
	let suggestion: Suggestion
	let reason: String?
	let posterMaxWidth: CGFloat
	let showsHint: Bool
	let onDecide: (CardDecision) -> Void

	@State private var offset: CGSize = .zero
	/// Set once it's decided, so a second swipe can't decide it again.
	@State private var decided = false

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
		VStack(spacing: 12) {
			if let reason {
				Text(reason)
					.font(.system(size: 14, weight: .medium))
					.foregroundStyle(.white.opacity(0.8))
					.lineLimit(1)
					.minimumScaleFactor(0.85)
			}
			PosterImage(urlString: suggestion.largePosterURL, systemPlaceholder: suggestion.placeholder)
				.aspectRatio(2.0 / 3.0, contentMode: .fit)
				.clipShape(shape)
				.overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 1))
				.overlay { hint }
				.shadow(color: .black.opacity(0.35), radius: 24, y: 12)
				// Whatever height the rest leaves, so the page never has to scroll.
				.frame(maxWidth: posterMaxWidth, maxHeight: .infinity)
				.accessibilityHidden(true)
			VStack(spacing: 8) {
				Text(suggestion.title)
					.font(.system(size: 26, weight: .bold))
					.foregroundStyle(.white)
					.multilineTextAlignment(.center)
					.lineLimit(2)
					.minimumScaleFactor(0.8)
					.accessibilityAddTraits(.isHeader)
				score
				HStack(spacing: 8) {
					if let verdict = suggestion.equivalentVerdict { VerdictChip(rating: verdict) }
					Label(suggestion.kindLabel, systemImage: suggestion.kind.systemImage)
						.font(.system(size: 12, weight: .semibold))
						.foregroundStyle(.white)
						.padding(.horizontal, 9)
						.padding(.vertical, 5)
						.background(.white.opacity(0.12), in: Capsule())
				}
			}
			.fixedSize(horizontal: false, vertical: true)
			if !suggestion.overview.isEmpty {
				Text(suggestion.overview)
					.font(.system(size: 15))
					.foregroundStyle(.white.opacity(0.82))
					.multilineTextAlignment(.center)
					.lineLimit(4)
					.fixedSize(horizontal: false, vertical: true)
			}
			if showsHint {
				Text("Swipe right to add · left if not interested · up for later")
					.font(.system(size: 12, weight: .medium))
					.foregroundStyle(.white.opacity(0.55))
					.lineLimit(1)
					.minimumScaleFactor(0.8)
			}
		}
		.padding(.horizontal, 24)
		.padding(.top, 6)
		.contentShape(Rectangle())
		.offset(offset)
		.rotationEffect(.degrees(Double(offset.width) / 20), anchor: .bottom)
		.gesture(swipe)
		.accessibilityElement(children: .contain)
		.accessibilityActions {
			Button(CardDecision.add.label) { commit(.add) }
			Button(CardDecision.notInterested.label) { commit(.notInterested) }
			Button(CardDecision.later.label) { commit(.later) }
		}
	}

	/// TMDb's average, as stars and as the number.
	@ViewBuilder private var score: some View {
		if let average = suggestion.averageScore, let stars = suggestion.averageStars {
			HStack(spacing: 8) {
				StarsLabel(value: stars, size: 13, showsValue: false)
				Text("\(average.formatted(.number.precision(.fractionLength(1)))) average on TMDb")
					.font(.system(size: 14, weight: .medium))
					.foregroundStyle(.white.opacity(0.8))
			}
			.accessibilityElement(children: .combine)
		} else {
			Text("No ratings on TMDb yet")
				.font(.system(size: 14, weight: .medium))
				.foregroundStyle(.white.opacity(0.7))
		}
	}

	/// What the card is about to decide, stamped on the poster and firming up as
	/// it nears the threshold.
	@ViewBuilder private var hint: some View {
		if let lean = CardDecision.leaning(offset) {
			Label(lean.decision.swipeLabel, systemImage: lean.decision.symbol)
				.font(.system(size: 17, weight: .heavy))
				.foregroundStyle(.white)
				.padding(.horizontal, 16)
				.padding(.vertical, 9)
				.background(lean.decision.tint ?? .black.opacity(0.6), in: Capsule())
				.scaleEffect(0.85 + 0.15 * lean.progress)
				.opacity(Double(lean.progress))
		}
	}

	private var swipe: some Gesture {
		DragGesture(minimumDistance: 12)
			.onChanged { value in
				guard !decided else { return }
				let wasPast = CardDecision.forSwipe(translation: offset, predictedEnd: offset) != nil
				offset = value.translation
				let isPast = CardDecision.forSwipe(translation: offset, predictedEnd: offset) != nil
				// A tick as it crosses the threshold, either way.
				if isPast != wasPast { Haptics.selection() }
			}
			.onEnded { value in
				guard !decided else { return }
				if let decision = CardDecision.forSwipe(translation: value.translation,
				                                        predictedEnd: value.predictedEndTranslation) {
					commit(decision)
				} else {
					withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { offset = .zero }
				}
			}
	}

	/// Flies off the way the decision goes, from wherever it's been dragged, then
	/// decides.
	private func commit(_ decision: CardDecision) {
		guard !decided else { return }
		decided = true
		withAnimation(.easeIn(duration: 0.24)) { offset = decision.flyOff(from: offset) }
		Task {
			try? await Task.sleep(for: .milliseconds(240))
			onDecide(decision)
			// Back at rest, for when the same title comes straight round again.
			withAnimation(Glass.smooth) { offset = .zero }
			decided = false
		}
	}
}

private extension CardDecision {
	/// The swipe label's colour.
	var tint: Color? {
		switch self {
		case .add:           return Glass.ratingPerfection
		case .notInterested: return Glass.ratingSkip
		case .later:         return nil
		}
	}
}
