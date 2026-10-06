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

// MARK: - Titles named in a sentence

/// "Something like The Gentlemen": finding the film or show a sentence points at.
enum TitleReference {
	/// Phrases that introduce a title, longest first.
	private static let cues = ["reminds me of", "in the style of", "similar to", "such as", "like"]
	/// Where a title ends: punctuation, or one of these words.
	private static let enders = [" but ", " with ", " that ", " where ", " which ", " so ", " because ", " except "]
	/// What follows "like" when it isn't a title — "like a cozy night", "like me".
	private static let notTitles: Set<String> = ["a", "an", "some", "something", "anything", "my", "me", "that", "this",
	                                             "it", "how", "when", "being", "to", "you", "i", "we", "what"]

	/// The titles a sentence says it wants something like, as typed: whatever
	/// follows "like", "similar to" and the like, up to the end of the phrase.
	/// These are only candidates; TMDb decides whether each is a real title.
	static func extract(from text: String) -> [String] {
		let sentence = text.replacingOccurrences(of: "\u{2019}", with: "'")
		var found: [String] = []
		for cue in cues {
			var searchRange = sentence.startIndex..<sentence.endIndex
			while let hit = sentence.range(of: cue, options: .caseInsensitive, range: searchRange) {
				searchRange = hit.upperBound..<sentence.endIndex
				// A whole word: "likeable" and "dislike" aren't cues.
				let before = hit.lowerBound > sentence.startIndex ? sentence[sentence.index(before: hit.lowerBound)] : " "
				let after = hit.upperBound < sentence.endIndex ? sentence[hit.upperBound] : " "
				guard !before.isLetter, !after.isLetter else { continue }
				if let title = title(after: String(sentence[hit.upperBound...])), !found.contains(title) {
					found.append(title)
				}
			}
		}
		return Array(found.prefix(2))
	}

	private static func title(after rest: String) -> String? {
		var phrase = " " + rest.trimmingCharacters(in: .whitespaces) + " "
		// "like in The Gentlemen", "like the show Succession" keep what's after.
		if phrase.lowercased().hasPrefix(" in ") { phrase = String(phrase.dropFirst(3)) }
		var end = phrase.endIndex
		for stop in enders {
			if let hit = phrase.range(of: stop, options: .caseInsensitive), hit.lowerBound < end { end = hit.lowerBound }
		}
		if let punctuation = phrase.firstIndex(where: { ",;!?()\"".contains($0) }), punctuation < end { end = punctuation }
		let words = phrase[..<end].split(separator: " ").map(String.init)
		guard let first = words.first else { return nil }
		// "like a cozy night" — unless it's capitalised, as in "like A Quiet Place".
		if notTitles.contains(first.lowercased()), first.first?.isUppercase != true { return nil }
		let title = words.prefix(6).joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
		return title.isEmpty ? nil : title
	}

	/// A title for comparing: lower case, letters and digits only, no leading "the".
	static func normalized(_ title: String) -> String {
		var words = title.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
			.split { !$0.isLetter && !$0.isNumber }.map(String.init)
		if words.count > 1, words.first == "the" { words.removeFirst() }
		return words.joined(separator: " ")
	}

	/// Whether TMDb's title is the one the sentence named: the same, or one the
	/// other with a subtitle ("The Gentlemen" and "The Gentlemen: Season 1" would,
	/// "Gentle" and "The Gentlemen" wouldn't).
	static func isMatch(typed: String, title: String) -> Bool {
		let a = normalized(typed), b = normalized(title)
		guard !a.isEmpty, !b.isEmpty else { return false }
		if a == b { return true }
		let (short, long) = a.count <= b.count ? (a, b) : (b, a)
		return long.hasPrefix(short + " ") && Double(short.count) / Double(long.count) >= 0.6
	}
}

/// A film or show a sentence named, as TMDb has it.
struct ReferenceTitle {
	let kind: MediaKind
	let id: Int
	/// TMDb's name for it.
	let title: String
	/// Its genre names, and a few of its keywords' ids.
	let genres: [String]
	let keywordIDs: [Int]
	/// What TMDb recommends for it.
	let recommendations: [TMDbSuggestedTitle]

	/// Looks `typed` up: the first search result that is that title, with its
	/// genres, keywords and recommendations — or nil when TMDb has no such title
	/// (or can't be reached), which is also what "like a cozy night" comes to.
	static func find(_ typed: String) async -> ReferenceTitle? {
		let service = TMDbService.shared
		guard let results = try? await service.multiSearch(query: typed),
		      let hit = results.first(where: { TitleReference.isMatch(typed: typed, title: $0.displayTitle) }) else { return nil }
		let kind: MediaKind = hit.media_type == "tv" ? .show : .film
		var genres: [String] = []
		if kind == .film {
			genres = ((try? await service.movie(id: hit.id))?.genres ?? []).compactMap(\.name)
		} else {
			genres = ((try? await service.tv(id: hit.id))?.genres ?? []).compactMap(\.name)
		}
		let keywords = ((try? await service.keywords(kind, id: hit.id)) ?? []).prefix(4).map(\.id)
		let recommendations = (try? await TMDbSuggestions.titles(kind, hit.id)) ?? []
		return ReferenceTitle(kind: kind, id: hit.id, title: hit.displayTitle, genres: genres,
		                      keywordIDs: Array(keywords), recommendations: recommendations)
	}
}

