//
//  DiscoverFeed.swift
//  WatchList
//
//  What the Discover tab offers and why, worked out from the library. Discover's
//  queue, filter, rotation, swipes and TMDb lookups need no models and are shared
//  with the watch app, in Shared/DiscoverQueue.swift. Here are the parts that
//  read the library:
//    - the seeds: the library titles suggestions start from — rated Perfection,
//      then Go For It, then Timepass, each the most recently rated first, then
//      the rest, the most recently added first
//    - why a suggestion is offered, and More like's caption and See all groups
//    - how alike a suggestion is to every title in the library
//

import Foundation

/// A show or film in the library, as a title Discover's suggestions come from.
extension WatchedTitle: SuggestionSeed {}

extension DiscoverFeed {
	/// The library titles suggestions start from, in order: rated Perfection,
	/// then Go For It, then Timepass — each the most recently rated first — then
	/// the unrated, the most recently added first. Titles rated Skip aren't
	/// used, nor titles added by hand, which TMDb doesn't know.
	static func seeds(shows: [Show], films: [Film]) -> [WatchedTitle] {
		// Each title's values are read once: sorting the titles themselves goes
		// back to the models at every comparison, on every redraw of Discover.
		let ranked = (shows.map(WatchedTitle.show) + films.map(WatchedTitle.film))
			.compactMap { item -> (item: WatchedTitle, rank: Int, date: Date)? in
				guard item.tmdbID != nil else { return nil }
				// Titles rated before verdicts were dated fall back to when they were watched or added.
				switch item.rating {
				case .perfection: return (item, 0, item.ratedAt ?? item.watchedAt ?? item.dateAdded)
				case .goForIt:    return (item, 1, item.ratedAt ?? item.watchedAt ?? item.dateAdded)
				case .timepass:   return (item, 2, item.ratedAt ?? item.watchedAt ?? item.dateAdded)
				case nil:         return (item, 3, item.dateAdded)
				case .skip:       return nil
				}
			}
		return ranked.sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.date > $1.date }.map(\.item)
	}

	/// Why it's offered, from the first title it was suggested from.
	static func reason(for suggestion: Suggestion, in library: [WatchedTitle]) -> String? {
		guard let seedID = suggestion.seeds.first,
		      let seed = library.first(where: { $0.id == seedID }) else { return nil }
		return "Because \(becauseOf(seed))"
	}

	/// Under More like's posters: what picking a title narrows Discover to.
	static func moreLikeCaption(for seed: WatchedTitle?) -> String {
		guard let seed else { return "Suggestions from your whole library, best rated first." }
		return "Only what\u{2019}s suggested because \(becauseOf(seed))."
	}

	/// "you rated Severance Perfection", or "you added Slow Horses".
	private static func becauseOf(_ seed: WatchedTitle) -> String {
		because(title: seed.title, rating: seed.rating)
	}

	/// A group on More like's See all: the seeds given one verdict, or the unrated.
	struct SeedGroup: Identifiable {
		let rating: Rating?
		let titles: [WatchedTitle]

		var id: String { name }
		/// "Rated Perfection", or "Added".
		var name: String { rating.map { "Rated \($0.rawValue)" } ?? "Added" }
	}

	/// More like's See all: `seeds` under their verdicts, best first, then the
	/// unrated as Added — each group in seed order, and only the titles with
	/// `search` in their name.
	static func seedGroups(_ seeds: [WatchedTitle], matching search: String = "") -> [SeedGroup] {
		let query = search.trimmingCharacters(in: .whitespaces)
		let shown = query.isEmpty ? seeds : seeds.filter { $0.title.localizedCaseInsensitiveContains(query) }
		let verdicts: [Rating?] = [.perfection, .goForIt, .timepass, nil]
		return verdicts.compactMap { rating in
			let titles = shown.filter { $0.rating == rating }
			return titles.isEmpty ? nil : SeedGroup(rating: rating, titles: titles)
		}
	}
}

// MARK: - Similarity

/// A library title beside a suggestion, and how alike the two are.
struct SimilarityRow: Identifiable {
	let title: WatchedTitle
	let percent: Int

	var id: UUID { title.id }
}

extension Similarity {
	/// How alike a suggestion and a library title are, 0 to 100. TMDb gives no
	/// score of its own, so it's weighed from what both sides carry:
	///   - 55: the genres they share, out of every genre either has
	///   - 25: TMDb suggested it from this very title
	///   - 12: both TV shows, or both films
	///   -  8: how near their years are — none at 25 years apart, half when
	///         either year isn't known
	static func percent(_ suggestion: Suggestion, _ title: WatchedTitle) -> Int {
		percent(suggestion, genres: genreSet(suggestion.genres), title)
	}

	/// Every library title beside the suggestion, the most alike first.
	static func rows(for suggestion: Suggestion, in library: [WatchedTitle]) -> [SimilarityRow] {
		let theirs = genreSet(suggestion.genres)
		return library
			.map { SimilarityRow(title: $0, percent: percent(suggestion, genres: theirs, $0)) }
			.sorted { comesFirst($0, $1) }
	}

	/// The first of `rows`, found in one pass rather than by sorting the whole
	/// library — Discover names it under every card.
	static func closest(to suggestion: Suggestion, in library: [WatchedTitle]) -> SimilarityRow? {
		let theirs = genreSet(suggestion.genres)
		return library.lazy
			.map { SimilarityRow(title: $0, percent: percent(suggestion, genres: theirs, $0)) }
			.min { comesFirst($0, $1) }
	}

	/// The more alike first, then A–Z.
	private static func comesFirst(_ lhs: SimilarityRow, _ rhs: SimilarityRow) -> Bool {
		if lhs.percent != rhs.percent { return lhs.percent > rhs.percent }
		return lhs.title.title.localizedStandardCompare(rhs.title.title) == .orderedAscending
	}

	/// `percent`, with the suggestion's genres worked out once for the whole
	/// library rather than again for every title.
	private static func percent(_ suggestion: Suggestion, genres theirs: Set<String>, _ title: WatchedTitle) -> Int {
		let ours = libraryGenreSet(title.genre)
		let all = theirs.union(ours)
		let genres = all.isEmpty ? 0 : Double(theirs.intersection(ours).count) / Double(all.count)
		let seed: Double = suggestion.seeds.contains(title.id) ? 1 : 0
		let kind: Double = suggestion.kind == title.kind ? 1 : 0
		var era = 0.5
		if let theirYear = suggestion.year, let ourYear = title.year {
			era = max(0, 1 - Double(abs(theirYear - ourYear)) / 25)
		}
		return Int((100 * (0.55 * genres + 0.25 * seed + 0.12 * kind + 0.08 * era)).rounded())
	}

	/// A library title's comma-separated genres as `genreSet` has them. Titles
	/// share a handful of genre lists, so each list is worked out only once.
	private static func libraryGenreSet(_ genre: String) -> Set<String> {
		if let known = libraryGenres[genre] { return known }
		let set = genreSet(genre.split(separator: ",").map(String.init))
		libraryGenres[genre] = set
		return set
	}

	private static var libraryGenres: [String: Set<String>] = [:]
}
