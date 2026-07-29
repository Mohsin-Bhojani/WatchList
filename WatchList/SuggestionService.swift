//
//  SuggestionService.swift
//  WatchList
//
//  Talks to the Mac helper that holds the Anthropic API key (see
//  ~/bin/watchlist-similar-proxy.py). The key deliberately never ships in the
//  app, so the app is useless to anyone who extracts the binary.
//
//  Stateless value type doing I/O, mirroring TMDbService; the @MainActor half
//  that writes models lives in SimilarLoader, mirroring TriviaLoader.
//

import Foundation

// MARK: - Config

enum SimilarConfig {
	/// Loopback works from the Simulator (it shares the Mac's network stack).
	/// A device needs the Mac's Wi-Fi address — set in Settings.
	static var host: String {
		UserDefaults.standard.string(forKey: "similarProxyHost") ?? "127.0.0.1"
	}
	static var port: Int {
		let p = UserDefaults.standard.integer(forKey: "similarProxyPort")
		return p > 0 ? p : 8787
	}
	/// Only required when the helper is bound wide (0.0.0.0) for device use.
	static var token: String {
		UserDefaults.standard.string(forKey: "similarProxyToken") ?? ""
	}

	static var isConfigured: Bool { !host.trimmingCharacters(in: .whitespaces).isEmpty && port > 0 }

	static var displayAddress: String { "\(host):\(port)" }

	static func url(path: String) -> URL? {
		var components = URLComponents()
		components.scheme = "http"
		components.host = host.trimmingCharacters(in: .whitespaces)
		components.port = port
		components.path = path
		return components.url
	}
}

// MARK: - Wire types

struct TasteTitleDTO: Encodable {
	let title: String
	let year: String
	let kind: String        // "show" / "film" — lowercase on the wire, unlike MediaKind.rawValue
	let genre: String?
}

struct TasteProfileDTO: Encodable {
	let perfection: [TasteTitleDTO]
	let goForIt: [TasteTitleDTO]
	let avoid: [TasteTitleDTO]
}

private struct SuggestRequest: Encodable {
	let version = 1
	let count: Int
	let profile: TasteProfileDTO
	let exclude: [String]
}

struct SuggestionDTO: Decodable {
	let title: String
	let year: String
	let kind: String
	let reason: String

	var mediaKind: MediaKind { kind == "show" ? .show : .film }
}

private struct SuggestResponse: Decodable {
	let suggestions: [SuggestionDTO]?
	let error: ProxyErrorBody?

	struct ProxyErrorBody: Decodable {
		let type: String
		let message: String
	}
}

// MARK: - Errors

enum SuggestionError: LocalizedError {
	case notConfigured
	case unreachable
	case http(Int)
	case proxy(String)
	case decoding

	var errorDescription: String? {
		switch self {
		case .notConfigured:
			return "Set your Mac's address in Settings first."
		case .unreachable:
			return "Couldn't reach your Mac at \(SimilarConfig.displayAddress). Is the helper running?"
		case .http(let code):
			return "Your Mac's helper returned an error (\(code))."
		case .proxy(let message):
			return message
		case .decoding:
			return "Couldn't read the response from your Mac."
		}
	}
}

// MARK: - Service

struct SuggestionService {
	static let shared = SuggestionService()

	/// Short-timeout session: a sleeping Mac should fail fast, not park the UI.
	/// `waitsForConnectivity = false` is set explicitly for that reason.
	private var session: URLSession {
		let config = URLSessionConfiguration.ephemeral
		config.waitsForConnectivity = false
		config.timeoutIntervalForRequest = 90
		config.timeoutIntervalForResource = 120
		return URLSession(configuration: config)
	}

	/// Cheap reachability probe so the tab can fall back to cache in ~2s
	/// instead of hanging for the full request timeout.
	func health() async -> Bool {
		guard SimilarConfig.isConfigured, let url = SimilarConfig.url(path: "/health") else { return false }

		let config = URLSessionConfiguration.ephemeral
		config.waitsForConnectivity = false
		config.timeoutIntervalForRequest = 2
		config.timeoutIntervalForResource = 3

		var request = URLRequest(url: url)
		request.timeoutInterval = 2

		guard let (_, response) = try? await URLSession(configuration: config).data(for: request),
		      let http = response as? HTTPURLResponse else { return false }
		return (200...299).contains(http.statusCode)
	}

	func suggest(profile: TasteProfileDTO, exclude: [String], count: Int) async throws -> [SuggestionDTO] {
		guard SimilarConfig.isConfigured, let url = SimilarConfig.url(path: "/similar") else {
			throw SuggestionError.notConfigured
		}

		var request = URLRequest(url: url)
		request.httpMethod = "POST"
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		let token = SimilarConfig.token
		if !token.isEmpty {
			request.setValue(token, forHTTPHeaderField: "X-WatchList-Token")
		}
		request.httpBody = try? JSONEncoder().encode(
			SuggestRequest(count: count, profile: profile, exclude: exclude)
		)

		let data: Data
		let response: URLResponse
		do {
			(data, response) = try await session.data(for: request)
		} catch {
			throw SuggestionError.unreachable
		}

		guard let http = response as? HTTPURLResponse else { throw SuggestionError.unreachable }

		// The helper reports its own failures in the body, so decode before
		// judging by status code — its message is more useful than the number.
		let decoded = try? JSONDecoder().decode(SuggestResponse.self, from: data)
		if let message = decoded?.error?.message {
			throw SuggestionError.proxy(message)
		}
		guard (200...299).contains(http.statusCode) else {
			throw SuggestionError.http(http.statusCode)
		}
		guard let suggestions = decoded?.suggestions else {
			throw SuggestionError.decoding
		}
		return suggestions
	}
}
