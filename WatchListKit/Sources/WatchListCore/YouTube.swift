//
//  YouTube.swift
//  WatchListCore
//
//  Shows whose episodes are on YouTube — Pakistani dramas, which the channels
//  that air them upload in full, and YouTube's own shows — read from the
//  playlist that holds them:
//    - YouTubeConfig: the YouTube Data API key, from the build like TMDb's
//    - YouTubePlaylistLink: the playlist id in a pasted link
//    - YouTubeService: a playlist's name and its videos, with their lengths
//    - YouTubeEpisodes: which video is which episode, read from the titles
//      ("Episode 12", "Ep 12", "قسط ۱۲"), leaving out teasers and promos
//
//  Playing them is YouTube's embedded player, as trailers are; nothing is
//  downloaded.
//

import Foundation

// MARK: - Key

public enum YouTubeConfig {
	/// The YouTube Data API v3 key, from `Configuration/Secrets.xcconfig` by way
	/// of the iPhone app's Info.plist (`YouTubeAPIKey`). A `YOUTUBE_API_KEY`
	/// environment variable wins when set.
	public static let apiKey: String = {
		let environment = ProcessInfo.processInfo.environment["YOUTUBE_API_KEY"] ?? ""
		if !environment.isEmpty { return environment }
		let bundled = Bundle.main.object(forInfoDictionaryKey: "YouTubeAPIKey") as? String ?? ""
		let trimmed = bundled.trimmingCharacters(in: .whitespacesAndNewlines)
		// An unset build setting arrives as its own name.
		return trimmed.hasPrefix("$(") ? "" : trimmed
	}()

	public static var isConfigured: Bool { !apiKey.isEmpty }
}

// MARK: - Links

public enum YouTubePlaylistLink {
	/// The playlist id in a link — youtube.com/playlist?list=…, a watch link
	/// with &list=…, youtu.be/…?list=… — or a bare id. Nil for anything else,
	/// including youtube.com/show/… pages, which YouTube's API can't read.
	public static func id(from raw: String) -> String? {
		let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		if isID(text) { return text }
		guard let components = URLComponents(string: text.contains("://") ? text : "https://" + text),
		      let host = components.host?.lowercased(),
		      host.hasSuffix("youtube.com") || host == "youtu.be"
		else { return nil }
		let list = components.queryItems?.first { $0.name == "list" }?.value ?? ""
		return isID(list) ? list : nil
	}

	/// Whether `text` reads as a playlist id: PL…, OL…, UU… and the like.
	static func isID(_ text: String) -> Bool {
		guard text.count >= 12, text.count <= 64,
		      ["PL", "OL", "UU", "FL", "LL", "RD", "VL"].contains(where: text.hasPrefix) else { return false }
		return text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
	}

	/// The link that opens a video in YouTube.
	public static func watchURL(_ videoID: String) -> URL? {
		URL(string: "https://www.youtube.com/watch?v=\(videoID)")
	}
}

// MARK: - Service

public struct YouTubeVideo: Equatable, Sendable, Identifiable {
	public init(id: String, title: String, position: Int, publishedAt: Date?, thumbnailURL: String,
	            durationMinutes: Int? = nil) {
		self.id = id
		self.title = title
		self.position = position
		self.publishedAt = publishedAt
		self.thumbnailURL = thumbnailURL
		self.durationMinutes = durationMinutes
	}

	public let id: String
	public let title: String
	/// Where it sits in the playlist, from 0.
	public let position: Int
	public let publishedAt: Date?
	public let thumbnailURL: String
	public var durationMinutes: Int?
}

/// A playlist as YouTube's search lists it, before its videos are read.
public struct YouTubePlaylistResult: Equatable, Sendable, Identifiable {
	public let id: String
	public let title: String
	public let channel: String
	public let thumbnailURL: String
}

public struct YouTubePlaylist: Equatable, Sendable {
	public let id: String
	public let title: String
	public let channel: String
	public let thumbnailURL: String
	public let videos: [YouTubeVideo]
}

public enum YouTubeError: LocalizedError, Equatable {
	case notConfigured
	case badLink
	case notFound
	case refused
	case http(Int)
	case decoding

