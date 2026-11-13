//
//  ReviewText.swift
//  WatchListCore
//
//  TMDb's reviews as plain reading: the HTML and Markdown people write them
//  in taken out, their paragraphs kept, and who wrote them, when and how
//  they scored it put the way the app says things.
//

import Foundation

public enum ReviewText {
	/// The review's words alone: tags and Markdown emphasis gone, paragraphs
	/// kept, never more than one blank line between them.
	public static func cleaned(_ raw: String) -> String {
		var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
			.replacingOccurrences(of: "\r", with: "\n")
		// <br> and </p> end a line; every other tag just goes.
		text = text.replacingOccurrences(of: "<br\\s*/?>|</p>", with: "\n", options: [.regularExpression, .caseInsensitive])
		text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
		// Markdown links keep their words: [text](url) → text.
		text = text.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
		for mark in ["**", "__"] { text = text.replacingOccurrences(of: mark, with: "") }
		text = text.replacingOccurrences(of: "&amp;", with: "&")
			.replacingOccurrences(of: "&quot;", with: "\"")
			.replacingOccurrences(of: "&#39;", with: "'")
			.replacingOccurrences(of: "&nbsp;", with: " ")
		text = text.replacingOccurrences(of: "[ \\t]+\n", with: "\n", options: .regularExpression)
		text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
		return text.trimmingCharacters(in: .whitespacesAndNewlines)
	}

	/// Their name, else their username, else "A TMDb user".
	public static func author(_ review: TMDbReview) -> String {
		for candidate in [review.author_details?.name, review.author, review.author_details?.username] {
			if let name = candidate?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
		}
		return "A TMDb user"
	}

	/// Their score as the app's stars: out of five, to the half.
	public static func stars(_ review: TMDbReview) -> Double? {
		guard let rating = review.author_details?.rating, rating > 0 else { return nil }
		return (min(rating, 10)).rounded() / 2
	}

	/// When it was written, from TMDb's timestamp.
	public static func date(_ review: TMDbReview) -> Date? {
		guard let raw = review.created_at else { return nil }
		let withFraction = ISO8601DateFormatter()
		withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		return withFraction.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
	}

	/// The reviews worth showing, in TMDb's order: the empty ones dropped.
	public static func readable(_ reviews: [TMDbReview]) -> [TMDbReview] {
		reviews.filter { !cleaned($0.content ?? "").isEmpty }
	}
}
