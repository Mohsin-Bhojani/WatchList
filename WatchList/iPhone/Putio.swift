//
//  Putio.swift
//  WatchList
//
//  Your put.io account, as a second source the player can play from. You
//  connect it (Settings) with the OAuth token put.io gives your own app; it's
//  kept in the Keychain. put.io turns any video into HLS the iPhone plays, with
//  subtitles, and keeps where you stopped in each file.
//
//  put.io holds plain files and knows nothing about shows, so you link them:
//  a show to a folder, whose videos are sorted into episodes by the S01E03 in
//  their names (in season folders or not), and a film to a file. Links are
//  kept here by the title's own id, in UserDefaults — the library's models
//  aren't touched.
//

import Foundation

// MARK: - Files

/// A file or folder in put.io.
struct PutioFile: Decodable, Identifiable, Hashable {
	let id: Int
	var name: String
	/// "FOLDER", "VIDEO", "AUDIO", "IMAGE", …
	var fileType: String?
	var parentID: Int?
	var size: Int64?
	/// A frame from a video, for its artwork.
	var screenshot: String?

	var isFolder: Bool { fileType == "FOLDER" }
	var isVideo: Bool { fileType == "VIDEO" }

	enum CodingKeys: String, CodingKey {
		case id, name, size, screenshot
		case fileType = "file_type", parentID = "parent_id"
	}
}

enum PutioError: LocalizedError {
	case badToken
	case http(Int)
	case decoding

	var errorDescription: String? {
		switch self {
		case .badToken:       return "put.io didn't accept that token. Copy it again from your OAuth app's page on put.io."
		case .http(let code): return "put.io answered with an error (HTTP \(code))."
		case .decoding:       return "Couldn't read put.io's answer."
		}
	}
}

/// Which episode a file is, from its name.
struct EpisodeNumber: Equatable {
	let season: Int
	let first: Int
	/// A double episode's last; `first` otherwise.
	let last: Int

	func contains(season: Int, episode: Int) -> Bool {
		self.season == season && (first...last).contains(episode)
	}
}

enum PutioEpisodes {
	/// "Show.S01E03.1080p", "show s1e3", "Show S02E05-E06", "Show 1x03" —
	/// nil for a name without an episode in it.
	static func number(in name: String) -> EpisodeNumber? {
		let patterns = [#"(?i)s(\d{1,2})[ ._-]?e(\d{1,3})(?:[ ._-]?-?[ ._-]?e(\d{1,3}))?"#,
		                #"(?<![\d])(\d{1,2})x(\d{2,3})(?![\d])"#]
		for pattern in patterns {
			guard let regex = try? NSRegularExpression(pattern: pattern),
			      let match = regex.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) else { continue }
			func group(_ i: Int) -> Int? {
				guard i < match.numberOfRanges, let range = Range(match.range(at: i), in: name) else { return nil }
				return Int(name[range])
			}
			guard let season = group(1), let first = group(2) else { continue }
			return EpisodeNumber(season: season, first: first, last: max(first, group(3) ?? first))
		}
		return nil
	}

	/// The video for an episode, among a linked folder's.
	static func match(_ files: [PutioFile], season: Int, episode: Int) -> PutioFile? {
		files.first { number(in: $0.name)?.contains(season: season, episode: episode) == true }
	}
}

// MARK: - Links

/// A title's put.io file or folder.
struct PutioLink: Codable, Hashable {
	let fileID: Int
	let name: String
	let isFolder: Bool
}

/// Which shows and films are linked to what, by the title's own id.
@Observable
final class PutioLinks {
	static let shared = PutioLinks()
	private static let key = "putioLinks"

	private(set) var links: [UUID: PutioLink] = [:]

	private init() {
		if let data = UserDefaults.standard.data(forKey: Self.key),
		   let stored = try? JSONDecoder().decode([UUID: PutioLink].self, from: data) {
			links = stored
		}
	}

	func link(_ titleID: UUID) -> PutioLink? { links[titleID] }

