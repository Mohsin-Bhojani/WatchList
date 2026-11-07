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
	/// Films or shows the sentence says it wants something like — as typed, then
	/// as TMDb names them once they've been found.
	var references: [String] = []

	/// "Romance · happy ending · not Horror · like The Gentlemen", for under the
	/// card and the filter.
	var summary: String {
		var parts = genres
		if let ending { parts.append("\(ending.rawValue) ending") }
		parts += avoidGenres.map { "not \($0)" }
		parts += references.map { "like \($0)" }
		if parts.isEmpty { parts = keywords }
		return parts.joined(separator: " \u{00B7} ")
	}

	var isEmpty: Bool {
		genres.isEmpty && avoidGenres.isEmpty && keywords.isEmpty && ending == nil && references.isEmpty
	}
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
		@Guide(description: "Genres the person explicitly said they don't want, each copied exactly from the allowed list. Empty unless they said so in words like 'not', 'no' or 'without'.")
		var avoidGenres: [String]
		@Guide(description: "Up to three short keywords that describe the mood or theme, such as 'feel-good' or 'time travel'.")
		var keywords: [String]
		@Guide(description: "Titles of films or shows the person says they want something like, copied as they wrote them. Empty if they name none.")
		var similarTo: [String]
		@Guide(description: "Either 'film', 'show' or 'either'.")
		var kind: String
		@Guide(description: "How the person wants it to end: 'happy', 'bittersweet', 'sad' or 'open', only if they talk about the ending or how it should make them feel. Otherwise 'any'.")
		var ending: String
	}

	private static func onDevice(_ text: String, genreNames: [String]) async throws -> DescribedQuery {
		let session = LanguageModelSession(instructions: """
			You turn a description of what someone wants to watch into search terms. \
			Allowed genres: \(genreNames.sorted().joined(separator: ", ")). \
			Only use those exact genre names, and never list a genre twice. \
			Use only what the person actually said: don't add an ending or genres to avoid \
			they didn't mention. If they name a film or show, use that title's own genres. \
			"No sad ending" means the ending is happy.
			""")
		let reading = try await session.respond(to: text, generating: Reading.self).content
		return WordListInterpreter.sanitized(genres: reading.genres, avoid: reading.avoidGenres,
		                                     keywords: reading.keywords, similarTo: reading.similarTo, kind: reading.kind,
		                                     ending: reading.ending, genreNames: genreNames, text: text)
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
		query.references = TitleReference.extract(from: text)
		return query
	}

	/// Words that mean the sentence is about how something ends or feels.
	private static let endingCues = ["end", "ending", "ends", "ended", "cry", "sad", "happy", "feel-good", "feel good",
	                                 "uplifting", "tearjerker", "bittersweet", "heartwarming", "wholesome",
	                                 "depressing", "tragic", "twist", "cozy", "cosy"]

	/// A model's answer made safe to use. The model has to fill every field, so
	/// it makes some up: an ending is kept only if the sentence talks about one,
	/// and genres to avoid only if it says "not" or "no" somewhere. Genre names
	/// come only from TMDb's list, and the same genre under TV's name and film's
	/// (Action, Action & Adventure) counts once.
	static func sanitized(genres: [String], avoid: [String], keywords: [String], similarTo: [String] = [],
	                      kind: String, ending: String, genreNames: [String], text: String) -> DescribedQuery {
		let lowered = text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
		let words = Set(lowered.split { !$0.isLetter && $0 != "-" && $0 != "'" }.map(String.init))
		let mentionsEnding = endingCues.contains { $0.contains(" ") ? lowered.contains($0) : words.contains($0) }
		let negates = !words.isDisjoint(with: negators) || words.contains("but")

		func known(_ names: [String], skipping taken: Set<String> = []) -> [String] {
			var seen: [String] = []
			var covered = taken
			for name in names {
				guard let match = genreNames.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
				let set = Similarity.genreSet([match])
				guard covered.isDisjoint(with: set) else { continue }
				covered.formUnion(set)
				seen.append(match)
			}
			return seen
		}
		var query = DescribedQuery()
		query.genres = Array(known(genres).prefix(3))
		let wanted = Similarity.genreSet(query.genres)
		query.avoidGenres = negates ? known(avoid, skipping: wanted) : []
		query.keywords = Array(keywords.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
			.filter { !$0.isEmpty }.prefix(3))
		switch kind.lowercased() {
		case "film": query.kind = .film
		case "show": query.kind = .show
		default:     query.kind = nil
		}
		// A title the model names counts only if the sentence does.
		let sentence = TitleReference.normalized(text)
		query.references = Array(similarTo.filter {
			let name = TitleReference.normalized($0)
			return !name.isEmpty && sentence.contains(name)
		}.prefix(2))
		if mentionsEnding { query.ending = EndingFeel(rawValue: ending.lowercased()) }
		if query.ending == .happy, !query.keywords.contains("happy ending") { query.keywords.append("happy ending") }
		return query
	}
}
