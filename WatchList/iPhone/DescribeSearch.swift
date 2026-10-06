//
//  DescribeSearch.swift
//  WatchList
//
//  Describe, in Discover's filter: say what you're in the mood for — "something
//  romantic that doesn't have a sad ending" — and the matches come back as the
//  usual swipe cards.
//    - DescribedQuery: what a sentence comes to — genres, genres to avoid,
//      keywords, a type and how it should end
//    - DescribeInterpreter: Apple's on-device model reads the sentence; where
//      it isn't available, a plain word list does, so Describe still works
//    - DescribeSession: looks the query up on TMDb, ranks what comes back by
//      the library's taste and holds it for Discover to deal from
//  The sentence never leaves the phone: only the genres and keywords it comes
//  to are sent to TMDb.
//

import Foundation
import FoundationModels

/// How a described title should end.
enum EndingFeel: String, CaseIterable {
	case happy, bittersweet, sad, open
}

struct DescribedQuery: Equatable {
	/// TMDb genre names to include and to leave out.
	var genres: [String] = []
	var avoidGenres: [String] = []
	/// Words for TMDb's keywords, such as "happy ending".
	var keywords: [String] = []
	/// Nil for either.
	var kind: MediaKind?
	var ending: EndingFeel?

	/// "Romance · happy ending · not Horror", for under the card and the filter.
	var summary: String {
		var parts = genres
		if let ending { parts.append("\(ending.rawValue) ending") }
		parts += avoidGenres.map { "not \($0)" }
		if parts.isEmpty { parts = keywords }
		return parts.joined(separator: " · ")
	}

	var isEmpty: Bool { genres.isEmpty && avoidGenres.isEmpty && keywords.isEmpty && ending == nil }
}

// MARK: - Reading the sentence

enum DescribeInterpreter {
	/// Whether Apple's on-device model can read the sentence on this device.
	static var onDeviceAvailable: Bool {
		if case .available = SystemLanguageModel.default.availability { return true }
		return false
	}

	/// What the sentence comes to, and whether the on-device model read it.
	/// `genreNames` are TMDb's, which the query's genres have to come from.
	static func interpret(_ text: String, genreNames: [String]) async -> (query: DescribedQuery, usedModel: Bool) {
		if onDeviceAvailable, let query = try? await onDevice(text, genreNames: genreNames), !query.isEmpty {
			return (query, true)
		}
		return (WordListInterpreter.interpret(text, genreNames: genreNames), false)
	}

	@Generable
	struct Reading {
		@Guide(description: "Up to three genres the person wants, each copied exactly from the allowed list. Empty if none is clear.")
		var genres: [String]
		@Guide(description: "Genres the person doesn't want, each copied exactly from the allowed list.")
		var avoidGenres: [String]
		@Guide(description: "Up to three short keywords that describe the mood or theme, such as 'feel-good' or 'time travel'.")
		var keywords: [String]
		@Guide(description: "Either 'film', 'show' or 'either'.")
		var kind: String
		@Guide(description: "How the person wants it to end: 'happy', 'bittersweet', 'sad', 'open' or 'any'.")
		var ending: String
	}

	private static func onDevice(_ text: String, genreNames: [String]) async throws -> DescribedQuery {
		let session = LanguageModelSession(instructions: """
			You turn a description of what someone wants to watch into search terms. \
			Allowed genres: \(genreNames.sorted().joined(separator: ", ")). \
			Only use those exact genre names. "No sad ending" means the ending is happy.
			""")
		let reading = try await session.respond(to: text, generating: Reading.self).content
		return WordListInterpreter.sanitized(genres: reading.genres, avoid: reading.avoidGenres,
		                                     keywords: reading.keywords, kind: reading.kind,
		                                     ending: reading.ending, genreNames: genreNames)
	}
}

