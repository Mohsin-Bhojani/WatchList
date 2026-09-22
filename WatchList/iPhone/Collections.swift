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

extension TitleCollection {
	/// Long enough for any real name, short enough to fit a card.
	static let maxNameLength = 40

	/// Top 4: the collection every library has from the start, pinned above the
	/// verdicts on the Collections tab and leading the profile. Known by this
	/// fixed id rather than a flag on the model, so the library store's shape
	/// doesn't change. It holds four titles at most, and can't be renamed or
	/// deleted. It began as All Time Best, which held any number.
	static let topFourID = UUID(uuidString: "A11B35C0-7E57-4B57-A11B-35C07E57B357")!
	static let topFourName = "Top 4"
	static let topFourSize = 4

	var isPinned: Bool { id == Self.topFourID }

	/// The most titles it holds: four in Top 4, any number in your own.
	var capacity: Int? { isPinned ? Self.topFourSize : nil }

	/// Whether another title fits, holding `count` titles still in the library.
	func hasRoom(holding count: Int) -> Bool {
		capacity.map { count < $0 } ?? true
	}

	/// Trimmed and capped, so a pasted paragraph doesn't become a name.
	static func cleaned(_ raw: String) -> String {
		String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
	}

	func contains(_ titleID: UUID) -> Bool { titleIDs.contains(titleID) }

	/// What a longer All Time Best keeps as Top 4: its first four titles still
	/// in the library.
	static func topFour(of titleIDs: [UUID], inLibrary library: Set<UUID>) -> [UUID] {
		Array(titleIDs.filter(library.contains).prefix(topFourSize))
	}

	/// Puts a title in — at the end — or takes it out.
	func set(_ titleID: UUID, included: Bool) {
		if included {
			if !titleIDs.contains(titleID) { titleIDs.append(titleID) }
		} else {
			titleIDs.removeAll { $0 == titleID }
		}
	}

	/// A blank name leaves the old one.
	func rename(to raw: String) {
		let cleaned = Self.cleaned(raw)
		if !cleaned.isEmpty { name = cleaned }
	}
}

extension ModelContext {
	/// Makes an empty collection, or nothing when the name is blank.
	@discardableResult
	func makeCollection(named raw: String) -> TitleCollection? {
		let name = TitleCollection.cleaned(raw)
		guard !name.isEmpty else { return nil }
		let collection = TitleCollection(name: name)
		insert(collection)
		return collection
	}

	/// Gives the library Top 4: adds it to one that doesn't have it yet — a new
	/// one, or one from before it existed — and turns the All Time Best it used to
	/// be into it, renamed and cut to its first four titles still in the library.
	func ensurePinnedCollection() {
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

// MARK: - Add to collection

/// The title pages' "Add to collection": a tick for each collection — Top 4
/// first — and New Collection, which names one and puts the title straight in.
/// Top 4 with four titles in takes no more until one comes out.
struct AddToCollectionMenu: View {
	let titleID: UUID
	let onNew: () -> Void

	@Query(sort: \TitleCollection.created) private var collections: [TitleCollection]
	@Query private var shows: [Show]
	@Query private var films: [Film]

	var body: some View {
		Menu {
			ForEach(CollectionsFeed.pinned(collections).map { [$0] } ?? []) { toggle($0) }
			ForEach(CollectionsFeed.yours(collections)) { toggle($0) }
			Button(action: onNew) {
				Label("New Collection…", systemImage: "plus")
			}
		} label: {
			Label("Add to collection", systemImage: "rectangle.stack.badge.plus")
		}
	}

	@ViewBuilder private func toggle(_ collection: TitleCollection) -> some View {
		let isIn = collection.contains(titleID)
		let full = !isIn && collection.capacity != nil
			&& !collection.hasRoom(holding: CollectionsFeed.items(in: collection, shows: shows, films: films).count)
		Toggle(full ? "\(collection.name) (full)" : collection.name, isOn: Binding(
			get: { isIn },
			set: { collection.set(titleID, included: $0) }))
			.disabled(full)
	}
}

extension View {
	/// Asks for a name and makes a collection; with `adding`, that title goes in.
	func newCollectionAlert(isPresented: Binding<Bool>, adding titleID: UUID? = nil,
	                        onCreate: @escaping (TitleCollection) -> Void = { _ in }) -> some View {
		modifier(NewCollectionAlert(isPresented: isPresented, titleID: titleID, onCreate: onCreate))
	}
}

private struct NewCollectionAlert: ViewModifier {
	@Binding var isPresented: Bool
	let titleID: UUID?
	let onCreate: (TitleCollection) -> Void

	@Environment(\.modelContext) private var ctx
	@State private var name = ""

	func body(content: Content) -> some View {
		content
			.alert("New Collection", isPresented: $isPresented) {
				TextField("Name", text: $name)
				Button("Cancel", role: .cancel) { name = "" }
				Button("Create") {
					if let collection = ctx.makeCollection(named: name) {
						if let titleID { collection.set(titleID, included: true) }
						Haptics.success()
						onCreate(collection)
					}
					name = ""
				}
			} message: {
				Text(titleID == nil ? "Give it a name. You can add titles next." : "Give it a name. This title goes straight in.")
			}
	}
}
