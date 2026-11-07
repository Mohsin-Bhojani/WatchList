//
//  EndingJudge.swift
//  WatchList
//
//  Describe's judgement of how a candidate ends, against the ending asked for.
//  Split out of DescribeSearch.swift.
//

import Foundation
import FoundationModels
import WatchListCore
import WatchListLibrary

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
