//
//  Collections.swift
//  WatchList
//
//  Your own collections (TitleCollection, in the library store): naming and
//  filling them, the pinned Top 4 every library starts with, the "Add to
//  collection" menu the title pages share, and the alert that names a new
//  collection.
//

import SwiftUI
import SwiftData
import WatchListCore

extension TitleCollection {
	/// Long enough for any real name, short enough to fit a card.
	public static let maxNameLength = 40

	/// Top 4: the collection every library has from the start, pinned above the
	/// verdicts on the Collections tab and leading the profile. Known by this
	/// fixed id rather than a flag on the model, so the library store's shape
	/// doesn't change. It holds four titles at most, and can't be renamed or
	/// deleted. It began as All Time Best, which held any number.
	public static let topFourID = UUID(uuidString: "A11B35C0-7E57-4B57-A11B-35C07E57B357")!
	public static let topFourName = "Top 4"
	public static let topFourSize = 4

	public var isPinned: Bool { id == Self.topFourID }

	/// The most titles it holds: four in Top 4, any number in your own.
	public var capacity: Int? { isPinned ? Self.topFourSize : nil }

	/// Whether another title fits, holding `count` titles still in the library.
	public func hasRoom(holding count: Int) -> Bool {
		capacity.map { count < $0 } ?? true
	}

	/// Trimmed and capped, so a pasted paragraph doesn't become a name.
	public static func cleaned(_ raw: String) -> String {
		String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
	}

	public func contains(_ titleID: UUID) -> Bool { titleIDs.contains(titleID) }

	/// What a longer All Time Best keeps as Top 4: its first four titles still
	/// in the library.
	public static func topFour(of titleIDs: [UUID], inLibrary library: Set<UUID>) -> [UUID] {
		Array(titleIDs.filter(library.contains).prefix(topFourSize))
	}

	/// Puts a title in — at the end — or takes it out.
	public func set(_ titleID: UUID, included: Bool) {
		if included {
			if !titleIDs.contains(titleID) { titleIDs.append(titleID) }
		} else {
			titleIDs.removeAll { $0 == titleID }
		}
	}

	/// A blank name leaves the old one.
	public func rename(to raw: String) {
		let cleaned = Self.cleaned(raw)
		if !cleaned.isEmpty { name = cleaned }
	}
}

extension ModelContext {
	/// Makes an empty collection, or nothing when the name is blank.
	@discardableResult
	public func makeCollection(named raw: String) -> TitleCollection? {
		let name = TitleCollection.cleaned(raw)
		guard !name.isEmpty else { return nil }
		let collection = TitleCollection(name: name)
		insert(collection)
		return collection
	}

	/// Gives the library Top 4: adds it to one that doesn't have it yet — a new
	/// one, or one from before it existed — and turns the All Time Best it used to
	/// be into it, renamed and cut to its first four titles still in the library.
	public func ensurePinnedCollection() {
		let id = TitleCollection.topFourID
		guard let found = try? fetch(FetchDescriptor<TitleCollection>(predicate: #Predicate { $0.id == id })) else {
			return
		}
		guard let pinned = found.first else {
			let collection = TitleCollection(name: TitleCollection.topFourName)
			collection.id = id
			insert(collection)
			return
		}
		if pinned.name != TitleCollection.topFourName { pinned.name = TitleCollection.topFourName }
		guard pinned.titleIDs.count > TitleCollection.topFourSize else { return }
		var shows = FetchDescriptor<Show>()
		shows.propertiesToFetch = [\.id]
		var films = FetchDescriptor<Film>()
		films.propertiesToFetch = [\.id]
		guard let showIDs = try? fetch(shows).map(\.id), let filmIDs = try? fetch(films).map(\.id) else { return }
		pinned.titleIDs = TitleCollection.topFour(of: pinned.titleIDs, inLibrary: Set(showIDs + filmIDs))
	}
}
