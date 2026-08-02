//
//  CreditsLoader.swift
//  WatchList
//
//  The @MainActor half of the Cast and Similar tabs, mirroring TriviaLoader and
//  SimilarLoader: TMDbService does the I/O, this owns the mapping and the cache.
//
//  Nothing here is persisted. A tab is fetched the first time it is opened and
//  then held for the rest of the session, keyed per title / season / episode —
//  flipping between tabs, or back out and into a page, costs no requests.
//
//  This is unrelated to SimilarLoader, which powers the dock's Similar tab.
//

import Foundation

// MARK: - Display models

/// One person in a Cast tab. Built from whichever credits endpoint the page
/// uses, so the pages can share a single row.
struct CastEntry: Identifiable, Hashable {
	/// Why this person is called out. Mirrors the mock's ochre flag.
	enum Flag: Hashable {
		case none
		case newThisSeason
		case guestStar

		var label: String? {
			switch self {
			case .none:          return nil
			case .newThisSeason: return "New this season"
			case .guestStar:     return "Guest star"
			}
		}
	}

	let id: Int                 // TMDb person id
	let name: String
	let character: String
	let episodeCount: Int?
	let profileURL: String
	var flag: Flag = .none
}

/// An episode's "In this episode" payload: the two spec rows plus everyone who
/// appeared.
struct EpisodeCredits: Hashable {
	var directedBy: String = ""
	var writtenBy: String = ""
	var people: [CastEntry] = []

	var isEmpty: Bool { directedBy.isEmpty && writtenBy.isEmpty && people.isEmpty }
}

/// One row of a Similar tab. There is deliberately no match percentage —
/// `/tv/{id}/similar` doesn't return one, so the honest figures are TMDb's
/// vote average and the genres the two titles actually share.
struct SimilarEntry: Identifiable, Hashable {
	let id: Int                 // TMDb show id
	let title: String
	let year: String
	let voteAverage: Double
	let posterURL: String
	let sharedGenres: [String]
}

// MARK: - Loader

@MainActor
enum CreditsLoader {

	// MARK: Cache

	private struct SeasonKey: Hashable { let tvID: Int; let season: Int }
	private struct EpisodeKey: Hashable { let tvID: Int; let season: Int; let episode: Int }

	private static var seriesCastCache: [Int: [CastEntry]] = [:]
	private static var seasonCastCache: [SeasonKey: [CastEntry]] = [:]
	/// Just the person ids per season, which is all "new this season" needs.
	/// Reading seasons in order otherwise re-fetches season 1 every time.
	private static var seasonCastIDCache: [SeasonKey: [Int]] = [:]
	private static var episodeCache: [EpisodeKey: EpisodeCredits] = [:]
	private static var similarCache: [Int: [SimilarEntry]] = [:]
	/// The genre id -> name table, fetched at most once per session.
	private static var genreNames: [Int: String] = [:]

	// MARK: Cast

	/// Everyone in the series, most episodes first.
	static func seriesCast(tvID: Int) async -> [CastEntry] {
		if let cached = seriesCastCache[tvID] { return cached }
		guard let credits = try? await TMDbService.shared.aggregateCredits(tvID: tvID) else { return [] }
		let entries = castEntries(from: credits)
		seriesCastCache[tvID] = entries
		return entries
	}

	/// One season's cast, with anyone who didn't appear in an earlier season
	/// flagged. Season 1 flags nobody — everybody is new, so the flag would be
	/// noise rather than information.
	static func seasonCast(tvID: Int, season: Int) async -> [CastEntry] {
		let key = SeasonKey(tvID: tvID, season: season)
		if let cached = seasonCastCache[key] { return cached }

		guard let credits = try? await TMDbService.shared.seasonAggregateCredits(tvID: tvID, seasonNumber: season) else { return [] }
		seasonCastIDCache[key] = (credits.cast ?? []).map(\.id)

		// Earlier seasons only tell us who is *not* new, so a failure to fetch
		// one simply means we flag more conservatively — never wrongly.
		var earlier: Set<Int> = []
		if season > 1 {
			await withTaskGroup(of: [Int].self) { group in
				for previous in 1..<season {
					group.addTask { await castIDs(tvID: tvID, season: previous) }
				}
				for await ids in group { earlier.formUnion(ids) }
			}
		}

		let entries = castEntries(from: credits).map { entry -> CastEntry in
			guard season > 1, !earlier.contains(entry.id) else { return entry }
			var flagged = entry
			flagged.flag = .newThisSeason
			return flagged
		}
		seasonCastCache[key] = entries
		return entries
	}

	/// Who appeared in a season, ids only — the cheap half of `seasonCast`.
	private static func castIDs(tvID: Int, season: Int) async -> [Int] {
		let key = SeasonKey(tvID: tvID, season: season)
		if let cached = seasonCastIDCache[key] { return cached }
		guard let credits = try? await TMDbService.shared.seasonAggregateCredits(tvID: tvID, seasonNumber: season) else { return [] }
		let ids = (credits.cast ?? []).map(\.id)
		seasonCastIDCache[key] = ids
		return ids
	}

