//
//  CollectionMenus.swift
//  WatchList
//
//  The title pages' Add to collection menu and the New Collection alert. The
//  collections' rules are in WatchListKit's Library (Collections.swift).
//

import SwiftUI
import SwiftData
import WatchListCore
import WatchListLibrary

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
