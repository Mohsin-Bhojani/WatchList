//
//  Jellyfin.swift
//  WatchList
//
//  Your own Jellyfin server, as a source the player can play from. Signing in
//  (Settings) keeps the server and user in UserDefaults and the access token in
//  the Keychain. The server's films and shows are indexed by their TMDb and
//  IMDb ids, so a film or episode page finds its copy without a search; an
//  episode is then found in its show by season and episode number.
//
//  Playing asks the server how (PlaybackInfo, with what an iPhone plays
//  natively): an MP4 or MOV in H.264/HEVC plays as it is, anything else — an
//  MKV, say — is remuxed or transcoded to HLS. Progress goes back to the
//  server as it plays, so Jellyfin keeps the resume point and its own
//  watched marks, and other Jellyfin apps see where you got to.
//
//  Nothing here touches the library's models.
//

import Foundation
import Security
import UIKit

// MARK: - Account

/// The server signed in to. Its token is kept apart, in the Keychain.
struct JellyfinAccount: Codable, Hashable {
	var server: URL
	var serverName: String
	var userID: String
	var userName: String
}

enum JellyfinError: LocalizedError {
	case badServer
	case http(Int)
	case wrongPassword
	case decoding
	case nothingPlayable

	var errorDescription: String? {
		switch self {
		case .badServer:       return "That doesn't look like a server address. Try something like 192.168.1.20:8096."
		case .http(let code):  return "The Jellyfin server answered with an error (HTTP \(code))."
		case .wrongPassword:   return "Jellyfin didn't accept that username and password."
		case .decoding:        return "Couldn't read the Jellyfin server's answer."
		case .nothingPlayable: return "Jellyfin has no playable version of this."
		}
	}
}

enum JellyfinServer {
	/// A typed address as a server URL: "http://" when no scheme is given, and
	/// no trailing slash, so API paths can be added to it. A base path
	/// ("…/jellyfin") is kept.
	static func normalized(_ raw: String) -> URL? {
		var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !text.isEmpty, !text.contains(" ") else { return nil }
		if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
			text = "http://" + text
		}
		while text.hasSuffix("/") { text.removeLast() }
		guard let url = URL(string: text), let host = url.host(), !host.isEmpty else { return nil }
		return url
	}
}

/// The Jellyfin access token, in the Keychain rather than UserDefaults.
enum JellyfinKeychain {
	private static let service = "com.mohsin.WatchList.jellyfin"
	private static let account = "token"

	static var token: String? {
		get {
			let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
			                            kSecAttrService as String: service,
			                            kSecAttrAccount as String: account,
			                            kSecReturnData as String: true,
			                            kSecMatchLimit as String: kSecMatchLimitOne]
			var result: AnyObject?
			guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
			      let data = result as? Data else { return nil }
			return String(data: data, encoding: .utf8)
		}
		set {
			let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
			                            kSecAttrService as String: service,
			                            kSecAttrAccount as String: account]
			SecItemDelete(query as CFDictionary)
			guard let newValue, let data = newValue.data(using: .utf8) else { return }
			var add = query
			add[kSecValueData as String] = data
			add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
			SecItemAdd(add as CFDictionary, nil)
		}
	}
}

// MARK: - Items

/// A film, show or episode on the server — the fields WatchList reads.
struct JellyfinItem: Decodable, Equatable, Identifiable {
	let id: String
	var name: String?
	var type: String?
	var providerIDs: [String: String]?
	/// An episode's number; with `indexNumberEnd`, a double episode's first.
	var indexNumber: Int?
	var indexNumberEnd: Int?
	/// An episode's season number.
	var parentIndexNumber: Int?
	var runTimeTicks: Int64?
	var productionYear: Int?
	var overview: String?
	var userData: UserData?

	struct UserData: Decodable, Equatable {
		var playbackPositionTicks: Int64?
		var played: Bool?

		enum CodingKeys: String, CodingKey {
			case playbackPositionTicks = "PlaybackPositionTicks"
			case played = "Played"
		}
	}

	enum CodingKeys: String, CodingKey {
		case id = "Id", name = "Name", type = "Type", providerIDs = "ProviderIds"
		case indexNumber = "IndexNumber", indexNumberEnd = "IndexNumberEnd"
		case parentIndexNumber = "ParentIndexNumber", runTimeTicks = "RunTimeTicks", userData = "UserData"
		case productionYear = "ProductionYear", overview = "Overview"
	}

	/// A provider's id ("Tmdb", "Imdb"), whatever case the server wrote it in.
	func providerID(_ provider: String) -> String? {
		providerIDs?.first { $0.key.caseInsensitiveCompare(provider) == .orderedSame }?.value
	}

