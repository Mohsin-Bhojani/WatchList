//
//  TasteProfile.swift
//  WatchList
//
//  What the library says about taste, as numbers Discover can score a
//  suggestion with. A title's verdict says how much it was liked; the aspects
//  picked on its rating card say what for. Both move the genres the title
//  carries:
//    - verdict: Perfection +1, Go For It +0.6, Timepass +0.1, Skip -0.8; a
//      title with no verdict says nothing
//    - aspects: each one liked +0.15 and each disliked -0.15, up to 0.45 either
//      way, so a loved title with a hated ending counts for less
//    - Romance, Humour and Music name genres too: liking Romance on any title
//      leans toward the Romance genre, disliking it away from it
//  A genre's affinity is the average of its titles' pulls, held back toward 0
//  until a few titles agree, so one rating can't decide a genre. Affinity runs
//  from -1 to 1; a suggestion's score from 0 to 100, 50 meaning no leaning.
//
//  TMDb's keywords and cast aren't on a suggestion yet; when they are, they take
//  their place beside genres here.
//

import Foundation

/// A library title as the profile reads it: no models, so it's easy to test.
struct TasteSample {
	let genres: Set<String>
	let rating: Rating?
	let aspects: AspectTaste
}

extension TasteSample {
	init(_ title: WatchedTitle) {
		self.init(genres: Similarity.genreSet(title.genre.split(separator: ",").map(String.init)),
		          rating: title.rating, aspects: title.aspectTaste)
	}
}

extension WatchedTitle {
	var aspectTaste: AspectTaste {
		switch self {
		case .show(let show): return show.aspectTaste
		case .film(let film): return film.aspectTaste
		}
	}
}

struct TasteProfile {
	/// How many titles' worth of doubt every genre starts with: with 2, one
	/// Perfection title brings a genre a third of the way to 1.
	static let doubt = 2.0
	/// What a title's aspects can add or take away, at most.
	static let aspectLimit = 0.45
	static let aspectStep = 0.15
	/// What liking or disliking an aspect that names a genre does to that genre.
	static let genrePull = 0.5

	/// Each genre's affinity, -1 to 1. A genre the library says nothing about
	/// isn't here.
	let genreAffinity: [String: Double]

	init(_ samples: [TasteSample]) {
		var pull: [String: Double] = [:]
		var count: [String: Double] = [:]
		for sample in samples {
			let weight = Self.weight(sample)
			for genre in sample.genres where weight != 0 {
				pull[genre, default: 0] += weight
				count[genre, default: 0] += 1
			}
			for aspect in Aspect.allCases {
				guard let genre = Self.genre(named: aspect) else { continue }
				switch sample.aspects.state(of: aspect) {
				case .liked:    pull[genre, default: 0] += Self.genrePull; count[genre, default: 0] += 1
				case .disliked: pull[genre, default: 0] -= Self.genrePull; count[genre, default: 0] += 1
				case .unmarked: break
				}
			}
		}
		genreAffinity = pull.reduce(into: [:]) { result, entry in
			let value = entry.value / (count[entry.key, default: 0] + Self.doubt)
			result[entry.key] = max(-1, min(1, value))
		}
	}

	init(_ library: [WatchedTitle]) {
		self.init(library.map(TasteSample.init))
	}

	/// How much a title pulls its genres, from its verdict and its aspects.
	private static func weight(_ sample: TasteSample) -> Double {
		guard let rating = sample.rating else { return 0 }
		let verdict: Double = switch rating {
		case .perfection: 1
		case .goForIt:    0.6
		case .timepass:   0.1
		case .skip:       -0.8
		}
		let net = Double(sample.aspects.liked.count - sample.aspects.disliked.count) * aspectStep
		return verdict + max(-aspectLimit, min(aspectLimit, net))
	}

	/// The genre an aspect stands for, if it stands for one.
	private static func genre(named aspect: Aspect?) -> String? {
		switch aspect {
		case .romance: return "romance"
		case .humour:  return "comedy"
		case .music:   return "music"
		default:       return nil
		}
	}

	/// -1 to 1: the average affinity of the suggestion's genres the library has a
	/// view on; 0 when it has none.
	func affinity(for suggestion: Suggestion) -> Double {
		let known = Similarity.genreSet(suggestion.genres).compactMap { genreAffinity[$0] }
		return known.isEmpty ? 0 : known.reduce(0, +) / Double(known.count)
	}

	/// 0 to 100, 50 for a suggestion the library has no view on.
	func score(_ suggestion: Suggestion) -> Int {
		Int((50 + 50 * affinity(for: suggestion)).rounded())
	}

	/// The genre that moves the suggestion's score most, with the way: the one
	/// to say "you rate Romance highly" about.
	func strongestGenre(for suggestion: Suggestion) -> (genre: String, affinity: Double)? {
		var best: (genre: String, affinity: Double)?
		for genre in Similarity.genreSet(suggestion.genres).sorted() {
			guard let value = genreAffinity[genre] else { continue }
			// Sorted A–Z, so a tie goes to the first.
			if best == nil || abs(value) > abs(best!.affinity) { best = (genre, value) }
		}
		return best
	}

	/// The suggestions the taste favours first. Ties keep their order, which is
	/// TMDb's.
	func ranked(_ suggestions: [Suggestion]) -> [Suggestion] {
		let scored: [(index: Int, suggestion: Suggestion, score: Int)] = suggestions.enumerated()
			.map { (index: $0.offset, suggestion: $0.element, score: score($0.element)) }
		let ordered = scored.sorted { lhs, rhs in
			lhs.score != rhs.score ? lhs.score > rhs.score : lhs.index < rhs.index
		}
		return ordered.map(\.suggestion)
	}
}
