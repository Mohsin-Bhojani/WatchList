//
//  DiscoverQueue.swift
//  WatchList
//
//  What Discover offers and in what order, compiled into both the iPhone app and
//  the watch app so the two deal suggestions the same way:
//    - the queue: TMDb's recommendations for each seed in order (its similar
//      titles when it has none), each once, leaving out what's in the library or
//      turned down, and putting titles put off for later at the back
//    - the deal: the card that's up and how many are ready, for the filter and
//      the rotation between titles
//    - the filter: a type, genres, and — More like — the one library title
//      suggestions come from
//    - when to move on to the next library title: after 5 of its suggestions
//      are decided, unless 3 or more of those were added, which earns it 5 more
//    - what a swipe on the card decides
//  DiscoverLoader fetches the suggestions a few seeds at a time, keeping the
//  titles coming up next fetched before Discover gets to them.
//
//  Which library titles are seeds, and in what order, is the iPhone's to work
//  out from its models (WatchList/iPhone/DiscoverFeed.swift); the watch is sent
//  them.
//

import Foundation

/// A title TMDb suggests, with what its card and the comparisons need.
struct Suggestion: Identifiable, Equatable {
	let kind: MediaKind
	let tmdbID: Int
	let title: String
	let year: Int?
	/// TMDb's poster at list size.
	let posterURL: String
	/// TMDb's average score out of 10; nil before anyone has voted.
	let averageScore: Double?
	let genres: [String]
	/// The synopsis; empty when TMDb has none.
	var overview = ""
	/// The library titles it was suggested from, in seed order.
	var seeds: [UUID] = []

	/// Kind and TMDb id, as MediaKind keys a title.
	var id: String { kind.key(tmdbID: tmdbID) }

	var kindLabel: String { kind == .show ? "TV Show" : "Film" }
	var placeholder: String { kind == .show ? "tv" : "film" }

	/// The poster at the size the card draws it.
	var largePosterURL: String { posterURL.replacingOccurrences(of: "/w500/", with: "/w780/") }
}

/// A title from TMDb's `/recommendations` or `/similar`, which send the same
/// shape: a show fills `name` and `first_air_date`, a film `title` and
/// `release_date`.
struct TMDbSuggestedTitle: Decodable {
	let id: Int
	let name: String?
	let title: String?
	let first_air_date: String?
	let release_date: String?
	let overview: String?
	let vote_average: Double?
	let poster_path: String?
	let genre_ids: [Int]?
}

struct TMDbSuggestedPage: Decodable {
	let results: [TMDbSuggestedTitle]
}

