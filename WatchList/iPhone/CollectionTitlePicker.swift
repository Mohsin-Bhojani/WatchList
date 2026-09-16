//
//  CollectionTitlePicker.swift
//  WatchList
//
//  Add Titles, from one of your collections: the whole library A–Z — or just
//  its shows or films — searchable, on the colour of the page it opens from.
//  Each title is a glass row, lit and ticked once it's in; tapping one puts it
//  in or takes it out there and then.
//

import SwiftUI
import SwiftData

struct CollectionTitlePicker: View {
	let collectionID: UUID
	/// The colour of the page it opens from; nil for your accent's, as on the
	/// profile.
	var tone: UIColor?

	@Environment(\.dismiss) private var dismiss
	@Query private var shows: [Show]
	@Query private var films: [Film]
	@Query(sort: \TitleCollection.created) private var collections: [TitleCollection]

	@State private var search = ""
	@State private var kind: BrowseKind = .all

	private static let rowShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

	private var ground: PageGround { tone.map { PageGround(base: $0) } ?? .accent }

	private var titles: [WatchedTitle] {
		var items: [WatchedTitle] = []
		if kind.includesShows { items += shows.map(WatchedTitle.show) }
		if kind.includesFilms { items += films.map(WatchedTitle.film) }
		let query = search.trimmingCharacters(in: .whitespaces)
		if !query.isEmpty {
			items = items.filter { $0.title.localizedCaseInsensitiveContains(query) }
		}
		return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
	}

	var body: some View {
		let collection = collections.first { $0.id == collectionID }
		let included = Set(collection?.titleIDs ?? [])
		let titles = titles
		let name = collection.map { "Add to \($0.name)" } ?? "Add Titles"
		NavigationStack {
			ScrollView {
				LazyVStack(spacing: 10) {
					kindSwitch
						.padding(.bottom, 6)
					if titles.isEmpty {
						Text(search.isEmpty ? "Nothing in your library yet." : "No titles match \u{201C}\(search)\u{201D}.")
							.font(.system(size: 14, weight: .medium))
							.foregroundStyle(.white.opacity(0.75))
							.frame(maxWidth: .infinity, alignment: .leading)
							.padding(16)
							.liquidCard(cornerRadius: 20)
					}
					ForEach(titles) { item in
						row(item, included: included.contains(item.id))
					}
				}
				.foregroundStyle(.white)
				.padding(.horizontal, 16)
				.padding(.top, 8)
				.padding(.bottom, 24)
				.readableColumn()
			}
			.scrollDismissesKeyboard(.interactively)
			.background(ground.gradient.ignoresSafeArea())
			.searchable(text: $search, prompt: "Search your library")
			.navigationTitle(name)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				// The name with what's in under it, drawn here so both stay white: the
				// bar's own subtitle takes the app's accent, which vanishes on this colour.
				ToolbarItem(placement: .principal) {
					VStack(spacing: 1) {
						Text(name)
							.font(.system(size: 17, weight: .semibold))
						Text(CollectionsFeed.countLabel(CollectionsFeed.items(in: collection, shows: shows,
						                                                      films: films).count))
							.font(.system(size: 12, weight: .medium))
							.foregroundStyle(.white.opacity(0.65))
							.contentTransition(.numericText())
					}
					.foregroundStyle(.white)
					.lineLimit(1)
					.accessibilityElement(children: .combine)
					.accessibilityAddTraits(.isHeader)
				}
				.sharedBackgroundVisibility(.hidden)
				ToolbarItem(placement: .confirmationAction) {
					Button("Done", systemImage: "checkmark", role: .confirm) { dismiss() }
				}
			}
		}
		// White text and dark glass on the colour, whatever the system's scheme —
		// and a white Done, since the app's accent vanishes on its own colour.
		.tint(.white)
		.preferredColorScheme(.dark)
		.presentationBackground(ground.gradient)
	}

	/// All, TV Shows or Films, as the title pages' glass switch.
	private var kindSwitch: some View {
		PageSwitch(options: BrowseKind.allCases.map { option in
			PageSwitchOption(title: option.label, systemImage: option.systemImage, selected: kind == option,
			                 fill: .white) {
				withAnimation(Glass.smooth) { kind = option }
			}
		}, selectedText: ground.deep)
		.frame(maxWidth: .infinity)
	}

	private func row(_ item: WatchedTitle, included: Bool) -> some View {
		Button {
			Haptics.selection()
			withAnimation(Glass.smooth) {
				collections.first { $0.id == collectionID }?.set(item.id, included: !included)
			}
		} label: {
			HStack(spacing: 14) {
				PosterImage(urlString: item.posterURL, systemPlaceholder: item.placeholder)
					.frame(width: 44, height: 66)
					.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
					.shadow(color: .black.opacity(0.3), radius: 6, y: 4)
				VStack(alignment: .leading, spacing: 3) {
					Text(item.title)
						.font(.system(size: 15, weight: .semibold))
						.multilineTextAlignment(.leading)
						.lineLimit(2)
					Text(CollectionsFeed.kindLine(item))
						.font(.system(size: 12, weight: .medium))
						.foregroundStyle(.white.opacity(0.65))
				}
				Spacer(minLength: 8)
				tick(included)
			}
			.padding(10)
			.padding(.trailing, 6)
			.contentShape(Self.rowShape)
		}
		.buttonStyle(.plain)
		// What's in lifts off the colour: brighter glass, and a white tick.
		.glassEffect(.regular.tint(.white.opacity(included ? 0.2 : 0.04)).interactive(), in: Self.rowShape)
		.accessibilityAddTraits(included ? .isSelected : [])
		.accessibilityHint(included ? "Takes it out of the collection" : "Puts it in the collection")
	}

	/// A plus in a ring to put a title in; once it's in, a tick on white.
	private func tick(_ included: Bool) -> some View {
		Image(systemName: included ? "checkmark" : "plus")
			.font(.system(size: 13, weight: .bold))
			.foregroundStyle(included ? ground.deep : .white)
			.contentTransition(.symbolEffect(.replace))
			.frame(width: 30, height: 30)
			.background {
				if included {
					Circle().fill(.white)
				} else {
					Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1.5)
				}
			}
			.accessibilityHidden(true)
	}
}