	/// One episode's crew pair and the people in it.
	static func episodeCredits(tvID: Int, season: Int, episode: Int) async -> EpisodeCredits {
		let key = EpisodeKey(tvID: tvID, season: season, episode: episode)
		if let cached = episodeCache[key] { return cached }
		guard let credits = try? await TMDbService.shared.episodeCredits(tvID: tvID, season: season, episode: episode) else {
			return EpisodeCredits()
		}
		let built = episodeCredits(from: credits)
		episodeCache[key] = built
		return built
	}

	// MARK: Similar

	/// Titles TMDb considers similar, annotated with the genres they share with
	/// `parentGenres` (the comma-joined string stored on the Show).
	static func similar(tvID: Int, parentGenres: String) async -> [SimilarEntry] {
		if let cached = similarCache[tvID] { return cached }

		guard let results = try? await TMDbService.shared.similar(tvID: tvID) else { return [] }

		if genreNames.isEmpty, let genres = try? await TMDbService.shared.tvGenres() {
			genreNames = Dictionary(uniqueKeysWithValues: genres.compactMap { genre in
				genre.name.map { (genre.id, $0) }
			})
		}

		let entries = similarEntries(from: results, parentGenres: parentGenres, genreNames: genreNames)
		similarCache[tvID] = entries
		return entries
	}

	// MARK: Mapping

	/// Aggregate credits -> rows, sorted by episode count descending. Ties keep
	/// TMDb's billing order, so the leads stay above the bit parts.
	static func castEntries(from credits: TMDbAggregateCredits) -> [CastEntry] {
		let people = (credits.cast ?? []).enumerated().map { index, member in
			(index, CastEntry(id: member.id,
			                  name: member.name ?? "",
			                  character: characterName(member.roles),
			                  episodeCount: member.total_episode_count,
			                  profileURL: TMDbConfig.profile(member.profile_path)))
		}
		return people
			.sorted { lhs, rhs in
				let left = lhs.1.episodeCount ?? 0
				let right = rhs.1.episodeCount ?? 0
				return left == right ? lhs.0 < rhs.0 : left > right
			}
			.map(\.1)
	}

	/// Episode credits -> the director / writer pair plus a de-duplicated cast
	/// list with guest stars flagged. Series regulars come first and plain,
	/// exactly as the mock draws them.
	static func episodeCredits(from credits: TMDbCredits) -> EpisodeCredits {
		var built = EpisodeCredits()
		built.directedBy = names(in: credits.crew, jobs: ["Director"])
		built.writtenBy = names(in: credits.crew, jobs: ["Writer", "Screenplay", "Teleplay", "Story"])

		var seen: Set<Int> = []
		var people: [CastEntry] = []
		func append(_ members: [TMDbCastMember], flag: CastEntry.Flag) {
			for member in members where seen.insert(member.id).inserted {
				people.append(CastEntry(id: member.id,
				                        name: member.name ?? "",
				                        character: member.character ?? "",
				                        episodeCount: nil,
				                        profileURL: TMDbConfig.profile(member.profile_path),
				                        flag: flag))
			}
		}
		append(credits.cast ?? [], flag: .none)
		append(credits.guest_stars ?? [], flag: .guestStar)

		built.people = people
		return built
	}

	/// Similar results -> rows, each annotated with the genres it shares with
	/// the title you came from.
	static func similarEntries(from results: [TMDbSimilarTV],
	                           parentGenres: String,
	                           genreNames: [Int: String]) -> [SimilarEntry] {
		let parent = splitGenres(parentGenres)
		return results.map { item in
			let own = (item.genre_ids ?? []).compactMap { genreNames[$0] }
			// Keep the parent's own ordering, so the line reads the same way the
			// header above it does.
			let shared = parent.filter { genre in
				own.contains { $0.compare(genre, options: .caseInsensitive) == .orderedSame }
			}
			return SimilarEntry(id: item.id,
			                    title: item.name ?? "",
			                    year: String((item.first_air_date ?? "").prefix(4)),
			                    voteAverage: item.vote_average ?? 0,
			                    posterURL: TMDbConfig.poster(item.poster_path),
			                    sharedGenres: shared)
		}
	}

	// MARK: Helpers

	/// A person's characters, joined when they played more than one.
	private static func characterName(_ roles: [TMDbCreditRole]?) -> String {
		(roles ?? [])
			.compactMap { $0.character }
			.filter { !$0.isEmpty }
			.joined(separator: ", ")
	}

	private static func names(in crew: [TMDbCrewMember]?, jobs: [String]) -> String {
		var seen: Set<String> = []
		return (crew ?? [])
			.filter { member in jobs.contains { $0 == member.job } }
			.compactMap { $0.name }
			.filter { !$0.isEmpty && seen.insert($0).inserted }
			.joined(separator: ", ")
	}

	/// "Comedy, Drama" -> ["Comedy", "Drama"].
	static func splitGenres(_ genres: String) -> [String] {
		genres
			.components(separatedBy: ",")
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
	}
}
