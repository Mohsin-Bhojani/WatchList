//
//  SimilarLoader.swift
//  WatchList
//
//  The @MainActor half of the Similar tab, mirroring TriviaLoader: the service
//  does the I/O, this writes SwiftData models and owns the caching policy.
//
//  Refresh only when the ratings behind the batch actually changed (or it's a
//  week old, or you pulled to refresh) — otherwise every time the sheet opened
//  would spend a Claude call to re-derive the same answer.
//

import CryptoKit
import Foundation
import SwiftData

@MainActor
enum SimilarLoader {

	/// How many suggestions to ask for.
	static let batchSize = 12
	/// Even with unchanged ratings, re-ask after this long.
	static let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60

	enum Outcome {
		case fresh(Int)          // n new suggestions
		case cached              // existing batch still good, no call made
		case stale(String)       // showing old suggestions; why the refresh failed
		case needsRatings        // nothing rated Perfection / Go For It yet
	}

	// MARK: Taste profile

	struct Profile {
		let dto: TasteProfileDTO
		let exclude: [String]
		let fingerprint: String
		let lovedCount: Int
		let likedCount: Int
	}

	/// Caps keep the prompt to a few hundred tokens. Synopses are deliberately
	/// left out — they're the biggest token sink and Claude already knows these
	/// titles; the ratings are the only part it can't know.
	static func buildProfile(shows: [Show], films: [Film]) -> Profile {
		func title(_ show: Show) -> (TasteTitleDTO, Rating?, String) {
			(TasteTitleDTO(title: show.title,
			               year: show.firstAirYear,
			               kind: "show",
			               genre: shortGenre(show.genre)),
			 show.rating,
			 "show:\(show.tmdbID.map(String.init) ?? show.title)")
		}
		func title(_ film: Film) -> (TasteTitleDTO, Rating?, String) {
			(TasteTitleDTO(title: film.title,
			               year: film.year,
			               kind: "film",
			               genre: shortGenre(film.genre)),
			 film.rating,
			 "film:\(film.tmdbID.map(String.init) ?? film.title)")
		}

		let entries = shows.map(title) + films.map(title)

		func bucket(_ ratings: Set<Rating>, limit: Int, keepGenre: Bool) -> [TasteTitleDTO] {
			entries
				.filter { $0.1.map(ratings.contains) ?? false }
				.prefix(limit)
				.map { keepGenre ? $0.0 : TasteTitleDTO(title: $0.0.title, year: $0.0.year, kind: $0.0.kind, genre: nil) }
		}

		let perfection = bucket([.perfection], limit: 25, keepGenre: true)
		let goForIt    = bucket([.goForIt], limit: 25, keepGenre: true)
		let avoid      = bucket([.timepass, .skip], limit: 15, keepGenre: false)

		let exclude = Array((shows.map(\.title) + films.map(\.title))
			.filter { !$0.isEmpty }
			.prefix(200))

		// Only rated titles feed the fingerprint — adding an unrated title to
		// the library shouldn't invalidate a batch it had no part in.
		let tokens = entries
			.compactMap { entry -> String? in
				guard let rating = entry.1 else { return nil }
				return "\(entry.2):\(rating.rawValue)"
			}
			.sorted()

		return Profile(
			dto: TasteProfileDTO(perfection: perfection, goForIt: goForIt, avoid: avoid),
			exclude: exclude,
			fingerprint: fingerprint(of: tokens),
			lovedCount: perfection.count,
			likedCount: goForIt.count
		)
	}

	/// "Action, Drama, Sci-Fi" -> "Action/Drama". The raw TMDb field is longer
	/// than it needs to be for a taste signal.
	private static func shortGenre(_ genre: String) -> String? {
		let tokens = genre
			.components(separatedBy: ",")
			.map { $0.trimmingCharacters(in: .whitespaces) }
			.filter { !$0.isEmpty }
			.prefix(2)
		return tokens.isEmpty ? nil : tokens.joined(separator: "/")
	}