	public var errorDescription: String? {
		switch self {
		case .notConfigured: return "There's no YouTube API key yet. Add YOUTUBE_API_KEY to Configuration/Secrets.xcconfig and build again."
		case .badLink:       return "That isn't a YouTube playlist link. Open the playlist on YouTube, tap Share, copy the link and paste it here."
		case .notFound:      return "YouTube couldn't find that playlist. It may be private or deleted."
		case .refused:       return "YouTube turned the key down. Check it's restricted to the YouTube Data API v3 and to this app's bundle ID."
		case .http(let code): return "YouTube didn't answer (error \(code)). Try again in a moment."
		case .decoding:      return "YouTube's answer couldn't be read."
		}
	}
}

public struct YouTubeService: Sendable {
	public static let shared = YouTubeService()

	/// Most videos read from one playlist: 20 pages of 50.
	static let pageLimit = 20

	/// A playlist's name and every video in it that can be watched, with their
	/// lengths. Private and deleted videos are left out.
	/// Playlists whose name matches `query` — a show's title — the ones that
	/// read like a full run of episodes first. Costs 100 of the day's 10,000
	/// quota units, so it runs only when asked.
	public func searchPlaylists(_ query: String) async throws -> [YouTubePlaylistResult] {
		let list: SearchList = try await get("search", ["part": "snippet", "type": "playlist", "maxResults": "10",
		                                                 "q": query + " episodes"])
		let results = list.items.compactMap { item -> YouTubePlaylistResult? in
			guard let id = item.id.playlistId, let snippet = item.snippet else { return nil }
			return YouTubePlaylistResult(id: id, title: Self.unescaped(snippet.title ?? ""),
			                             channel: Self.unescaped(snippet.channelTitle ?? ""),
			                             thumbnailURL: snippet.thumbnails?.best ?? "")
		}
		return YouTubeEpisodes.ranked(results)
	}

