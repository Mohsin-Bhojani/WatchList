//
//  StrayLibraryCopy.swift
//  WatchListLibrary
//
//  One build of the app (249f736, before the store was pinned to the app's own
//  folder) let SwiftData copy the library into the widget's App Group folder
//  and work on the copy there. The app opens its own folder again now, so the
//  copy sits unused. This removes it — but only when nothing of yours would go
//  with it: every status, verdict, star, episode rating, watched and rated
//  date, note, aspect, collection and Discover choice in the copy has to be in
//  the library just as it is there. TMDb's own details (names, stills, air
//  dates) don't count; the daily refresh fills those in again. Otherwise the
//  copy stays put, for a restore by hand.
//

import Foundation
import SwiftData
import WatchListCore

public enum StrayLibraryCopy {

	public enum Outcome: Equatable {
		/// No copy there.
		case none
		/// The copy held nothing the library doesn't, and is gone.
		case removed
		/// The copy holds something the library doesn't; left where it is.
		case kept
	}

	/// The copy the old build left: default.store in the App Group's Application
	/// Support. Nil without the group.
	public nonisolated static var groupCopyURL: URL? {
		FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: WidgetLink.appGroup)?
			.appendingPathComponent("Library/Application Support/default.store")
	}

	/// Removes the copy at `copyURL`, and its -wal and -shm, when the library
	/// at `libraryURL` exists and covers everything of yours in it.
	public nonisolated static func removeIfCovered(copyAt copyURL: URL, libraryAt libraryURL: URL) -> Outcome {
		let files = FileManager.default
		guard files.fileExists(atPath: copyURL.path) else { return .none }
		// Never the only library there is.
		guard copyURL.standardizedFileURL != libraryURL.standardizedFileURL,
		      files.fileExists(atPath: libraryURL.path) else { return .kept }
		guard let copy = try? fingerprint(of: copyURL), let library = try? fingerprint(of: libraryURL),
		      isCovered(copy, by: library) else { return .kept }
		for suffix in ["", "-wal", "-shm"] {
			try? files.removeItem(atPath: copyURL.path + suffix)
		}
		return .removed
	}

	/// True when every entry in `copy` is in `library` with the same value.
	nonisolated static func isCovered(_ copy: [String: String], by library: [String: String]) -> Bool {
		copy.allSatisfy { library[$0.key] == $0.value }
	}

	/// What's yours in the store at `url`, one entry per record, keyed by kind
	/// and id. Opened, read and closed again before anything is removed.
	nonisolated static func fingerprint(of url: URL) throws -> [String: String] {
		let container = try ModelContainer(for: LibraryStore.schema, migrationPlan: LibraryMigrationPlan.self,
		                                   configurations: [LibraryStore.configuration(at: url)])
		let context = ModelContext(container)
		var entries: [String: String] = [:]
		func date(_ value: Date?) -> String { value.map { String($0.timeIntervalSinceReferenceDate) } ?? "-" }
		func stars(_ value: Double?) -> String { value.map { String($0) } ?? "-" }

		for show in try context.fetch(FetchDescriptor<Show>()) {
			entries["show:\(show.id)"] = [show.status.rawValue, show.rating?.rawValue ?? "-", stars(show.stars),
			                              date(show.watchedAt), date(show.ratedAt), show.notes,
			                              show.likedAspects.joined(separator: ","),
			                              show.dislikedAspects.joined(separator: ",")].joined(separator: "|")
		}
		for season in try context.fetch(FetchDescriptor<Season>()) {
			entries["season:\(season.id)"] = [season.status.rawValue, season.rating?.rawValue ?? "-",
			                                  stars(season.stars), date(season.ratedAt)].joined(separator: "|")
		}
		for episode in try context.fetch(FetchDescriptor<Episode>()) {
			entries["episode:\(episode.id)"] = [episode.status.rawValue, episode.episodeTier?.rawValue ?? "-",
			                                    date(episode.watchedAt)].joined(separator: "|")
		}
		for film in try context.fetch(FetchDescriptor<Film>()) {
			entries["film:\(film.id)"] = [film.status.rawValue, film.rating?.rawValue ?? "-", stars(film.stars),
			                              date(film.watchedAt), date(film.ratedAt), film.notes,
			                              film.likedAspects.joined(separator: ","),
			                              film.dislikedAspects.joined(separator: ",")].joined(separator: "|")
		}
		for collection in try context.fetch(FetchDescriptor<TitleCollection>()) {
			entries["collection:\(collection.id)"] = collection.name + "|"
				+ collection.titleIDs.map(\.uuidString).joined(separator: ",")
		}
		for decision in try context.fetch(FetchDescriptor<SuggestionDecision>()) {
			entries["decision:\(decision.key)"] = decision.choice.rawValue + "|" + date(decision.decidedAt)
		}
		return entries
	}
}