// MARK: - Judging endings

/// How a title ends as far as its synopsis tells, and what to do with that when
/// someone asked for a kind of ending.
enum EndingFit {
	/// Where a title judged `judged` goes among the matches for a wanted ending:
	/// 0 is best, and nil means leave it out — the opposite of what was asked.
	/// A title not judged, or judged unclear, is never left out.
	static func rank(wanted: EndingFeel, judged: EndingFeel?) -> Int? {
		switch (wanted, judged) {
		case (_, nil):                        return 1
		case (.happy, .happy?):               return 0
		case (.happy, .sad?):                 return nil
		case (.happy, .bittersweet?):         return 1
		case (.sad, .sad?):                   return 0
		case (.sad, .happy?):                 return nil
		case (.sad, .bittersweet?):           return 1
		case (.bittersweet, .bittersweet?):   return 0
		case (.open, .open?):                 return 0
		case (.bittersweet, .open?), (.open, .bittersweet?): return 1
		default:                              return 2
		}
	}
}

/// Apple's on-device model reading how a title ends from its synopsis. A
/// synopsis seldom gives an ending away, so the model says "unclear" unless it
/// has real grounds, and an unclear title is neither kept out nor put first.
enum EndingJudge {
	@Generable
	struct Reading {
		@Guide(description: "How the story ends: 'happy', 'bittersweet', 'sad', 'open' or 'unclear'. Say 'unclear' unless the synopsis or what you reliably know about this title tells you.")
		var ending: String
	}

	static func judge(_ suggestion: Suggestion) async -> EndingFeel? {
		guard DescribeInterpreter.onDeviceAvailable, !suggestion.overview.isEmpty else { return nil }
		// A session each, so one title's synopsis doesn't colour the next.
		let session = LanguageModelSession(instructions: """
			You judge how a film or show ends. Never guess from the title or genre alone: \
			answer 'unclear' when you aren't sure.
			""")
		let year = suggestion.year.map { " (\($0))" } ?? ""
		let prompt = "\(suggestion.title)\(year), \(suggestion.genres.joined(separator: ", ")).\n\(suggestion.overview)"
		guard let reading = try? await session.respond(to: prompt, generating: Reading.self).content else { return nil }
		return EndingFeel(rawValue: reading.ending.lowercased())
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
	/// What TMDb sent, the taste's favourites first.
	private(set) var candidates: [Suggestion] = []
	/// How each candidate ends, as far as it's been judged.
	private(set) var endings: [String: EndingFeel] = [:]
	/// Whether endings are still being judged in the background.
	private(set) var isJudging = false
	/// How many candidates are judged before the first card is shown.
	static let judgedBeforeShowing = 6
	/// How many are judged in all.
	static let judgedInAll = 30

	@ObservationIgnored private var judging: Task<Void, Never>?
	/// Reads one candidate's ending; the on-device model unless a test says otherwise.
	@ObservationIgnored var judge: (Suggestion) async -> EndingFeel?

	init(judge: @escaping (Suggestion) async -> EndingFeel? = { await EndingJudge.judge($0) }) {
		self.judge = judge
	}

	/// The matches: the candidates when no ending was asked for; otherwise those
	/// that don't end the opposite way, the best fits first and the taste's order
	/// among equals.
	var results: [Suggestion] {
		guard let wanted = query?.ending else { return candidates }
		let ranked = candidates.enumerated().compactMap { index, suggestion -> (Int, Int, Suggestion)? in
			EndingFit.rank(wanted: wanted, judged: endings[suggestion.id]).map { ($0, index, suggestion) }
		}
		return ranked.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }.map(\.2)
	}

	/// Fills the session without going to TMDb, for tests.
	func setForTesting(candidates: [Suggestion], query: DescribedQuery) {
		self.candidates = candidates
		self.query = query
		phase = .ready
	}

	/// "Reads as a happy ending", for a card whose ending has been judged.
	func endingNote(for suggestion: Suggestion) -> String? {
		endings[suggestion.id].map { "reads as a \($0.rawValue) ending" }
	}

	var isActive: Bool { phase != .idle }

	func clear() {
		judging?.cancel()
		judging = nil
		isJudging = false
		phase = .idle
		query = nil
		candidates = []
		endings = [:]
	}

