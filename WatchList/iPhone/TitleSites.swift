//
//  TitleSites.swift
//  WatchList
//
//  The sites "Open in…" lists for a title: IMDb and TMDb, then Letterboxd,
//  Trakt, Rotten Tomatoes, Metacritic and JustWatch wherever they have
//  somewhere to go.
//    - Letterboxd looks a film up by its TMDb (or IMDb) id and lands on its
//      page; it only has films. Trakt is looked up through its API when
//      tapped (TraktLinks), and only offered once there's a Trakt client id.
//    - Rotten Tomatoes, Metacritic and JustWatch take no outside ids, so they
//      open a search for the title, which is usually one tap from its page.
//      JustWatch searches in Settings' Where to watch country.
//  Season and episode pages get only what reaches them: IMDb, TMDb and Trakt,
//  whose seasons and episodes hang off their show's page.
//

import Foundation

/// One site a title opens in.
struct TitleSite: Identifiable, Equatable {
	enum Destination: Equatable {
		case url(URL)
		/// Looked up when tapped.
		case trakt(TraktLookup)
	}

	let name: String
	let destination: Destination

	var id: String { name }

	/// The address, when it's known without a lookup.
	var url: URL? {
		if case .url(let url) = destination { return url }
		return nil
	}
}

enum TitleSites {
	static func film(imdbID: String?, tmdbID: Int?, title: String, region: String = currentRegion,
	                 trakt: Bool = Trakt.isConfigured) -> [TitleSite] {
		[site("IMDb", imdbID.flatMap(IMDb.titleURL)),
		 site("TMDb", TitleLinks.tmdbMovie(tmdbID)),
		 site("Letterboxd", tmdbID.map { "https://letterboxd.com/tmdb/\($0)/" }
		 	?? imdbID.map { "https://letterboxd.com/imdb/\($0)/" }),
		 traktSite(trakt, TraktLookup(.movie, tmdbID: tmdbID, imdbID: imdbID)),
		 site("Rotten Tomatoes", search(title) { "https://www.rottentomatoes.com/search?search=\($0)" }),
		 site("Metacritic", pathSearch(title) { "https://www.metacritic.com/search/\($0)/" }),
		 site("JustWatch", justWatch(title, region: region))].compactMap { $0 }
	}

	static func show(imdbID: String?, tmdbID: Int?, title: String, region: String = currentRegion,
	                 trakt: Bool = Trakt.isConfigured) -> [TitleSite] {
		[site("IMDb", imdbID.flatMap(IMDb.titleURL)),
		 site("TMDb", TitleLinks.tmdbTV(tmdbID)),
		 traktSite(trakt, TraktLookup(.show, tmdbID: tmdbID, imdbID: imdbID)),
		 site("Rotten Tomatoes", search(title) { "https://www.rottentomatoes.com/search?search=\($0)" }),
		 site("Metacritic", pathSearch(title) { "https://www.metacritic.com/search/\($0)/" }),
		 site("JustWatch", justWatch(title, region: region))].compactMap { $0 }
	}

	static func season(showIMDbID: String?, showTMDbID: Int?, season: Int,
	                   trakt: Bool = Trakt.isConfigured) -> [TitleSite] {
		[site("IMDb", showIMDbID.flatMap { IMDb.seasonURL($0, season: season) }),
		 site("TMDb", TitleLinks.tmdbTV(showTMDbID, season: season)),
		 traktSite(trakt, TraktLookup(.show, tmdbID: showTMDbID, imdbID: showIMDbID, season: season))]
			.compactMap { $0 }
	}

	/// Trakt finds an episode through its show, so it needs the show's ids.
	static func episode(imdbID: String?, showTMDbID: Int?, showIMDbID: String?, season: Int, episode: Int,
	                    trakt: Bool = Trakt.isConfigured) -> [TitleSite] {
		[site("IMDb", imdbID.flatMap(IMDb.titleURL)),
		 site("TMDb", TitleLinks.tmdbTV(showTMDbID, season: season, episode: episode)),
		 traktSite(trakt, TraktLookup(.show, tmdbID: showTMDbID, imdbID: showIMDbID,
		                              season: season, episode: episode))].compactMap { $0 }
	}

	/// Where to watch's country, which JustWatch searches in.
	static var currentRegion: String {
		WatchRegion.resolved(UserDefaults.standard.string(forKey: WatchRegion.key) ?? "")
	}

	// MARK: Building links

	private static func site(_ name: String, _ url: URL?) -> TitleSite? {
		url.map { TitleSite(name: name, destination: .url($0)) }
	}

	private static func traktSite(_ enabled: Bool, _ lookup: TraktLookup?) -> TitleSite? {
		guard enabled, let lookup else { return nil }
		return TitleSite(name: "Trakt", destination: .trakt(lookup))
	}

	private static func site(_ name: String, _ link: String?) -> TitleSite? {
		site(name, link.flatMap(URL.init(string:)))
	}

	/// JustWatch's site is by country, lowercased — except the UK, which it
	/// files as `uk` rather than ISO's `gb`.
	private static func justWatch(_ title: String, region: String) -> URL? {
		let country = region.uppercased() == "GB" ? "uk" : region.lowercased()
		guard country.count == 2, country.allSatisfy(\.isLetter) else { return nil }
		return search(title) { "https://www.justwatch.com/\(country)/search?q=\($0)" }
	}

	private static func search(_ title: String, _ link: (String) -> String) -> URL? {
		encoded(title, allowed: queryValue).flatMap { URL(string: link($0)) }
	}

	private static func pathSearch(_ title: String, _ link: (String) -> String) -> URL? {
		encoded(title, allowed: pathSegment).flatMap { URL(string: link($0)) }
	}

	private static func encoded(_ title: String, allowed: CharacterSet) -> String? {
		let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return nil }
		return trimmed.addingPercentEncoding(withAllowedCharacters: allowed)
	}

	/// Unescaped in a query value: not `&`, `=`, `+`, `#` or `?`.
	private static let queryValue = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#?"))
	/// Unescaped in one path segment: not `/`, `?` or `#`.
	private static let pathSegment = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))
}