	/// Where it was left, in seconds; nil when it wasn't started.
	var resumeSeconds: TimeInterval? {
		MediaPlayback.resumePoint(position: JellyfinTicks.seconds(userData?.playbackPositionTicks ?? 0),
		                          duration: runTimeTicks.map(JellyfinTicks.seconds))
	}
}

private struct JellyfinItemList: Decodable {
	let items: [JellyfinItem]
	enum CodingKeys: String, CodingKey { case items = "Items" }
}

enum JellyfinTicks {
	/// Jellyfin counts time in ticks of 100 nanoseconds.
	static let perSecond: Double = 10_000_000
	static func seconds(_ ticks: Int64) -> TimeInterval { Double(ticks) / perSecond }
	static func ticks(_ seconds: TimeInterval) -> Int64 { Int64((seconds * perSecond).rounded()) }
}

/// The server's films and shows, by their TMDb and IMDb ids.
struct JellyfinIndex {
	private var movies: [String: JellyfinItem] = [:]
	private var series: [String: JellyfinItem] = [:]
	private(set) var movieCount = 0
	private(set) var seriesCount = 0

	init(items: [JellyfinItem]) {
		for item in items {
			let keys = [item.providerID("Tmdb").map { "tmdb:\($0)" },
			            item.providerID("Imdb").map { "imdb:\($0.lowercased())" }].compactMap { $0 }
			switch item.type {
			case "Movie":
				movieCount += 1
				for key in keys where movies[key] == nil { movies[key] = item }
			case "Series":
				seriesCount += 1
				for key in keys where series[key] == nil { series[key] = item }
			default: break
			}
		}
	}

	func movie(tmdbID: Int?, imdbID: String?) -> JellyfinItem? { Self.find(in: movies, tmdbID, imdbID) }
	func series(tmdbID: Int?, imdbID: String?) -> JellyfinItem? { Self.find(in: series, tmdbID, imdbID) }

	/// TMDb first, as WatchList's own ids are; IMDb for a server whose metadata
	/// came from somewhere else.
	private static func find(in table: [String: JellyfinItem], _ tmdbID: Int?, _ imdbID: String?) -> JellyfinItem? {
		if let tmdbID, let item = table["tmdb:\(tmdbID)"] { return item }
		if let imdbID, !imdbID.isEmpty, let item = table["imdb:\(imdbID.lowercased())"] { return item }
		return nil
	}
}

enum JellyfinEpisodes {
	/// The episode with this season and number; a double episode ("E03–E04")
	/// answers for both of its numbers.
	static func match(_ episodes: [JellyfinItem], season: Int, episode: Int) -> JellyfinItem? {
		episodes.first { item in
			guard item.parentIndexNumber == season, let first = item.indexNumber else { return false }
			return (first...max(first, item.indexNumberEnd ?? first)).contains(episode)
		}
	}
}

// MARK: - Playback info

struct JellyfinPlaybackInfo: Decodable {
	let mediaSources: [Source]
	let playSessionID: String?

	struct Source: Decodable {
		let id: String
		var supportsDirectPlay: Bool?
		var transcodingURL: String?

		enum CodingKeys: String, CodingKey {
			case id = "Id", supportsDirectPlay = "SupportsDirectPlay", transcodingURL = "TranscodingUrl"
		}
	}

	enum CodingKeys: String, CodingKey { case mediaSources = "MediaSources", playSessionID = "PlaySessionId" }
}

enum JellyfinStreams {
	/// What the player gets for a source: the file itself when the iPhone can
	/// play it as it is, otherwise the server's HLS stream. The token goes in
	/// the URL, as AVPlayer can't add Jellyfin's header.
	static func url(server: URL, token: String, itemID: String, source: JellyfinPlaybackInfo.Source,
	                playSessionID: String?) -> (url: URL, method: String)? {
		if source.supportsDirectPlay == true {
			var components = URLComponents(url: server.appending(path: "Videos/\(itemID)/stream"),
			                               resolvingAgainstBaseURL: false)
			components?.queryItems = [URLQueryItem(name: "static", value: "true"),
			                          URLQueryItem(name: "mediaSourceId", value: source.id),
			                          playSessionID.map { URLQueryItem(name: "playSessionId", value: $0) },
			                          URLQueryItem(name: "api_key", value: token)].compactMap { $0 }
			return components?.url.map { ($0, "DirectPlay") }
		}
		guard var path = source.transcodingURL, !path.isEmpty else { return nil }
		let lowered = path.lowercased()
		if !lowered.contains("api_key=") && !lowered.contains("apikey=") {
			path += (path.contains("?") ? "&" : "?") + "api_key=\(token)"
		}
		if !path.hasPrefix("/") { path = "/" + path }
		return URL(string: server.absoluteString + path).map { ($0, "Transcode") }
	}