	/// SHA256, not `hashValue` — Swift's hashing is seeded per process, so a
	/// hashValue-based fingerprint would differ on every launch and the cache
	/// would refresh every single time.
	private static func fingerprint(of tokens: [String]) -> String {
		let joined = tokens.joined(separator: "|")
		let digest = SHA256.hash(data: Data(joined.utf8))
		return digest.map { String(format: "%02x", $0) }.joined()
	}

	// MARK: Refresh

	static func refreshIfNeeded(shows: [Show],
	                            films: [Film],
	                            cached: [Suggestion],
	                            into context: ModelContext,
	                            force: Bool = false) async -> Outcome {
		let profile = buildProfile(shows: shows, films: films)

		guard profile.lovedCount + profile.likedCount > 0 else { return .needsRatings }

		if !force, !cached.isEmpty, isCurrent(cached, fingerprint: profile.fingerprint) {
			return .cached
		}

		// Probe first: a sleeping Mac should drop us onto the cache in ~2s
		// rather than after the full request timeout.
		guard await SuggestionService.shared.health() else {
			return .stale(SuggestionError.unreachable.localizedDescription)
		}

		let dtos: [SuggestionDTO]
		do {
			dtos = try await SuggestionService.shared.suggest(
				profile: profile.dto,
				exclude: profile.exclude,
				count: batchSize
			)
		} catch {
			// Never destroy a usable cache because a refresh failed.
			return .stale((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
		}

		guard !dtos.isEmpty else {
			return .stale("Your Mac returned no suggestions.")
		}

		// Swap the batch in one pass so the list never renders half-empty.
		for old in cached { context.delete(old) }
		let inserted = dtos.enumerated().map { index, dto -> Suggestion in
			let suggestion = Suggestion(title: dto.title,
			                            year: dto.year,
			                            kind: dto.mediaKind,
			                            reason: dto.reason,
			                            rank: index,
			                            profileFingerprint: profile.fingerprint)
			context.insert(suggestion)
			return suggestion
		}

		// Resolve after inserting, so posters fill in behind an already-visible
		// list rather than holding it back. Sequential is fine for 12.
		for suggestion in inserted {
			await resolve(suggestion)
		}

		return .fresh(inserted.count)
	}

	private static func isCurrent(_ cached: [Suggestion], fingerprint: String) -> Bool {
		guard let newest = cached.map(\.generatedAt).max() else { return false }
		guard Date().timeIntervalSince(newest) < maxCacheAge else { return false }
		return cached.allSatisfy { $0.profileFingerprint == fingerprint }
	}

	// MARK: TMDb resolution

	/// Turns a bare title into something addable: a tmdbID and a poster.
	/// A definitive miss still sets `resolved`, so a title Claude invented
	/// isn't re-queried on every appearance — it just renders without a button.
	static func resolve(_ suggestion: Suggestion) async {
		guard !suggestion.resolved, TMDbConfig.isConfigured else { return }

		guard let results = try? await TMDbService.shared.multiSearch(query: suggestion.title) else {
			// Network blip rather than a definitive miss — leave it unresolved
			// so a later refresh can try again.
			return
		}

		let wanted = suggestion.kind == .show ? "tv" : "movie"
		let candidates = results.filter { $0.media_type == wanted }

		let match = candidates.first { exactTitle($0, suggestion.title) && sameYear($0, suggestion.year) }
			?? candidates.first { exactTitle($0, suggestion.title) }
			?? candidates.first { sameYear($0, suggestion.year) }
			?? candidates.first

		if let match {
			suggestion.tmdbID = match.id
			suggestion.posterURL = TMDbConfig.poster(match.poster_path)
		}
		suggestion.resolved = true
	}

	private static func exactTitle(_ item: TMDbSearchItem, _ title: String) -> Bool {
		item.displayTitle.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
	}

	private static func sameYear(_ item: TMDbSearchItem, _ year: String) -> Bool {
		guard !year.isEmpty else { return false }
		let raw = item.release_date ?? item.first_air_date ?? ""
		return String(raw.prefix(4)) == year
	}
}