	/// YouTube's search escapes a few characters in names: "Tom &amp; Jerry".
	static func unescaped(_ text: String) -> String {
		text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"")
			.replacingOccurrences(of: "&#39;", with: "'")
	}

	public func playlist(id: String) async throws -> YouTubePlaylist {
		let info: PlaylistList = try await get("playlists", ["part": "snippet", "id": id])
		guard let snippet = info.items.first?.snippet else { throw YouTubeError.notFound }

		var videos: [YouTubeVideo] = []
		var token: String?
		for _ in 0..<Self.pageLimit {
			var query = ["part": "snippet,contentDetails", "playlistId": id, "maxResults": "50"]
			if let token { query["pageToken"] = token }
			let page: ItemList = try await get("playlistItems", query)
			for item in page.items {
				guard let videoID = item.contentDetails?.videoId, let s = item.snippet,
				      !Self.isUnavailable(s.title) else { continue }
				videos.append(YouTubeVideo(id: videoID, title: s.title ?? "", position: s.position ?? videos.count,
				                           publishedAt: Self.date(item.contentDetails?.videoPublishedAt ?? s.publishedAt),
				                           thumbnailURL: s.thumbnails?.best ?? ""))
			}
			token = page.nextPageToken
			if token == nil { break }
		}

		// Lengths, 50 videos a request.
		var minutes: [String: Int] = [:]
		for start in stride(from: 0, to: videos.count, by: 50) {
			let ids = videos[start..<min(start + 50, videos.count)].map(\.id).joined(separator: ",")
			let details: VideoList = try await get("videos", ["part": "contentDetails", "id": ids])
			for video in details.items {
				if let length = video.contentDetails?.duration.flatMap(Self.minutes) { minutes[video.id] = length }
			}
		}
		for index in videos.indices { videos[index].durationMinutes = minutes[videos[index].id] }

		return YouTubePlaylist(id: id, title: snippet.title ?? "Untitled", channel: snippet.channelTitle ?? "",
		                       thumbnailURL: snippet.thumbnails?.best ?? "", videos: videos)
	}

	// MARK: Reading

	static func isUnavailable(_ title: String?) -> Bool {
		["Private video", "Deleted video"].contains(title ?? "")
	}

	static func date(_ raw: String?) -> Date? {
		guard let raw else { return nil }
		let withFraction = ISO8601DateFormatter()
		withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return withFraction.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
	}

	/// An ISO 8601 length — PT42M10S, PT1H5M — in whole minutes, rounded.
	public static func minutes(_ iso: String) -> Int? {
		guard iso.hasPrefix("PT") || iso.hasPrefix("P") else { return nil }
		var seconds = 0.0, number = ""
		var inTime = false
		for character in iso.dropFirst() {
			if character == "T" { inTime = true; continue }
			if character.isNumber || character == "." { number.append(character); continue }
			let value = Double(number) ?? 0
			number = ""
			switch (inTime, character) {
			case (false, "D"): seconds += value * 86_400
			case (true, "H"):  seconds += value * 3600
			case (true, "M"):  seconds += value * 60
			case (true, "S"):  seconds += value
			default: break
			}
		}
		return seconds > 0 ? max(1, Int((seconds / 60).rounded())) : nil
	}

	private struct Thumbnails: Decodable {
		struct Image: Decodable { let url: String? }
		let maxres: Image?, standard: Image?, high: Image?, medium: Image?
		let `default`: Image?
		/// 16:9 first: YouTube's high and standard sizes are letterboxed 4:3.
		var best: String? { (maxres ?? medium ?? high ?? standard ?? `default`)?.url }
	}
	private struct Snippet: Decodable {
		let title: String?
		let channelTitle: String?
		let position: Int?
		let publishedAt: String?
		let thumbnails: Thumbnails?
	}
	private struct SearchList: Decodable {
		struct Item: Decodable {
			struct ID: Decodable { let playlistId: String? }
			let id: ID
			let snippet: Snippet?
		}
		let items: [Item]
	}
	private struct PlaylistList: Decodable {
		struct Item: Decodable { let snippet: Snippet? }
		let items: [Item]
	}
	private struct ItemList: Decodable {
		struct Item: Decodable {
			struct Details: Decodable { let videoId: String?; let videoPublishedAt: String? }
			let snippet: Snippet?
			let contentDetails: Details?
		}
		let items: [Item]
		let nextPageToken: String?
	}
	private struct VideoList: Decodable {
		struct Item: Decodable {
			struct Details: Decodable { let duration: String? }
			let id: String
			let contentDetails: Details?
		}
		let items: [Item]
	}

	// MARK: Networking

	private func get<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T {
		guard YouTubeConfig.isConfigured else { throw YouTubeError.notConfigured }
		var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/" + path)
		components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
			+ [URLQueryItem(name: "key", value: YouTubeConfig.apiKey)]
		guard let url = components?.url else { throw YouTubeError.badLink }
		var request = URLRequest(url: url)
		// A key restricted to iOS apps checks this header.
		if let bundle = Bundle.main.bundleIdentifier {
			request.setValue(bundle, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
		}
		let (data, response) = try await URLSession.shared.data(for: request)
		let code = (response as? HTTPURLResponse)?.statusCode ?? -1
		switch code {
		case 200...299: break
		case 403, 400: throw YouTubeError.refused
		case 404: throw YouTubeError.notFound
		default: throw YouTubeError.http(code)
		}
		do { return try JSONDecoder().decode(T.self, from: data) } catch { throw YouTubeError.decoding }
	}
}

// MARK: - Episodes

public enum YouTubeEpisodes {
	/// Words that mark a video as something other than the episode itself.
	static let extras = ["teaser", "promo", "preview", "trailer", "next episode", "review", "reaction",
	                     "behind the scenes", " bts ", "making of", "highlights", "best scene", "best moment",
	                     "recap", "#shorts", " shorts ", " ost ", " ost:", "(ost", "title song"]

	/// Whether a video is a teaser, promo, song or clip rather than an episode.
	public static func isExtra(_ title: String) -> Bool {
		let lower = " " + title.lowercased().replacingOccurrences(of: "|", with: " ") + " "
		return extras.contains { lower.contains($0) }
	}