/// Reads a sentence from a list of words, for a device without the on-device
/// model. It finds the plain asks — "funny", "scary", "happy ending", "not
/// horror" — and misses what needs real reading.
enum WordListInterpreter {
	private static let genreWords: [(genre: String, words: [String])] = [
		("Romance", ["romantic", "romance", "love", "rom-com", "romcom"]),
		("Comedy", ["funny", "comedy", "comedic", "laugh", "rom-com", "romcom", "hilarious"]),
		("Horror", ["scary", "horror", "creepy", "terrifying"]),
		("Thriller", ["thriller", "tense", "suspense", "suspenseful", "gripping"]),
		("Mystery", ["mystery", "whodunit", "detective"]),
		("Science Fiction", ["sci-fi", "scifi", "space", "futuristic", "dystopian"]),
		("Fantasy", ["fantasy", "magic", "magical", "wizards"]),
		("Animation", ["animated", "animation", "cartoon", "anime"]),
		("Family", ["family", "kids"]),
		("Crime", ["crime", "heist", "gangster", "mafia"]),
		("War", ["war"]),
		("History", ["historical", "history", "period"]),
		("Documentary", ["documentary", "docuseries"]),
		("Action", ["action", "explosive", "fights"]),
		("Adventure", ["adventure", "quest"]),
		("Drama", ["drama", "emotional", "dramatic"]),
		("Music", ["musical", "music"]),
	]
	private static let negators: Set<String> = ["no", "not", "without", "nothing", "never", "doesn't", "doesnt",
	                                            "don't", "dont", "isn't", "isnt", "avoid", "except"]
	private static let sadWords: Set<String> = ["sad", "depressing", "tragic", "bleak", "heartbreaking", "gloomy"]
	private static let happyPhrases = ["happy ending", "feel good", "feel-good", "feelgood", "uplifting",
	                                   "heartwarming", "wholesome", "lighthearted"]

	static func interpret(_ text: String, genreNames: [String]) -> DescribedQuery {
		// A phone's keyboard types curly apostrophes: "doesn’t" is one word.
		let lowered = text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
		let words = lowered.split { !$0.isLetter && $0 != "-" && $0 != "'" }.map(String.init)
		var query = DescribedQuery()
		let availableSet = Similarity.genreSet(genreNames)

		for (index, word) in words.enumerated() {
			if sadWords.contains(word) { continue }
			guard let genre = genreWords.first(where: { $0.words.contains(word) })?.genre else { continue }
			// Only genres TMDb has, TV's joint names lined up with film's.
			guard !Similarity.genreSet([genre]).isDisjoint(with: availableSet) else { continue }
			let before = words[max(0, index - 3)..<index]
			if before.contains(where: negators.contains) {
				if !query.avoidGenres.contains(genre) { query.avoidGenres.append(genre) }
			} else if !query.genres.contains(genre) {
				query.genres.append(genre)
			}
		}

		// "No sad ending", "doesn't end sadly", "happy ending" — a happy one.
		var wantsHappy = happyPhrases.contains { lowered.contains($0) }
		for (index, word) in words.enumerated() where sadWords.contains(word) || word.hasPrefix("sadly") {
			let before = words[max(0, index - 4)..<index]
			if before.contains(where: negators.contains) { wantsHappy = true }
		}
		if wantsHappy {
			query.ending = .happy
		} else if lowered.contains("bittersweet") {
			query.ending = .bittersweet
		} else if lowered.contains("tearjerker") || lowered.contains("make me cry") || lowered.contains("sad ending") {
			query.ending = .sad
		}

		if words.contains(where: ["movie", "movies", "film", "films"].contains) {
			query.kind = .film
		} else if words.contains(where: ["show", "shows", "series", "tv", "binge"].contains) {
			query.kind = .show
		}
		if query.ending == .happy { query.keywords = ["happy ending"] }
		return query
	}

	/// A model's answer made safe to use: genre names only from TMDb's list,
	/// the type and ending read from its words.
	static func sanitized(genres: [String], avoid: [String], keywords: [String], kind: String,
	                      ending: String, genreNames: [String]) -> DescribedQuery {
		func known(_ names: [String]) -> [String] {
			var seen: [String] = []
			for name in names {
				guard let match = genreNames.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }),
				      !seen.contains(match) else { continue }
				seen.append(match)
			}
			return seen
		}
		var query = DescribedQuery()
		query.genres = Array(known(genres).prefix(3))
		query.avoidGenres = known(avoid).filter { !query.genres.contains($0) }
		query.keywords = Array(keywords.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
			.filter { !$0.isEmpty }.prefix(3))
		switch kind.lowercased() {
		case "film": query.kind = .film
		case "show": query.kind = .show
		default:     query.kind = nil
		}
		query.ending = EndingFeel(rawValue: ending.lowercased())
		if query.ending == .happy, !query.keywords.contains("happy ending") { query.keywords.append("happy ending") }
		return query
	}
}