	func set(_ link: PutioLink?, for titleID: UUID) {
		links[titleID] = link
		UserDefaults.standard.set(try? JSONEncoder().encode(links), forKey: Self.key)
	}
}

// MARK: - Session

@Observable
final class PutioSession {
	static let shared = PutioSession()

	private static let userKey = "putioUser"
	private static let base = URL(string: "https://api.put.io/v2")!
	private static let folderLifetime: TimeInterval = 10 * 60

	/// The account's username, while connected.
	private(set) var userName: String?
	private var token: String?
	/// A linked show folder's videos, and when they were listed.
	private var folderVideos: [Int: (files: [PutioFile], at: Date)] = [:]

	var isConnected: Bool { userName != nil && token != nil }

	private init() {
		token = PutioKeychain.token
		userName = token == nil ? nil : UserDefaults.standard.string(forKey: Self.userKey)
	}

	// MARK: Connecting

	func connect(token raw: String) async throws {
		let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		struct Info: Decodable { let info: User; struct User: Decodable { let username: String? } }
		let info: Info
		do {
			info = try await get("account/info", token: candidate)
		} catch PutioError.http(let code) where code == 401 || code == 400 {
			throw PutioError.badToken
		}
		PutioKeychain.token = candidate
		UserDefaults.standard.set(info.info.username ?? "put.io", forKey: Self.userKey)
		token = candidate
		userName = info.info.username ?? "put.io"
		folderVideos = [:]
	}

	func disconnect() {
		PutioKeychain.token = nil
		UserDefaults.standard.removeObject(forKey: Self.userKey)
		token = nil
		userName = nil
		folderVideos = [:]
	}

	// MARK: Files

	/// A folder's files, folders first, then by name. 0 is the account's top.
	func files(in folderID: Int) async throws -> [PutioFile] {
		struct Page: Decodable { let files: [PutioFile]; let cursor: String? }
		var page: Page = try await get("files/list", query: ["parent_id": String(folderID), "per_page": "500"])
		var files = page.files
		while let cursor = page.cursor, !cursor.isEmpty {
			page = try await post("files/list/continue", form: ["cursor": cursor, "per_page": "500"])
			files += page.files
		}
		return files.sorted { a, b in
			if a.isFolder != b.isFolder { return a.isFolder }
			return a.name.localizedStandardCompare(b.name) == .orderedAscending
		}
	}

	/// Every video in a folder and the folders in it, three deep — a show
	/// folder with a folder per season, or per episode.
	func videos(under folderID: Int) async throws -> [PutioFile] {
		if let cached = folderVideos[folderID], Date.now.timeIntervalSince(cached.at) < Self.folderLifetime {
			return cached.files
		}
		var found: [PutioFile] = []
		var level = [folderID]
		for _ in 0..<3 where !level.isEmpty {
			var next: [Int] = []
			for folder in level {
				let files = try await files(in: folder)
				found += files.filter(\.isVideo)
				next += files.filter(\.isFolder).map(\.id)
			}
			level = next
		}
		folderVideos[folderID] = (found, .now)
		return found
	}

	/// The video linked to a film — a file, or the biggest video in a folder.
	func filmVideo(_ link: PutioLink) async throws -> PutioFile? {
		guard link.isFolder else { return PutioFile(id: link.fileID, name: link.name, fileType: "VIDEO") }
		return try await videos(under: link.fileID).max { ($0.size ?? 0) < ($1.size ?? 0) }
	}

	/// The episode's video in a show's linked folder.
	func episodeVideo(_ link: PutioLink, season: Int, episode: Int) async throws -> PutioFile? {
		PutioEpisodes.match(try await videos(under: link.fileID), season: season, episode: episode)
	}

	/// Where you stopped in a video, in seconds; nil from the start.
	func startFrom(_ file: PutioFile) async -> TimeInterval? {
		struct Start: Decodable { let start_from: Int? }
		guard let start: Start = try? await get("files/\(file.id)/start-from"),
		      let seconds = start.start_from, seconds >= 30 else { return nil }
		return TimeInterval(seconds)
	}