	/// Reads `text`, looks it up and ranks the matches. `kind` and `picked` are
	/// the filter's own type and genres, which narrow it further.
	func run(_ text: String, kind: BrowseKind, picked: Set<String>, taste: TasteProfile) async {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { clear(); return }
		judging?.cancel()
		judging = nil
		isJudging = false
		phase = .working
		candidates = []
		endings = [:]
		guard TMDbConfig.isConfigured else { phase = .failed("No TMDb key."); return }

		let tv = (try? await TMDbService.shared.tvGenres()) ?? []
		let movie = (try? await TMDbService.shared.movieGenres()) ?? []
		// One list for the model, so a genre isn't offered twice: film's names, and
		// TV's where film has no match (Kids, Reality). Joint names like "Action &
		// Adventure" are film's Action and Adventure already.
		let filmNames = movie.compactMap(\.name)
		let filmSets = Similarity.genreSet(filmNames)
		let tvOnly = tv.compactMap(\.name).filter { name in
			!name.contains("&") && Similarity.genreSet([name]).isDisjoint(with: filmSets)
		}
		var (read, model) = await DescribeInterpreter.interpret(trimmed, genreNames: filmNames + tvOnly)
		for genre in picked.sorted() where !read.genres.contains(genre) { read.genres.append(genre) }
		usedModel = model

		// "Like The Gentlemen": the titles TMDb knows by those names, kept under
		// the names TMDb gives them. A name TMDb doesn't know is dropped.
		var references: [ReferenceTitle] = []
		for typed in read.references.prefix(2) {
			if let found = await ReferenceTitle.find(typed) { references.append(found) }
		}
		read.references = references.map(\.title)
		// The genres asked for in words; with none, the first title's own stand in.
		let askedGenres = read.genres
		if askedGenres.isEmpty, let first = references.first {
			let allowed = filmNames + tvOnly
			var taken = Set<String>()
			for name in first.genres {
				let set = Similarity.genreSet([name])
				guard taken.isDisjoint(with: set), let match = allowed.first(where: {
					!Similarity.genreSet([$0]).isDisjoint(with: set)
				}) else { continue }
				taken.formUnion(set)
				read.genres.append(match)
				if read.genres.count == 2 { break }
			}
		}
		query = read

		var kinds: [MediaKind] = []
		switch kind {
		case .shows: kinds = [.show]
		case .films: kinds = [.film]
		case .all:   kinds = read.kind.map { [$0] } ?? references.first.map { [$0.kind] } ?? [.film, .show]
		}

		var keywordIDs: [Int] = []
		for word in read.keywords.prefix(3) {
			if let id = try? await TMDbService.shared.keywordID(for: word) { keywordIDs.append(id) }
		}
		keywordIDs += references.first?.keywordIDs.prefix(4) ?? []

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
		// What TMDb recommends for the titles named come first — people who liked
		// them went on to watch these — as long as they fit the rest of the
		// sentence; then the matches for its genres and keywords.
		let avoided = Similarity.genreSet(read.avoidGenres)
		let wantedGenres = Similarity.genreSet(askedGenres)
		var recommended: [Suggestion] = []
		for reference in references {
			let table = Dictionary((reference.kind == .show ? tv : movie).compactMap { genre in
				genre.name.map { (genre.id, $0) }
			}, uniquingKeysWith: { first, _ in first })
			for title in reference.recommendations {
				guard let suggestion = Suggestion(title, kind: reference.kind, genreNames: table),
				      kind.includes(suggestion.kind),
				      !recommended.contains(where: { $0.id == suggestion.id }) else { continue }
				let genres = Similarity.genreSet(suggestion.genres)
				guard genres.isDisjoint(with: avoided), wantedGenres.isEmpty || !genres.isDisjoint(with: wantedGenres)
				else { continue }
				recommended.append(suggestion)
			}
		}
		let named = Set(references.map { $0.kind.key(tmdbID: $0.id) })
		let taken = Set(recommended.map(\.id)).union(named)
		candidates = taste.ranked(recommended) + taste.ranked(merged.filter { !taken.contains($0.id) })
		await judgeEndings(wanted: read.ending)
		phase = .ready
	}

	/// With an ending asked for, reads the first candidates' endings before any
	/// card is shown, so the first cards are already the right ones, and the rest
	/// in the background as the viewer swipes.
	func judgeEndings(wanted: EndingFeel?) async {
		guard wanted != nil else { return }
		let toJudge = Array(candidates.prefix(Self.judgedInAll))
		let now = Array(toJudge.prefix(Self.judgedBeforeShowing))
		let later = Array(toJudge.dropFirst(Self.judgedBeforeShowing))
		for suggestion in now {
			guard !Task.isCancelled else { return }
			if let feel = await judge(suggestion) { endings[suggestion.id] = feel }
		}
		guard !later.isEmpty else { return }
		isJudging = true
		judging = Task { [weak self] in
			for suggestion in later {
				guard !Task.isCancelled, let self else { return }
				if let feel = await self.judge(suggestion) { self.endings[suggestion.id] = feel }
			}
			self?.isJudging = false
		}
	}
}