	/// What an iPhone plays natively. Jellyfin plays what fits a direct-play
	/// profile untouched and turns anything else into fragmented-MP4 HLS,
	/// copying the streams across when they already fit.
	static let deviceProfile: [String: Any] = [
		"Name": "WatchList iPhone",
		"MaxStreamingBitrate": 120_000_000,
		"MaxStaticBitrate": 120_000_000,
		"DirectPlayProfiles": [["Container": "mp4,m4v,mov", "Type": "Video",
		                        "VideoCodec": "h264,hevc", "AudioCodec": "aac,ac3,eac3,mp3,alac,flac"]],
		"TranscodingProfiles": [["Container": "mp4", "Type": "Video", "Protocol": "hls",
		                         "VideoCodec": "h264,hevc", "AudioCodec": "aac,ac3,eac3",
		                         "Context": "Streaming", "MaxAudioChannels": "6", "MinSegments": 1,
		                         "BreakOnNonKeyFrames": true]],
		"SubtitleProfiles": [["Format": "vtt", "Method": "Hls"]],
		"ContainerProfiles": [], "CodecProfiles": [], "ResponseProfiles": [],
	]
}

// MARK: - Session

/// The signed-in server, for Settings, the play buttons and the player.
@Observable
final class JellyfinSession {
	static let shared = JellyfinSession()

	private static let accountKey = "jellyfinAccount"
	private static let deviceIDKey = "jellyfinDeviceID"
	/// How long the index of the server's titles is trusted before it's fetched again.
	private static let indexLifetime: TimeInterval = 10 * 60

	private(set) var account: JellyfinAccount?
	/// The server's titles, once fetched; Settings shows the counts.
	private(set) var index: JellyfinIndex?
	private var token: String?
	private var indexedAt: Date?
	private var indexing: Task<JellyfinIndex, Error>?

	var isSignedIn: Bool { account != nil && token != nil }

	private init() {
		if let data = UserDefaults.standard.data(forKey: Self.accountKey) {
			account = try? JSONDecoder().decode(JellyfinAccount.self, from: data)
		}
		token = JellyfinKeychain.token
	}

	private static var deviceID: String {
		if let id = UserDefaults.standard.string(forKey: deviceIDKey) { return id }
		let id = UUID().uuidString
		UserDefaults.standard.set(id, forKey: deviceIDKey)
		return id
	}

	// MARK: Signing in

	func signIn(server raw: String, userName: String, password: String) async throws {
		guard let server = JellyfinServer.normalized(raw) else { throw JellyfinError.badServer }
		struct PublicInfo: Decodable { let ServerName: String? }
		struct AuthResult: Decodable {
			let AccessToken: String
			let User: User
			struct User: Decodable { let Id: String; let Name: String? }
		}
		let info: PublicInfo = try await request(server: server, token: nil, "System/Info/Public")
		let auth: AuthResult
		do {
			auth = try await request(server: server, token: nil, "Users/AuthenticateByName", method: "POST",
			                         body: ["Username": userName, "Pw": password])
		} catch JellyfinError.http(let code) where code == 401 || code == 400 {
			throw JellyfinError.wrongPassword
		}
		let signedIn = JellyfinAccount(server: server, serverName: info.ServerName ?? server.host() ?? "Jellyfin",
		                               userID: auth.User.Id, userName: auth.User.Name ?? userName)
		JellyfinKeychain.token = auth.AccessToken
		UserDefaults.standard.set(try? JSONEncoder().encode(signedIn), forKey: Self.accountKey)
		token = auth.AccessToken
		account = signedIn
		forgetIndex()
		_ = try? await currentIndex()
	}

	/// Forgets the server here; the token is also ended on the server, if it answers.
	func signOut() {
		if let account, let token {
			Task { try? await send(server: account.server, token: token, "Sessions/Logout") }
		}
		JellyfinKeychain.token = nil
		UserDefaults.standard.removeObject(forKey: Self.accountKey)
		token = nil
		account = nil
		forgetIndex()
	}

	private func forgetIndex() {
		indexing?.cancel()
		indexing = nil
		index = nil
		indexedAt = nil
	}

	// MARK: Finding titles