	// MARK: Playing

	/// put.io's HLS stream of a video — any video, turned into what the iPhone
	/// plays — with subtitles in your put.io languages.
	func stream(for file: PutioFile, title: String, subtitle: String?) async throws -> PlayableStream {
		guard let token else { throw PutioError.badToken }
		var components = URLComponents(url: Self.base.appending(path: "files/\(file.id)/hls/media.m3u8"),
		                               resolvingAgainstBaseURL: false)
		components?.queryItems = [URLQueryItem(name: "subtitle_key", value: "all"),
		                          URLQueryItem(name: "oauth_token", value: token)]
		guard let url = components?.url else { throw PutioError.http(-1) }
		return PlayableStream(url: url, title: title, subtitle: subtitle, startAt: await startFrom(file) ?? 0,
		                      reporter: PutioReporter(session: self, fileID: file.id))
	}

	fileprivate func saveStart(_ seconds: TimeInterval, fileID: Int) async {
		let _: EmptyReply? = try? await post("files/\(fileID)/start-from", form: ["time": String(Int(seconds))])
	}

	fileprivate func clearStart(fileID: Int) async {
		let _: EmptyReply? = try? await post("files/\(fileID)/start-from/delete", form: [:])
	}

	// MARK: Networking

	private struct EmptyReply: Decodable {}

	private func url(_ path: String, token: String?, query: [String: String]) throws -> URL {
		var components = URLComponents(url: Self.base.appending(path: path), resolvingAgainstBaseURL: false)
		var items = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
		if let token { items.append(URLQueryItem(name: "oauth_token", value: token)) }
		components?.queryItems = items
		guard let url = components?.url else { throw PutioError.http(-1) }
		return url
	}

	private func get<T: Decodable>(_ path: String, token: String? = nil, query: [String: String] = [:]) async throws -> T {
		let request = URLRequest(url: try url(path, token: token ?? self.token, query: query), timeoutInterval: 20)
		return try await send(request)
	}

	private func post<T: Decodable>(_ path: String, form: [String: String]) async throws -> T {
		var request = URLRequest(url: try url(path, token: token, query: [:]), timeoutInterval: 20)
		request.httpMethod = "POST"
		request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
		var body = URLComponents()
		body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
		request.httpBody = body.percentEncodedQuery?.data(using: .utf8)
		return try await send(request)
	}

	private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
		let (data, response) = try await URLSession.shared.data(for: request)
		guard let http = response as? HTTPURLResponse else { throw PutioError.http(-1) }
		guard (200...299).contains(http.statusCode) else { throw PutioError.http(http.statusCode) }
		do { return try JSONDecoder().decode(T.self, from: data) } catch { throw PutioError.decoding }
	}
}

/// Keeps put.io's resume point in step with the player; watched through, it's
/// cleared, so the next play starts from the top.
private final class PutioReporter: PlaybackReporter {
	private let session: PutioSession
	private let fileID: Int
	private var lastSaved: TimeInterval = -1

	init(session: PutioSession, fileID: Int) {
		self.session = session
		self.fileID = fileID
	}

	func started(at seconds: TimeInterval) async {}

	/// Every ten seconds from the player; put.io is told every thirty.
	func progress(at seconds: TimeInterval, paused: Bool) async {
		guard abs(seconds - lastSaved) >= 30 else { return }
		lastSaved = seconds
		await session.saveStart(seconds, fileID: fileID)
	}

	func stopped(at seconds: TimeInterval, watched: Bool) async {
		if watched {
			await session.clearStart(fileID: fileID)
		} else if seconds >= 30 {
			await session.saveStart(seconds, fileID: fileID)
		}
	}
}

/// The put.io token, in the Keychain beside Jellyfin's.
enum PutioKeychain {
	private static let service = "com.mohsin.WatchList.putio"

	static var token: String? {
		get { KeychainItem.read(service: service) }
		set { KeychainItem.write(newValue, service: service) }
	}
}