extension Suggestion {
	/// A show or film TMDb suggests, or nil when it has no poster to show.
	init?(_ item: TMDbSuggestedTitle, kind: MediaKind, genreNames: [Int: String]) {
		guard let poster = item.poster_path, !poster.isEmpty else { return nil }
		let date = kind == .show ? item.first_air_date : item.release_date
		self.init(kind: kind, tmdbID: item.id,
		          title: (kind == .show ? item.name : item.title) ?? "Untitled",
		          year: Int((date ?? "").prefix(4)),
		          posterURL: TMDbConfig.poster(poster),
		          averageScore: item.vote_average.flatMap { $0 > 0 ? $0 : nil },
		          genres: (item.genre_ids ?? []).compactMap { genreNames[$0] },
		          overview: (item.overview ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
	}
}

/// A library title Discover's suggestions come from: on the iPhone a show or film
/// in the library, on the watch the same title as the iPhone sent it.
protocol SuggestionSeed {
	var id: UUID { get }
	var kind: MediaKind { get }
	/// Nil for a title added by hand, which TMDb doesn't know.
	var tmdbID: Int? { get }
}

/// What Discover deals from, for a filter and where the rotation has got to.
struct DiscoverDeal<Seed: SuggestionSeed> {
	/// The seeds of the filter's type: a seed is suggested titles of its own kind.
	let seeds: [Seed]
	/// More like's title, while it's still one of `seeds`.
	let picked: Seed?
	/// What suggestions are drawn from: More like's title, or every seed.
	let drawingSeeds: [Seed]
	/// Their ids in the order they're drawn from, titles moved on from at the back.
	let seedOrder: [UUID]
	/// The suggestions in the order they're offered, fitting the filter.
	let queue: [Suggestion]
	/// The card up now; nil while the next title's suggestions are on their way.
	let current: Suggestion?
	/// The titles cards are dealt from: those not moved on from, or every one once
	/// all of them have been.
	let dealing: [UUID]
	/// Not to be dealt: excluded, or put off.
	let skipped: Set<String>
	/// How many cards are ready to deal, up to `DiscoverFeed.readyAhead`.
	let ready: Int

	/// `allSeeds` in seed order; `excluded` the titles in the library, turned down
	/// or on their way in; `putOff` when each title put off for later was.
	init(seeds allSeeds: [Seed], filter: DiscoverFilter, rotation: DiscoverRotation,
	     similar: [UUID: [Suggestion]], fetched: Set<UUID>, excluded: Set<String>, putOff: [String: Date]) {
		seeds = allSeeds.filter { filter.kind.includes($0.kind) }
		// More like narrows Discover to the one title's suggestions.
		picked = seeds.first { $0.id == filter.seed }
		drawingSeeds = picked.map { [$0] } ?? seeds
		// Titles moved on from go to the back; suggestions come from the rest first.
		seedOrder = rotation.order(drawingSeeds.map(\.id))
		let drawing = seedOrder.filter { !rotation.passed.contains($0) }
		queue = DiscoverFeed.queue(seedOrder: seedOrder, similar: similar, excluding: excluded, putOff: putOff)
			.filter(filter.matches)
		// Just moved on, with the next title's suggestions not in yet: wait for
		// them rather than show the passed title's again.
		let waitingForNext = queue.first.flatMap(\.seeds.first).map { rotation.passed.contains($0) } == true
			&& drawing.contains { !fetched.contains($0) }
		current = waitingForNext ? nil : queue.first
		// Cards ready to come from the titles being drawn from — every title, once
		// all of them have been passed.
		dealing = drawing.isEmpty ? seedOrder : drawing
		skipped = excluded.union(putOff.keys)
		ready = DiscoverFeed.ready(seedOrder: dealing, similar: similar, excluding: skipped,
		                           matching: filter, rotation: rotation, wanted: DiscoverFeed.readyAhead)
	}

	/// The seeds to fetch suggestions for, in the order they're drawn from.
	var ordered: [Seed] {
		let byID = Dictionary(drawingSeeds.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
		return seedOrder.compactMap { byID[$0] }
	}
}

enum DiscoverFeed {
	/// How many cards to have ready to deal — enough to reach past the title in
	/// use, so the next one's suggestions are in before Discover moves on.
	static let readyAhead = 8

	/// The suggestions in the order they're offered: each seed's similar titles
	/// in `seedOrder`, TMDb's order within a seed, each title once with every
	/// seed it came from. Titles in `excluded` are left out; titles in `putOff`
	/// go after the rest, the one put off longest ago first.
	static func queue(seedOrder: [UUID], similar: [UUID: [Suggestion]],
	                  excluding excluded: Set<String>, putOff: [String: Date]) -> [Suggestion] {
		var order: [String] = []
		var byID: [String: Suggestion] = [:]
		for seed in seedOrder {
			for suggestion in similar[seed] ?? [] where !excluded.contains(suggestion.id) {
				if var known = byID[suggestion.id] {
					if !known.seeds.contains(seed) { known.seeds.append(seed) }
					byID[suggestion.id] = known
				} else {
					var fresh = suggestion
					fresh.seeds = [seed]
					byID[suggestion.id] = fresh
					order.append(suggestion.id)
				}
			}
		}
		let fresh = order.filter { putOff[$0] == nil }
		let later = order.compactMap { id in putOff[id].map { (id, $0) } }
			.sorted { $0.1 < $1.1 }
			.map(\.0)
		return (fresh + later).compactMap { byID[$0] }
	}

	/// How many cards Discover can deal from the seeds in `seedOrder` before it
	/// has to wait on TMDb, counting no further than `wanted`: each seed's
	/// suggestions outside `excluded` that fit `filter`, each once, up to the room
	/// `rotation` leaves that seed. A seed not fetched yet has none.
	static func ready(seedOrder: [UUID], similar: [UUID: [Suggestion]], excluding excluded: Set<String>,
	                  matching filter: DiscoverFilter, rotation: DiscoverRotation, wanted: Int) -> Int {
		var counted = Set<String>()
		for seed in seedOrder where counted.count < wanted {
			let room = rotation.room(for: seed)
			var fromSeed = 0
			for suggestion in similar[seed] ?? [] where fromSeed < room {
				guard !excluded.contains(suggestion.id), filter.matches(suggestion),
				      counted.insert(suggestion.id).inserted else { continue }
				fromSeed += 1
			}
		}
		return min(counted.count, wanted)
	}
}

/// What Discover's filter narrows its suggestions to: TV shows, films or both,
/// any of some genres, and — More like — the one library title they come from.
struct DiscoverFilter: Equatable {
	var kind: BrowseKind = .all
	var genres: Set<String> = []
	/// The library title suggestions come from; nil for every title in turn.
	var seed: UUID?

	var isDefault: Bool { kind == .all && genres.isEmpty && seed == nil }

	/// The line under Discover's header while anything's narrowed: the title
	/// suggestions come from, the type, then the genres — "Severance · Drama,
	/// Mystery". `seedTitle` is the picked title's name, when it's still there.
	func summary(seedTitle: String?) -> String? {
		var parts: [String] = []
		if let seedTitle { parts.append(seedTitle) }
		if kind != .all { parts.append(kind.title) }
		switch genres.count {
		case 0:    break
		case 1, 2: parts.append(genres.sorted().joined(separator: ", "))
		default:   parts.append("\(genres.count) genres")
		}
		return parts.isEmpty ? nil : parts.joined(separator: " · ")
	}

	/// Whether a suggestion fits: its kind, and — with genres picked — at least
	/// one of them. TV and film genre names are lined up, so "Action" finds a
	/// show in "Action & Adventure".
	func matches(_ suggestion: Suggestion) -> Bool {
		guard kind.includes(suggestion.kind) else { return false }
		guard !genres.isEmpty else { return true }
		return !Similarity.genreSet(suggestion.genres).isDisjoint(with: Similarity.genreSet(Array(genres)))
	}

	/// The genre tiles for a type: TMDb's TV genres, its film genres or both,
	/// once each and A–Z.
	static func genreOptions(for kind: BrowseKind, tv: [String], movie: [String]) -> [String] {
		BrowseFilter.genres(in: (kind.includesShows ? tv : []) + (kind.includesFilms ? movie : []))
	}
}

/// Which library title Discover's suggestions come from, and when to move on.
/// A title gets 5 of its suggestions decided at a time. With 3 or more of those
/// added it gets 5 more; otherwise the next title in the library takes over and
/// the one passed goes to the back of the line — so Discover goes round every
/// title, then starts round again.
struct DiscoverRotation: Equatable {
	/// How many of a title's suggestions are decided before it's weighed up.
	static let batchSize = 5
	/// How many of those have to be added for it to get another batch.
	static let addsToStay = 3

	/// The title whose batch is running.
	private(set) var reference: UUID?
	/// Decisions in its batch so far, and how many of them were adds.
	private(set) var decided = 0
	private(set) var added = 0
	/// Titles moved on from, the longest ago first.
	private(set) var passed: [UUID] = []

	/// Counts a decision on a suggestion taken from `seed`. True when it's the
	/// one that moves Discover on to the next title.
	@discardableResult
	mutating func record(_ decision: CardDecision, from seed: UUID) -> Bool {
		if seed != reference {
			// Come round to again, it's in use rather than waiting at the back.
			passed.removeAll { $0 == seed }
			reference = seed
			decided = 0
			added = 0
		}
		decided += 1
		if decision == .add { added += 1 }
		guard decided >= Self.batchSize else { return false }
		let earnedMore = added >= Self.addsToStay
		decided = 0
		added = 0
		if earnedMore { return false }
		passed.append(seed)
		reference = nil
		return true
	}

	/// How many more of `seed`'s suggestions come before it's weighed up: what's
	/// left of its batch while it's running, or a whole one.
	func room(for seed: UUID) -> Int {
		seed == reference ? Self.batchSize - decided : Self.batchSize
	}

	/// The seeds in the order suggestions are drawn from them: the one whose
	/// batch is running, then those not moved on from, as they come, then the
	/// ones passed, the longest ago first. The running title stays in front, so
	/// a title added from its suggestions — a seed itself — waits its turn.
	func order(_ seeds: [UUID]) -> [UUID] {
		let skipped = Set(passed)
		let present = Set(seeds)
		let running = reference.flatMap { present.contains($0) ? [$0] : nil } ?? []
		return running + seeds.filter { $0 != reference && !skipped.contains($0) }
			+ passed.filter { present.contains($0) }
	}
}

// MARK: - Genres

enum Similarity {
	/// Genre names made comparable across TV and film: lower-cased, TMDb's joint
	/// TV genres split ("Sci-Fi & Fantasy" is science fiction and fantasy), and
	/// TV-only names given their film equivalents.
	static func genreSet(_ names: [String]) -> Set<String> {
		var set = Set<String>()
		for name in names {
			for part in name.split(separator: "&") {
				let genre = part.trimmingCharacters(in: .whitespaces).lowercased()
				guard !genre.isEmpty else { continue }
				set.insert(filmNames[genre] ?? genre)
			}
		}
		return set
	}

	private static let filmNames = ["sci-fi": "science fiction", "kids": "family"]
}

// MARK: - Deciding

/// A decision on the suggestion on screen, made by swiping its card: right adds
/// it, left turns it down, up keeps it for later.
enum CardDecision: Equatable {
	case add, notInterested, later

	/// How far a card has to go — or be flung — to decide.
	static let threshold: CGFloat = 120

	var symbol: String {
		switch self {
		case .add:           return "checkmark"
		case .notInterested: return "xmark"
		case .later:         return "questionmark"
		}
	}

	/// Its name for VoiceOver, which offers the three as actions on the card.
	var label: String {
		switch self {
		case .add:           return "Add to To Watch"
		case .notInterested: return "Not interested"
		case .later:         return "Suggest later"
		}
	}

	/// What the card says while it's swiped this way.
	var swipeLabel: String {
		switch self {
		case .add:           return "Add"
		case .notInterested: return "Not interested"
		case .later:         return "Later"
		}
	}

	/// What a swipe decides as the finger lifts, or nil to spring the card back.
	/// Where it was heading counts, so a flick will do, but the card has to have
	/// moved that way too: thrown back the other way, it decides nothing.
	/// Swiping down decides nothing either. The card has to have moved a quarter of
	/// `threshold`; the watch's smaller card passes a shorter one.
	static func forSwipe(translation: CGSize, predictedEnd: CGSize,
	                     threshold: CGFloat = CardDecision.threshold) -> CardDecision? {
		if abs(predictedEnd.width) >= abs(predictedEnd.height) {
			guard abs(predictedEnd.width) >= threshold, abs(translation.width) >= threshold / 4,
			      (predictedEnd.width > 0) == (translation.width > 0) else { return nil }
			return predictedEnd.width > 0 ? .add : .notInterested
		}
		guard predictedEnd.height <= -threshold, translation.height <= -threshold / 4 else { return nil }
		return .later
	}

	/// Which decision a card being dragged leans towards, and how far it's got,
	/// from 0 to 1 at the threshold.
	static func leaning(_ translation: CGSize,
	                    threshold: CGFloat = CardDecision.threshold) -> (decision: CardDecision, progress: CGFloat)? {
		if abs(translation.width) >= abs(translation.height), translation.width != 0 {
			return (translation.width > 0 ? .add : .notInterested, min(abs(translation.width) / threshold, 1))
		}
		guard translation.height < 0 else { return nil }
		return (.later, min(-translation.height / threshold, 1))
	}

	/// Where the card flies off to from `start`: off either side, or off the top.
	func flyOff(from start: CGSize) -> CGSize {
		switch self {
		case .add:           return CGSize(width: 900, height: start.height + 60)
		case .notInterested: return CGSize(width: -900, height: start.height + 60)
		case .later:         return CGSize(width: start.width, height: -1400)
		}
	}
}

// MARK: - Loading

/// Fetches TMDb's suggestions for Discover's seeds and holds them for the
/// session.
@Observable
final class DiscoverLoader {
	/// Each fetched seed's suggestions, in TMDb's order.
	private(set) var similar: [UUID: [Suggestion]] = [:]
	/// Seeds looked up, whether or not TMDb had anything for them.
	private(set) var fetched: Set<UUID> = []
	private(set) var isLoading = false
	/// TMDb's genre names, TV's and film's, for the filter's tiles.
	private(set) var tvGenres: [String] = []
	private(set) var movieGenres: [String] = []
	private var failedSeeds: Set<UUID> = []

	/// Every lookup so far has failed — offline, most likely.
	var failed: Bool { !failedSeeds.isEmpty && similar.isEmpty }

	private static var genreNames: (tv: [Int: String], movie: [Int: String])?

	/// Looks up the seeds not yet fetched, three at a time and in order, until
	/// `wanted` cards are ready to deal from the seeds in `counted` — the ones
	/// Discover is drawing from — or no seeds are left. A seed counts only as far
	/// as its turn in `rotation` goes, so the titles after the one in use are in
	/// before Discover moves on to them.
	func fill<Seed: SuggestionSeed>(from seeds: [Seed], wanted: Int, excluding excluded: Set<String>,
	                                matching filter: DiscoverFilter, counting counted: [UUID],
	                                rotation: DiscoverRotation) async {
		guard !isLoading, TMDbConfig.isConfigured else { return }
		// Plain values read off the models here, so none go into the lookups.
		var pending = seeds.compactMap { seed -> (id: UUID, kind: MediaKind, tmdbID: Int)? in
			guard !fetched.contains(seed.id), let tmdbID = seed.tmdbID else { return nil }
			return (seed.id, seed.kind, tmdbID)
		}
		func readyCount() -> Int {
			DiscoverFeed.ready(seedOrder: counted, similar: similar, excluding: excluded, matching: filter,
			                   rotation: rotation, wanted: wanted)
		}
		guard !pending.isEmpty, readyCount() < wanted else { return }

		isLoading = true
		defer { isLoading = false }
		let names = await Self.loadGenreNames()
		while !pending.isEmpty, readyCount() < wanted {
			let batch = Array(pending.prefix(3))
			pending.removeFirst(batch.count)
			let results = await withTaskGroup(of: (UUID, [Suggestion]?).self) { group in
				for seed in batch {
					group.addTask { (seed.id, await Self.lookUp(seed.kind, seed.tmdbID, names: names)) }
				}
				var collected: [(UUID, [Suggestion]?)] = []
				for await result in group { collected.append(result) }
				return collected
			}
			for (id, suggestions) in results {
				fetched.insert(id)
				if let suggestions { similar[id] = suggestions } else { failedSeeds.insert(id) }
			}
		}
	}

	/// Lets the seeds whose lookups failed be tried again.
	func retry() {
		fetched.subtract(failedSeeds)
		failedSeeds.removeAll()
	}

	/// Fetches TMDb's genre names for the filter's tiles, once a session.
	func loadGenres() async {
		guard tvGenres.isEmpty, TMDbConfig.isConfigured else { return }
		let names = await Self.loadGenreNames()
		tvGenres = Array(names.tv.values)
		movieGenres = Array(names.movie.values)
	}

	/// A seed's suggestions: TMDb's recommendations — what people who liked it
	/// went on to watch, much closer than `/similar`'s keyword matches — or its
	/// similar titles when it has no recommendations.
	private static func lookUp(_ kind: MediaKind, _ tmdbID: Int,
	                           names: (tv: [Int: String], movie: [Int: String])) async -> [Suggestion]? {
		guard let titles = try? await TMDbSuggestions.titles(kind, tmdbID) else { return nil }
		let table = kind == .show ? names.tv : names.movie
		return titles.compactMap { Suggestion($0, kind: kind, genreNames: table) }
	}

	/// TMDb's genre names by id. The suggestion lists only send ids, and TV and
	/// film number their genres separately.
	private static func loadGenreNames() async -> (tv: [Int: String], movie: [Int: String]) {
		if let genreNames { return genreNames }
		func table(_ genres: [TMDbGenre]?) -> [Int: String] {
			Dictionary((genres ?? []).compactMap { genre in genre.name.map { (genre.id, $0) } },
			           uniquingKeysWith: { first, _ in first })
		}
		let loaded = (tv: table(try? await TMDbService.shared.tvGenres()),
		              movie: table(try? await TMDbService.shared.movieGenres()))
		// Kept only once both are in, so a failed lookup is tried again.
		if !loaded.tv.isEmpty && !loaded.movie.isEmpty { genreNames = loaded }
		return loaded
	}
}

/// TMDb's suggestions for a show or film. TMDbService keeps its request helper
/// private, and its similar-title types leave the synopsis out, so the requests
/// are built here the same way.
private enum TMDbSuggestions {
	/// Its recommendations, or its similar titles when it has none.
	static func titles(_ kind: MediaKind, _ id: Int) async throws -> [TMDbSuggestedTitle] {
		let base = kind == .show ? "/tv/\(id)" : "/movie/\(id)"
		let recommended: TMDbSuggestedPage = try await get(base + "/recommendations")
		if !recommended.results.isEmpty { return recommended.results }
		let similar: TMDbSuggestedPage = try await get(base + "/similar")
		return similar.results
	}

	private static func get<T: Decodable>(_ path: String) async throws -> T {
		guard TMDbConfig.isConfigured else { throw TMDbError.notConfigured }
		var components = URLComponents(string: TMDbConfig.apiBase + path)
		components?.queryItems = [URLQueryItem(name: "api_key", value: TMDbConfig.apiKey),
		                          URLQueryItem(name: "language", value: "en-US")]
		guard let url = components?.url else { throw TMDbError.badURL }
		let (data, response) = try await URLSession.shared.data(from: url)
		let status = (response as? HTTPURLResponse)?.statusCode ?? -1
		guard (200...299).contains(status) else { throw TMDbError.http(status) }
		do {
			return try JSONDecoder().decode(T.self, from: data)
		} catch {
			throw TMDbError.decoding
		}
	}
}