	/// The episode number a title names — "Episode 12", "Ep. 12", "EP12",
	/// "Episode #12", "قسط 12" in either set of digits — or nil.
	public static func number(in title: String) -> Int? {
		let text = western(title).lowercased()
		let pattern = "(?:episode|epi|ep|qist|قسط)\\s*[.#:\\-]?\\s*(\\d{1,4})"
		guard let regex = try? NSRegularExpression(pattern: pattern),
		      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
		      let range = Range(match.range(at: 1), in: text) else { return nil }
		return Int(text[range])
	}

	/// Arabic and Urdu digits as 0–9.
	static func western(_ text: String) -> String {
		String(text.map { character -> Character in
			guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return character }
			switch scalar.value {
			case 0x0660...0x0669: return Character(String(scalar.value - 0x0660))
			case 0x06F0...0x06F9: return Character(String(scalar.value - 0x06F0))
			default: return character
			}
		})
	}

	/// Which video is which episode. Titles decide when most of the playlist
	/// is numbered; a "Last Episode" without a number follows the highest one.
	/// When titles mostly aren't numbered, the oldest upload is episode 1 and
	/// so on. Where two videos claim a number (Part 1 and Part 2, a re-upload),
	/// the earlier upload keeps it.
	public static func match(_ videos: [YouTubeVideo]) -> [Int: YouTubeVideo] {
		let episodes = videos.filter { !isExtra($0.title) }
			.sorted { ($0.publishedAt ?? .distantPast, $0.position) < ($1.publishedAt ?? .distantPast, $1.position) }
		guard !episodes.isEmpty else { return [:] }

		let numbered = episodes.compactMap { video in number(in: video.title).map { ($0, video) } }
		guard numbered.count * 2 >= episodes.count else {
			return Dictionary(uniqueKeysWithValues: episodes.enumerated().map { ($0.offset + 1, $0.element) })
		}
		var byNumber: [Int: YouTubeVideo] = [:]
		for (number, video) in numbered where number > 0 && byNumber[number] == nil { byNumber[number] = video }
		let highest = byNumber.keys.max() ?? 0
		if let last = episodes.first(where: { number(in: $0.title) == nil && isFinale($0.title) }),
		   byNumber[highest + 1] == nil {
			byNumber[highest + 1] = last
		}
		return byNumber
	}

	static func isFinale(_ title: String) -> Bool {
		let lower = title.lowercased()
		return lower.contains("last episode") || lower.contains("final episode") || lower.contains("finale")
	}

	/// Search results with the ones that read like a whole drama first — "Full
	/// Episodes", "All Episodes" — and clips, songs and teasers last; otherwise
	/// YouTube's order.
	public static func ranked(_ results: [YouTubePlaylistResult]) -> [YouTubePlaylistResult] {
		func score(_ result: YouTubePlaylistResult) -> Int {
			let title = result.title.lowercased()
			if isExtra(result.title) { return 0 }
			return ["all episode", "full episode", "episodes", "complete"].contains(where: title.contains) ? 2 : 1
		}
		return results.enumerated().sorted { lhs, rhs in
			let (l, r) = (score(lhs.element), score(rhs.element))
			return l != r ? l > r : lhs.offset < rhs.offset
		}.map(\.element)
	}

	/// A show's name from its playlist's: "Kabhi Main Kabhi Tum - All Episodes |
	/// ARY Digital" reads as "Kabhi Main Kabhi Tum".
	public static func showName(fromPlaylist title: String) -> String {
		var name = title
		for separator in [" | ", " - ", " – ", " — ", " || "] {
			if let range = name.range(of: separator) { name = String(name[..<range.lowerBound]) }
		}
		for suffix in [" All Episodes", " Full Episodes", " Episodes", " Drama Serial", " Drama", " Full Drama"] {
			if name.lowercased().hasSuffix(suffix.lowercased()) { name = String(name.dropLast(suffix.count)) }
		}
		let trimmed = name.trimmingCharacters(in: .whitespaces)
		return trimmed.isEmpty ? title.trimmingCharacters(in: .whitespaces) : trimmed
	}
}
