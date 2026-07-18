//
//  Sharing.swift
//  WatchList
//
//  Local device-to-device sharing over WiFi (MultipeerConnectivity). You share
//  only the titles you've *watched*; a nearby device stores your list as a
//  separate, browse-only copy (see SharedLibrary) and can adopt any title into
//  its own library.
//
//  This file holds the wire format (LibrarySnapshot / SharedTitle) and the
//  received-copy model (SharedLibrary). The transport is in PeerSyncService and
//  the UI in NearbyView.
//

import Foundation
import SwiftData

// MARK: - Wire format (Codable, sent over the session)

/// One watched title, with enough to browse it and to re-fetch it on adopt.
struct SharedTitle: Codable, Identifiable, Hashable {
	var id: String          // stable key: "tmdb:show:123" / "imdb:film:tt.." / "manual:<uuid>"
	var kind: String         // MediaKind.rawValue
	var tmdbID: Int?
	var imdbID: String?
	var title: String
	var year: String
	var genre: String
	var posterURL: String
	var rating: String?      // Rating.rawValue (the sender's verdict)
	var posterData: Data?    // manual posters travel inline; TMDb posters re-load by URL

	var mediaKind: MediaKind { MediaKind(rawValue: kind) ?? .film }
	var ratingValue: Rating? { rating.flatMap(Rating.init(rawValue:)) }

	static func key(kind: MediaKind, tmdbID: Int?, imdbID: String?, uuid: UUID) -> String {
		if let tmdbID { return "tmdb:\(kind.rawValue):\(tmdbID)" }
		if let imdbID, !imdbID.isEmpty { return "imdb:\(kind.rawValue):\(imdbID)" }
		return "manual:\(uuid.uuidString)"
	}

	private static func manualPoster(_ posterURL: String, tmdbID: Int?, imdbID: String?) -> Data? {
		guard tmdbID == nil, (imdbID ?? "").isEmpty,
		      posterURL.hasPrefix("file:"), let url = URL(string: posterURL) else { return nil }
		return try? Data(contentsOf: url)
	}

	init(show s: Show) {
		self.id = SharedTitle.key(kind: .show, tmdbID: s.tmdbID, imdbID: s.imdbID, uuid: s.id)
		self.kind = MediaKind.show.rawValue
		self.tmdbID = s.tmdbID
		self.imdbID = s.imdbID
		self.title = s.title
		self.year = s.firstAirYear
		self.genre = s.genre
		self.posterURL = s.posterURL
		self.rating = s.rating?.rawValue
		self.posterData = SharedTitle.manualPoster(s.posterURL, tmdbID: s.tmdbID, imdbID: s.imdbID)
	}

	init(film f: Film) {
		self.id = SharedTitle.key(kind: .film, tmdbID: f.tmdbID, imdbID: f.imdbID, uuid: f.id)
		self.kind = MediaKind.film.rawValue
		self.tmdbID = f.tmdbID
		self.imdbID = f.imdbID
		self.title = f.title
		self.year = f.year
		self.genre = f.genre
		self.posterURL = f.posterURL
		self.rating = f.rating?.rawValue
		self.posterData = SharedTitle.manualPoster(f.posterURL, tmdbID: f.tmdbID, imdbID: f.imdbID)
	}
}

/// The whole payload one device sends another: its watched titles.
struct LibrarySnapshot: Codable {
	var ownerName: String
	var generatedAt: Date
	var titles: [SharedTitle]

	/// Build from the local library — watched Shows and Films only.
	@MainActor static func build(ownerName: String, context: ModelContext) -> LibrarySnapshot {
		let shows = (try? context.fetch(FetchDescriptor<Show>())) ?? []
		let films = (try? context.fetch(FetchDescriptor<Film>())) ?? []
		var titles: [SharedTitle] = []
		titles += shows.filter { $0.status == .watched }.map(SharedTitle.init(show:))
		titles += films.filter { $0.status == .watched }.map(SharedTitle.init(film:))
		return LibrarySnapshot(ownerName: ownerName, generatedAt: .now, titles: titles)
	}
}

// MARK: - Received copy (local model, one per peer)

/// A browse-only copy of another device's watched list, stored locally and
/// refreshed whenever that device shares again.
@Model
final class SharedLibrary {
	var peerID: String = ""      // stable peer identity, so re-shares replace in place
	var ownerName: String = ""
	var receivedAt: Date = Date.now
	/// JSON-encoded LibrarySnapshot.
	var data: Data = Data()

	init(peerID: String, ownerName: String, data: Data) {
		self.peerID = peerID
		self.ownerName = ownerName
		self.receivedAt = .now
		self.data = data
	}

	var snapshot: LibrarySnapshot? {
		try? JSONDecoder.snapshot.decode(LibrarySnapshot.self, from: data)
	}
	var titles: [SharedTitle] { snapshot?.titles ?? [] }
}

extension JSONEncoder {
	/// Shared coder so dates round-trip consistently across devices.
	static let snapshot: JSONEncoder = {
		let e = JSONEncoder()
		e.dateEncodingStrategy = .iso8601
		return e
	}()
}
extension JSONDecoder {
	static let snapshot: JSONDecoder = {
		let d = JSONDecoder()
		d.dateDecodingStrategy = .iso8601
		return d
	}()
}