	/// The server's copy of a film, with its resume point fresh.
	func movie(tmdbID: Int?, imdbID: String?) async -> JellyfinItem? {
		guard let found = try? await currentIndex().movie(tmdbID: tmdbID, imdbID: imdbID) else { return nil }
		return (try? await fresh(found.id)) ?? found
	}

	/// The server's copy of an episode, found in its show by season and number.
	func episode(showTMDbID: Int?, showIMDbID: String?, season: Int, episode: Int) async -> JellyfinItem? {
		guard let account, let token,
		      let series = try? await currentIndex().series(tmdbID: showTMDbID, imdbID: showIMDbID),
		      let list: JellyfinItemList = try? await request(
		          server: account.server, token: token, "Shows/\(series.id)/Episodes",
		          query: ["userId": account.userID, "season": String(season), "fields": "ProviderIds"])
		else { return nil }
		return JellyfinEpisodes.match(list.items, season: season, episode: episode)
	}

	/// Everything of a kind on the server — "Movie" or "Series" — by name, with
	/// what you've watched of it, for the On your server list.
	func items(ofType type: String) async throws -> [JellyfinItem] {
		guard let account, let token else { throw JellyfinError.http(401) }
		let list: JellyfinItemList = try await request(
			server: account.server, token: token, "Items",
			query: ["userId": account.userID, "recursive": "true", "includeItemTypes": type,
			        "fields": "ProviderIds,Overview", "sortBy": "SortName", "sortOrder": "Ascending",
			        "enableImages": "false"])
		return list.items
	}

	/// A show's episodes, every season, in order.
	func episodes(ofSeries seriesID: String) async throws -> [JellyfinItem] {
		guard let account, let token else { throw JellyfinError.http(401) }
		let list: JellyfinItemList = try await request(
			server: account.server, token: token, "Shows/\(seriesID)/Episodes",
			query: ["userId": account.userID, "fields": "ProviderIds,Overview"])
		return list.items
	}

	/// An item's artwork — a poster, or an episode's still. Jellyfin serves
	/// images without the token.
	func imageURL(_ item: JellyfinItem, height: Int = 450) -> String {
		guard let account else { return "" }
		var components = URLComponents(url: account.server.appending(path: "Items/\(item.id)/Images/Primary"),
		                               resolvingAgainstBaseURL: false)
		components?.queryItems = [URLQueryItem(name: "fillHeight", value: String(height)),
		                          URLQueryItem(name: "quality", value: "90")]
		return components?.url?.absoluteString ?? ""
	}

	/// Settings' "Refresh" — the next lookup fetches the index again.
	func refreshIndex() async throws {
		indexedAt = nil
		_ = try await currentIndex()
	}

	private func currentIndex() async throws -> JellyfinIndex {
		if let index, let indexedAt, Date.now.timeIntervalSince(indexedAt) < Self.indexLifetime { return index }
		if let indexing { return try await indexing.value }
		guard let account, let token else { throw JellyfinError.http(401) }
		let task = Task { () throws -> JellyfinIndex in
			let list: JellyfinItemList = try await request(
				server: account.server, token: token, "Items",
				query: ["userId": account.userID, "recursive": "true", "includeItemTypes": "Movie,Series",
				        "fields": "ProviderIds", "enableImages": "false", "enableUserData": "false"])
			return JellyfinIndex(items: list.items)
		}
		indexing = task
		defer { indexing = nil }
		let built = try await task.value
		// Signed out, or into another server, while it was fetching.
		guard self.account == account else { throw CancellationError() }
		index = built
		indexedAt = .now
		return built
	}

	private func fresh(_ itemID: String) async throws -> JellyfinItem? {
		guard let account, let token else { return nil }
		let list: JellyfinItemList = try await request(server: account.server, token: token, "Items",
		                                                query: ["userId": account.userID, "ids": itemID])
		return list.items.first
	}

	// MARK: Playing

