//
//  TitleReference.swift
//  WatchList
//
//  Describe's titles named in a sentence — "like The Gentlemen" — found on
//  TMDb so their recommendations come first. Split out of DescribeSearch.swift.
//

import Foundation

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
