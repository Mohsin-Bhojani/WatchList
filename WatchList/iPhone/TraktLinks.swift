//
//  TraktLinks.swift
//  WatchList
//
//  "Open in… Trakt". Trakt's pages are addressed by a slug — "inception-2010",
//  "dark-matter-2024" — that can't be worked out from a title, since a second
//  title of the same name takes a year on (the plain "dark-matter" is a 2015
//  show). Its old id-lookup links now 404 and its search needs you signed in,
//  so the slug comes from Trakt's API, looked up by TMDb or IMDb id when the
//  link is tapped and remembered for the session.
//
//  The API wants a client id: `TRAKT_CLIENT_ID` in Configuration/Secrets.xcconfig,
//  carried into the bundle like the TMDb key. Without one Trakt isn't offered.
//

import Foundation

/// Which Trakt page a title page's link goes to.
struct TraktLookup: Hashable {
	enum Kind: String { case movie, show }

	let kind: Kind
	let tmdbID: Int?
	let imdbID: String?
	/// A season or episode of the show, whose page hangs off the show's slug.
	var season: Int?
	var episode: Int?

	/// Nil when there's no id to look it up by.
	init?(_ kind: Kind, tmdbID: Int?, imdbID: String?, season: Int? = nil, episode: Int? = nil) {
		guard tmdbID != nil || imdbID?.isEmpty == false else { return nil }
		self.kind = kind
		self.tmdbID = tmdbID
		self.imdbID = imdbID
		self.season = season
		self.episode = episode
	}

	/// The page on trakt.tv, given the movie's or show's slug.
	func pageURL(slug: String) -> URL? {
		guard !slug.isEmpty, slug.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else {
			return nil
		}
		var path = "https://trakt.tv/\(kind == .movie ? "movies" : "shows")/\(slug)"
		if kind == .show, let season {
			path += "/seasons/\(season)"
			if let episode { path += "/episodes/\(episode)" }
		}
		return URL(string: path)
	}
}

enum Trakt {
	static let clientID: String = {
		let bundled = Bundle.main.object(forInfoDictionaryKey: "TraktClientID") as? String ?? ""
		return bundled.trimmingCharacters(in: .whitespacesAndNewlines)
	}()

	static var isConfigured: Bool { !clientID.isEmpty }

	private static var slugs: [String: String] = [:]

	/// The title's Trakt page, or nil when Trakt doesn't have it or can't be reached.
	static func pageURL(_ lookup: TraktLookup) async -> URL? {
		let (idType, id) = lookup.tmdbID.map { ("tmdb", String($0)) } ?? ("imdb", lookup.imdbID ?? "")
		let key = "\(lookup.kind.rawValue)/\(idType)/\(id)"
		if let slug = slugs[key] { return lookup.pageURL(slug: slug) }

		guard isConfigured,
		      let url = URL(string: "https://api.trakt.tv/search/\(idType)/\(id)?type=\(lookup.kind.rawValue)")
		else { return nil }
		var request = URLRequest(url: url)
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.setValue("2", forHTTPHeaderField: "trakt-api-version")
		request.setValue(clientID, forHTTPHeaderField: "trakt-api-key")
		guard let (data, response) = try? await URLSession.shared.data(for: request),
		      (response as? HTTPURLResponse)?.statusCode == 200,
		      let slug = slug(in: data, kind: lookup.kind) else { return nil }
		slugs[key] = slug
		return lookup.pageURL(slug: slug)
	}

	/// The first result's slug, from `/search/{id_type}/{id}`.
	static func slug(in data: Data, kind: TraktLookup.Kind) -> String? {
		struct Result: Decodable {
			struct Item: Decodable {
				struct IDs: Decodable { let slug: String? }
				let ids: IDs
			}
			let movie: Item?
			let show: Item?
		}
		guard let results = try? JSONDecoder().decode([Result].self, from: data) else { return nil }
		return results.lazy.compactMap { (kind == .movie ? $0.movie : $0.show)?.ids.slug }.first
	}
}