	/// A stream of the item for the player, reporting back to the server.
	func stream(for item: JellyfinItem, title: String, subtitle: String?) async throws -> PlayableStream {
		guard let account, let token else { throw JellyfinError.http(401) }
		let body: [String: Any] = ["UserId": account.userID, "MaxStreamingBitrate": 120_000_000,
		                           "EnableDirectPlay": true, "EnableDirectStream": true, "EnableTranscoding": true,
		                           "AllowVideoStreamCopy": true, "AllowAudioStreamCopy": true,
		                           "AutoOpenLiveStream": true, "DeviceProfile": JellyfinStreams.deviceProfile]
		let info: JellyfinPlaybackInfo = try await request(server: account.server, token: token,
		                                                   "Items/\(item.id)/PlaybackInfo", method: "POST",
		                                                   query: ["userId": account.userID], body: body)
		guard let source = info.mediaSources.first,
		      let chosen = JellyfinStreams.url(server: account.server, token: token, itemID: item.id,
		                                       source: source, playSessionID: info.playSessionID)
		else { throw JellyfinError.nothingPlayable }
		let reporter = JellyfinReporter(session: self, itemID: item.id, mediaSourceID: source.id,
		                                playSessionID: info.playSessionID, playMethod: chosen.method)
		return PlayableStream(url: chosen.url, title: title, subtitle: subtitle,
		                      startAt: item.resumeSeconds ?? 0, reporter: reporter)
	}

	/// Tells the server where playback is: "Sessions/Playing", "…/Progress" or "…/Stopped".
	fileprivate func report(_ path: String, _ body: [String: Any]) async {
		guard let account, let token else { return }
		try? await send(server: account.server, token: token, path, body: body)
	}

	// MARK: Networking

	private func authorization(_ token: String?) -> String {
		let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
		var parts = ["Client=\"WatchList\"", "Device=\"\(UIDevice.current.model)\"",
		             "DeviceId=\"\(Self.deviceID)\"", "Version=\"\(version)\""]
		if let token { parts.append("Token=\"\(token)\"") }
		return "MediaBrowser " + parts.joined(separator: ", ")
	}

	private func urlRequest(server: URL, token: String?, _ path: String, method: String,
	                        query: [String: String], body: [String: Any]?) throws -> URLRequest {
		var components = URLComponents(url: server.appending(path: path), resolvingAgainstBaseURL: false)
		if !query.isEmpty {
			components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
		}
		guard let url = components?.url else { throw JellyfinError.badServer }
		var request = URLRequest(url: url, timeoutInterval: 20)
		request.httpMethod = method
		request.setValue(authorization(token), forHTTPHeaderField: "Authorization")
		request.setValue("application/json", forHTTPHeaderField: "Accept")
		if let body {
			request.setValue("application/json", forHTTPHeaderField: "Content-Type")
			request.httpBody = try JSONSerialization.data(withJSONObject: body)
		}
		return request
	}

	private func request<T: Decodable>(server: URL, token: String?, _ path: String, method: String = "GET",
	                                   query: [String: String] = [:], body: [String: Any]? = nil) async throws -> T {
		let (data, response) = try await URLSession.shared.data(
			for: urlRequest(server: server, token: token, path, method: method, query: query, body: body))
		guard let http = response as? HTTPURLResponse else { throw JellyfinError.http(-1) }
		guard (200...299).contains(http.statusCode) else { throw JellyfinError.http(http.statusCode) }
		do { return try JSONDecoder().decode(T.self, from: data) } catch { throw JellyfinError.decoding }
	}

	private func send(server: URL, token: String, _ path: String, body: [String: Any] = [:]) async throws {
		let (_, response) = try await URLSession.shared.data(
			for: urlRequest(server: server, token: token, path, method: "POST", query: [:], body: body))
		if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
			throw JellyfinError.http(http.statusCode)
		}
	}
}

/// Keeps the server told where a playback is, so its resume point and
/// watched marks follow what you watch here.
private final class JellyfinReporter: PlaybackReporter {
	private let session: JellyfinSession
	private let itemID: String
	private let mediaSourceID: String
	private let playSessionID: String?
	private let playMethod: String

	init(session: JellyfinSession, itemID: String, mediaSourceID: String, playSessionID: String?, playMethod: String) {
		self.session = session
		self.itemID = itemID
		self.mediaSourceID = mediaSourceID
		self.playSessionID = playSessionID
		self.playMethod = playMethod
	}

	private func body(_ seconds: TimeInterval, paused: Bool = false) -> [String: Any] {
		var body: [String: Any] = ["ItemId": itemID, "MediaSourceId": mediaSourceID,
		                           "PositionTicks": JellyfinTicks.ticks(seconds), "IsPaused": paused,
		                           "PlayMethod": playMethod, "CanSeek": true]
		if let playSessionID { body["PlaySessionId"] = playSessionID }
		return body
	}

	func started(at seconds: TimeInterval) async { await session.report("Sessions/Playing", body(seconds)) }
	func progress(at seconds: TimeInterval, paused: Bool) async {
		await session.report("Sessions/Playing/Progress", body(seconds, paused: paused))
	}
	func stopped(at seconds: TimeInterval) async { await session.report("Sessions/Playing/Stopped", body(seconds)) }
}
