//
//  Collections.swift
//  WatchList
//
//  Your own collections (TitleCollection, in the library store): naming and
//  filling them, the pinned All Time Best every library starts with, the "Add
//  to collection" menu the title pages share, and the alert that names a new
//  collection.
//

import SwiftUI
import SwiftData

extension TitleCollection {
	/// Long enough for any real name, short enough to fit a card.
	static let maxNameLength = 40

	/// All Time Best: the collection every library has from the start, pinned
	/// above the verdicts on the Collections tab and leading the profile. Known
	/// by this fixed id rather than a flag on the model, so the library store's
	/// shape doesn't change. It fills and empties like any collection but can't
	/// be renamed or deleted.
	static let allTimeBestID = UUID(uuidString: "A11B35C0-7E57-4B57-A11B-35C07E57B357")!
	static let allTimeBestName = "All Time Best"

	var isPinned: Bool { id == Self.allTimeBestID }

	/// Trimmed and capped, so a pasted paragraph doesn't become a name.
	static func cleaned(_ raw: String) -> String {
		String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNameLength))
	}

	func contains(_ titleID: UUID) -> Bool { titleIDs.contains(titleID) }

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

	/// Adds All Time Best to a library that doesn't have it yet — a new one, or
	/// one from before it existed. Only ever adds.
	func ensurePinnedCollection() {
		let id = TitleCollection.allTimeBestID
		let existing = (try? fetchCount(FetchDescriptor<TitleCollection>(predicate: #Predicate { $0.id == id }))) ?? 0
		guard existing == 0 else { return }
		let collection = TitleCollection(name: TitleCollection.allTimeBestName)
		collection.id = id
		insert(collection)
	}
}

// MARK: - Add to collection

/// The title pages' "Add to collection": a tick for each collection — All Time
/// Best first — and New Collection, which names one and puts the title straight in.
struct AddToCollectionMenu: View {
	let titleID: UUID
	let onNew: () -> Void

	@Query(sort: \TitleCollection.created) private var collections: [TitleCollection]

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

	private func toggle(_ collection: TitleCollection) -> some View {
		Toggle(collection.name, isOn: Binding(
			get: { collection.contains(titleID) },
			set: { collection.set(titleID, included: $0) }))
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
