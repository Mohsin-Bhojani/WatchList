//
//  CollectionReorderSheet.swift
//  WatchList
//
//  Reorder, from one of your collections' "…" menu: its titles as a list with
//  drag handles, on the colour of the page it opens from, like Add Titles.
//  Each move is saved as it's made, so Done only closes the sheet. The order
//  is the collection's own — the list, the carousel, the fanned posters and,
//  for Top 4, Home and the profile all follow it.
//

import SwiftUI
import SwiftData

struct CollectionReorderSheet: View {
	let collectionID: UUID
	/// The colour of the page it opens from.
	var tone: UIColor?

	@Environment(\.dismiss) private var dismiss
	@Query private var shows: [Show]
	@Query private var films: [Film]
	@Query(sort: \TitleCollection.created) private var collections: [TitleCollection]

	/// The titles as shown, moved here first so a drag doesn't wait on the store.
	@State private var order: [WatchedTitle] = []

	private var collection: TitleCollection? { collections.first { $0.id == collectionID } }
	private var ground: PageGround { tone.map { PageGround(base: $0) } ?? .accent }

	var body: some View {
		NavigationStack {
			List {
				Section {
					ForEach(Array(order.enumerated()), id: \.element.id) { index, item in
						row(item, position: index + 1)
							.listRowBackground(Color.white.opacity(0.08))
							.listRowSeparatorTint(.white.opacity(0.12))
					}
					.onMove(perform: move)
				} footer: {
					Text("Drag a title by its handle. The new order is saved as you go.")
						.font(.system(size: 13, weight: .medium))
						.foregroundStyle(.white.opacity(0.7))
				}
			}
			.scrollContentBackground(.hidden)
			.environment(\.editMode, .constant(.active))
			.background(ground.gradient.ignoresSafeArea())
			.navigationTitle(collection.map { "Reorder \($0.name)" } ?? "Reorder")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				// Drawn here, as in Add Titles, so it stays white in the page's type
				// rather than the bar's own.
				ToolbarItem(placement: .principal) {
					Text(collection.map { "Reorder \($0.name)" } ?? "Reorder")
						.font(.system(size: 17, weight: .semibold))
						.foregroundStyle(.white)
						.lineLimit(1)
						.accessibilityAddTraits(.isHeader)
				}
				.sharedBackgroundVisibility(.hidden)
				ToolbarItem(placement: .confirmationAction) {
					Button("Done", systemImage: "checkmark", role: .confirm) { dismiss() }
				}
			}
		}
		.tint(.white)
		.preferredColorScheme(.dark)
		.presentationBackground(ground.gradient)
		.onAppear {
			order = CollectionsFeed.items(in: collection, shows: shows, films: films)
		}
	}

	private func row(_ item: WatchedTitle, position: Int) -> some View {
		HStack(spacing: 12) {
			Text("\(position)")
				.font(.system(size: 13, weight: .bold).monospacedDigit())
				.foregroundStyle(.white.opacity(0.55))
				.frame(minWidth: 20)
			PosterImage(urlString: item.posterURL, systemPlaceholder: item.placeholder)
				.frame(width: 36, height: 54)
				.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
			VStack(alignment: .leading, spacing: 3) {
				Text(item.title)
					.font(.system(size: 15, weight: .semibold))
					.foregroundStyle(.white)
					.lineLimit(2)
				Text(CollectionsFeed.kindLine(item))
					.font(.system(size: 12, weight: .medium))
					.foregroundStyle(.white.opacity(0.6))
					.lineLimit(1)
			}
		}
		.padding(.vertical, 2)
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(position). \(item.title)")
	}

	private func move(from source: IndexSet, to destination: Int) {
		order.move(fromOffsets: source, toOffset: destination)
		collection?.reorder(order.map(\.id))
		Haptics.selection()
	}
}