// MARK: - Looking it up

@Observable
final class DescribeSession {
	enum Phase: Equatable {
		case idle, working, ready
		case failed(String)
	}

	private(set) var phase: Phase = .idle
	/// What was asked for, once read.
	private(set) var query: DescribedQuery?
	/// Whether Apple's on-device model read it, rather than the word list.
	private(set) var usedModel = false
	/// The matches, the taste's favourites first.
	private(set) var results: [Suggestion] = []

	var isActive: Bool { phase != .idle }

	func clear() {
		phase = .idle
		query = nil
		results = []
	}

	/// Reads `text`, looks it up and ranks the matches. `kind` and `picked` are
	/// the filter's own type and genres, which narrow it further.
	func run(_ text: String, kind: BrowseKind, picked: Set<String>, taste: TasteProfile) async {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { clear(); return }
		phase = .working
		results = []
		guard TMDbConfig.isConfigured else { phase = .failed("No TMDb key."); return }

		let tv = (try? await TMDbService.shared.tvGenres()) ?? []
		let movie = (try? await TMDbService.shared.movieGenres()) ?? []
		let names = Set((tv + movie).compactMap(\.name))
		var (read, model) = await DescribeInterpreter.interpret(trimmed, genreNames: Array(names))
		for genre in picked.sorted() where !read.genres.contains(genre) { read.genres.append(genre) }
		query = read
		usedModel = model

		var kinds: [MediaKind] = []
		switch kind {
		case .shows: kinds = [.show]
		case .films: kinds = [.film]
		case .all:   kinds = read.kind.map { [$0] } ?? [.film, .show]
		}

		var keywordIDs: [Int] = []
		for word in read.keywords.prefix(3) {
			if let id = try? await TMDbService.shared.keywordID(for: word) { keywordIDs.append(id) }
		}

		var found: [[Suggestion]] = []
		var reached = false
		for kind in kinds {
			let table = Dictionary((kind == .show ? tv : movie).compactMap { genre in
				genre.name.map { (genre.id, $0) }
			}, uniquingKeysWith: { first, _ in first })
			func ids(_ wanted: [String]) -> [Int] {
				wanted.compactMap { name in
					let set = Similarity.genreSet([name])
					return table.filter { !Similarity.genreSet([$0.value]).isDisjoint(with: set) }.keys.min()
				}
			}
			let genreIDs = ids(read.genres)
			// TV has no Romance, say: leaving the genre out would hand back
			// everything, so this type has nothing to offer for it.
			guard genreIDs.count == read.genres.count else { reached = true; continue }
			// Every genre and the keywords; failing that, enough to go on with —
			// first without the keywords, then with only the first genre.
			let attempts: [(genres: [Int], keywords: [Int])] = [
				(genreIDs, keywordIDs), (genreIDs, []), (Array(genreIDs.prefix(1)), []),
			]
			var best: [Suggestion] = []
			for attempt in attempts {
				guard let titles = try? await TMDbService.shared.discover(
					kind, genreIDs: attempt.genres, withoutGenreIDs: ids(read.avoidGenres),
					keywordIDs: attempt.keywords) else { continue }
				reached = true
				best = titles.compactMap { Suggestion($0, kind: kind, genreNames: table) }
				if best.count >= 8 { break }
			}
			found.append(best)
		}
		guard reached else { phase = .failed("Couldn\u{2019}t reach TMDb."); return }

		// Alternate films and shows when both were asked for.
		var merged: [Suggestion] = []
		let longest = found.map(\.count).max() ?? 0
		for index in 0..<longest { for list in found where index < list.count { merged.append(list[index]) } }
		results = taste.ranked(merged)
		phase = .ready
	}
}
