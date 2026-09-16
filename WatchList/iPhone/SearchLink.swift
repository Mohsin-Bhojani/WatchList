//
//  SearchLink.swift
//  WatchList
//
//  Recognises a title link typed or pasted into the iPhone Search tab's field,
//  so the field can offer to add that exact title instead of running a text
//  search for a URL.
//

import Foundation

/// A title link the search field knows how to import.
enum SearchLink: Equatable {
	/// An IMDb title, by its `tt` id. Still needs a TMDb lookup to import.
	case imdb(String)
	/// A TMDb page, which already names the kind and the TMDb id.
	case tmdb(MediaKind, Int)

	/// Reads a title link — or a bare IMDb id — out of the search text. Share
	/// text with a link inside it counts; plain words return nil and go to the
	/// TMDb text search.
	static func parse(_ raw: String) -> SearchLink? {
		let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		let lowered = text.lowercased()

		if lowered.contains("themoviedb.org"),
		   let match = text.firstMatch(of: #/themoviedb\.org/(movie|tv)/([0-9]+)/#.ignoresCase()),
		   let id = Int(match.2) {
			return .tmdb(match.1.lowercased() == "tv" ? .show : .film, id)
		}
		if lowered.contains("imdb.com"), let id = IMDb.id(from: text) {
			return .imdb(id)
		}
		if text.wholeMatch(of: #/tt[0-9]{7,}/#) != nil {
			return .imdb(text)
		}
		return nil
	}

	/// True for text that is clearly meant as a link, title link or not. Lets
	/// the field explain an unsupported link rather than search TMDb for it.
	static func looksLikeLink(_ raw: String) -> Bool {
		let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
		return text.contains("://") || text.hasPrefix("www.")
			|| text.contains("imdb.com") || text.contains("themoviedb.org")
	}

	var sourceName: String {
		switch self {
		case .imdb: return "IMDb"
		case .tmdb: return "TMDb"
		}
	}

	/// Carried into the manual form when TMDb can't resolve the link.
	var imdbID: String? {
		if case .imdb(let id) = self { return id }
		return nil
	}
}
