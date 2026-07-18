//
//  IMDbTriviaService.swift
//  WatchList
//
//  Best-effort IMDb *trivia* scraper. TMDb does not expose trivia, so this is
//  the one place where we read directly from imdb.com.
//
//  ⚠️ IMPORTANT: IMDb has no official public API and its HTML/JSON layout can
//  change at any time. This scraper is intentionally defensive — it parses the
//  embedded `__NEXT_DATA__` JSON island and degrades gracefully (returns an
//  empty list) whenever the structure isn't what we expect, rather than
//  crashing. Trivia is therefore a "best-effort" feature.
//

import Foundation

struct IMDbTriviaService {
	static let shared = IMDbTriviaService()
	private let session = URLSession.shared

	/// Fetch up to `limit` trivia items for an IMDb title id (movie or episode).
	func trivia(imdbID: String, limit: Int = 20) async -> [String] {
		guard let url = URL(string: "https://www.imdb.com/title/\(imdbID)/trivia/") else { return [] }
		var request = URLRequest(url: url)
		// A desktop UA tends to return the server-rendered __NEXT_DATA__ payload.
		request.setValue(
			"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
			forHTTPHeaderField: "User-Agent")
		request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")

		do {
			let (data, response) = try await session.data(for: request)
			guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
			      let html = String(data: data, encoding: .utf8) else { return [] }
			return parse(html: html, limit: limit)
		} catch {
			return []
		}
	}

	// MARK: - Parsing

	private func parse(html: String, limit: Int) -> [String] {
		guard let json = extractNextDataJSON(from: html),
		      let data = json.data(using: .utf8),
		      let root = try? JSONSerialization.jsonObject(with: data) else {
			return []
		}

		var collected: [String] = []
		collectTriviaText(from: root, into: &collected)

		// Clean up, de-duplicate, and trim to a sensible number of facts.
		var seen = Set<String>()
		var result: [String] = []
		for raw in collected {
			let text = raw
				.replacingOccurrences(of: "\\n", with: " ")
				.trimmingCharacters(in: .whitespacesAndNewlines)
			guard text.count >= 25 else { continue }   // skip stray short strings
			if seen.contains(text) { continue }
			seen.insert(text)
			result.append(text)
			if result.count >= limit { break }
		}
		return result
	}

	/// Pull the JSON contained in <script id="__NEXT_DATA__" ...>{ ... }</script>.
	private func extractNextDataJSON(from html: String) -> String? {
		guard let scriptRange = html.range(of: "id=\"__NEXT_DATA__\"") else { return nil }
		guard let openBrace = html.range(of: "{", range: scriptRange.upperBound..<html.endIndex) else { return nil }
		// Walk forward balancing braces to find the matching close brace.
		var depth = 0
		var inString = false
		var escaped = false
		var endIndex: String.Index? = nil
		var i = openBrace.lowerBound
		while i < html.endIndex {
			let c = html[i]
			if escaped { escaped = false }
			else if c == "\\" { escaped = true }
			else if c == "\"" { inString.toggle() }
			else if !inString {
				if c == "{" { depth += 1 }
				else if c == "}" {
					depth -= 1
					if depth == 0 { endIndex = html.index(after: i); break }
				}
			}
			i = html.index(after: i)
		}
		guard let end = endIndex else { return nil }
		return String(html[openBrace.lowerBound..<end])
	}

	/// Recursively gather trivia text. IMDb's GraphQL trivia nodes look like:
	///   { "text": { "plainText": "...", "plaidHtml": "..." }, ... }
	/// so we collect every `text.plainText` we encounter on this page.
	private func collectTriviaText(from any: Any, into result: inout [String]) {
		if let dict = any as? [String: Any] {
			if let textNode = dict["text"] as? [String: Any],
			   let plain = textNode["plainText"] as? String, !plain.isEmpty {
				result.append(plain)
			}
			for (_, value) in dict { collectTriviaText(from: value, into: &result) }
		} else if let arr = any as? [Any] {
			for value in arr { collectTriviaText(from: value, into: &result) }
		}
	}
}
