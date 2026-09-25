//
//  FriendShare.swift
//  WatchList
//
//  Share with friends, without a server: a title travels as a watchlist://
//  link, a collection as a .watchlist file, through Messages, AirDrop, mail or
//  anything else that carries them. Both hold the same things — each title by
//  its TMDb (and IMDb) id with its name and year, and the sender's verdict,
//  stars and note — and the other person's WatchList opens either one to a
//  preview (IncomingShareSheet) that can add it to their library.
//
//  What arrives is only ever shown as the sender's opinion; nothing in it is
//  written into the other person's own ratings.
//

import SwiftUI
import UniformTypeIdentifiers

/// One title as it travels: enough to find it on TMDb, and the sender's take.
struct SharedTitle: Codable, Equatable, Identifiable {
	var kind: MediaKind
	var tmdbID: Int?
	var imdbID: String?
	var title: String
	var year: String
	var verdict: String?
	var stars: Double?
	var note: String?

	var id: String { "\(kind.rawValue)-\(tmdbID.map(String.init) ?? imdbID ?? title)" }

	/// Whether there's an id to add it to a library by.
	var canBeAdded: Bool { tmdbID != nil || imdbID != nil }
}

extension SharedTitle {
	init(film: Film) {
		self.init(kind: .film, tmdbID: film.tmdbID, imdbID: film.imdbID, title: film.title, year: film.year,
		          verdict: film.rating?.rawValue, stars: film.rating == nil ? nil : film.shownStars,
		          note: film.notes.isEmpty ? nil : film.notes)
	}

	init(show: Show) {
		self.init(kind: .show, tmdbID: show.tmdbID, imdbID: show.imdbID, title: show.title,
		          year: show.firstAirYear, verdict: show.rating?.rawValue,
		          stars: show.rating == nil ? nil : show.shownStars, note: show.notes.isEmpty ? nil : show.notes)
	}

	init(_ item: WatchedTitle) {
		switch item {
		case .show(let show): self.init(show: show)
		case .film(let film): self.init(film: film)
		}
	}
}

/// A collection as it travels, in the file.
struct SharedCollection: Codable, Equatable {
	/// Bumped if the file's shape ever changes, so an older app can say so.
	var version = 1
	var name: String
	var from: String?
	var titles: [SharedTitle]
}

/// What the app was asked to open.
enum IncomingShare: Identifiable, Equatable {
	case title(SharedTitle, from: String?)
	case collection(SharedCollection)

	var id: String {
		switch self {
		case .title(let title, _): return "title-\(title.id)"
		case .collection(let collection): return "collection-\(collection.name)-\(collection.titles.count)"
		}
	}
}

extension UTType {
	/// A shared collection, declared in the iPhone app's Info.plist.
	static let watchListCollection = UTType(exportedAs: "com.mohsin.watchlist.collection", conformingTo: .json)
}

enum FriendShare {
	static let scheme = "watchlist"
	static let fileExtension = "watchlist"

	/// The sender's nickname, when they've set one on their profile.
	@MainActor static var senderName: String? {
		let name = ProfileStore.shared.nickname
		return name.isEmpty ? nil : name
	}

	// MARK: Links

	/// watchlist://title?kind=film&tmdb=27205&title=Inception&year=2010&verdict=…
	static func link(for title: SharedTitle, from sender: String?) -> URL? {
		var components = URLComponents()
		components.scheme = scheme
		components.host = "title"
		let items: [(String, String?)] = [
			("kind", title.kind == .film ? "film" : "show"),
			("tmdb", title.tmdbID.map(String.init)),
			("imdb", title.imdbID),
			("title", title.title),
			("year", title.year.isEmpty ? nil : title.year),
			("verdict", title.verdict),
			("stars", title.stars.map { StarRating.label($0) }),
			("note", title.note),
			("from", sender),
		]
		components.queryItems = items.compactMap { name, value in value.map { URLQueryItem(name: name, value: $0) } }
		return components.url
	}

	/// The words that go with a link: what it is, the sender's take, and the link.
	static func message(for title: SharedTitle, link: URL) -> String {
		var lines = [title.year.isEmpty ? title.title : "\(title.title) (\(title.year))"]
		if let verdict = title.verdict {
			lines.append([verdict, title.stars.map { "\(StarRating.label($0)) stars" }]
				.compactMap { $0 }.joined(separator: " · "))
		}
		if let note = title.note { lines.append("\u{201C}\(note)\u{201D}") }
		lines.append("Open in WatchList: \(link.absoluteString)")
		return lines.joined(separator: "\n")
	}

	/// What the app was opened with: one of its links, or a collection file.
	static func incoming(from url: URL) -> IncomingShare? {
		if url.scheme == scheme { return title(from: url) }
		if url.isFileURL, url.pathExtension.lowercased() == fileExtension {
			let scoped = url.startAccessingSecurityScopedResource()
			defer { if scoped { url.stopAccessingSecurityScopedResource() } }
			return (try? Data(contentsOf: url)).flatMap(collection(from:)).map(IncomingShare.collection)
		}
		return nil
	}

	static func title(from url: URL) -> IncomingShare? {
		guard url.scheme == scheme, url.host == "title",
		      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return nil }
		func value(_ name: String) -> String? {
			items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 }
		}
		guard let name = value("title") else { return nil }
		let kind: MediaKind = value("kind") == "show" ? .show : .film
		let stars = value("stars").flatMap(Double.init).map { min(max(($0 * 2).rounded() / 2, 0.5), 5) }
		let shared = SharedTitle(kind: kind, tmdbID: value("tmdb").flatMap(Int.init),
		                         imdbID: value("imdb").flatMap(IMDb.id(from:)), title: String(name.prefix(200)),
		                         year: String((value("year") ?? "").prefix(4)),
		                         verdict: value("verdict").flatMap { Rating(rawValue: $0)?.rawValue },
		                         stars: stars, note: value("note").map { String($0.prefix(2000)) })
		return .title(shared, from: value("from").map { String($0.prefix(ProfileStore.maxNicknameLength)) })
	}

	// MARK: Files

	static func data(for collection: SharedCollection) throws -> Data {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		return try encoder.encode(collection)
	}

	static func collection(from data: Data) -> SharedCollection? {
		guard let decoded = try? JSONDecoder().decode(SharedCollection.self, from: data), decoded.version == 1
		else { return nil }
		return decoded
	}

	/// "Weekend.watchlist", safe as a file name.
	static func fileName(for name: String) -> String {
		let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
			.trimmingCharacters(in: .whitespacesAndNewlines)
		return (cleaned.isEmpty ? "Collection" : cleaned) + "." + fileExtension
	}
}

/// A collection handed to the share sheet as a .watchlist file, written only
/// when something takes it.
struct SharedCollectionFile: Transferable {
	let collection: SharedCollection

	static var transferRepresentation: some TransferRepresentation {
		FileRepresentation(exportedContentType: .watchListCollection) { file in
			let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
			try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
			let url = folder.appendingPathComponent(FriendShare.fileName(for: file.collection.name))
			try FriendShare.data(for: file.collection).write(to: url, options: .atomic)
			return SentTransferredFile(url)
		}
	}
}
