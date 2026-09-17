//
//  PhoneCollectionsView.swift
//  WatchList
//
//  The iPhone Collections tab, after the "Collections" design:
//    - Pinned: All Time Best, the collection every library starts with, filled
//      by hand and opening its page
//    - By verdict: Perfection, Go For It, Timepass and Skip, each card counting
//      its titles over a fan of their posters, and opening the collection
//    - Your collections: the ones you make (TitleCollection), each opening its
//      page; New collection names one and opens it to fill
//  Tapping Collections again once the page is at its top opens Filter & Sort:
//  which sections show, and the order of your own, either way round.
//

import SwiftUI
import SwiftData

struct PhoneCollectionsView: View {
	/// Whether the page is on screen at its top, for the tab bar to read.
	@Binding var atTop: Bool
	@Binding var showingFilters: Bool

	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Query(sort: \Show.dateAdded, order: .reverse) private var shows: [Show]
	@Query(sort: \Film.dateAdded, order: .reverse) private var films: [Film]
	@Query(sort: \TitleCollection.created) private var collections: [TitleCollection]
	@Environment(\.modelContext) private var ctx

	@State private var showing: Showing = .all
	@State private var sort = ListOrder<CollectionsFeed.Sort>()
	@State private var naming = false
	/// A collection just made, opened so it can be filled.
	@State private var opened: UUID?
	@State private var deleting: TitleCollection?

	/// Which sections the page shows.
	private enum Showing: CaseIterable, Identifiable {
		case all, pinned, verdicts, yours

		var id: Self { self }

		var title: String {
			switch self {
			case .all:      return "All"
			case .pinned:   return "Pinned"
			case .verdicts: return "By Verdict"
			case .yours:    return "Yours"
			}
		}

		/// Whether this choice shows `section`: All shows every one.
		func shows(_ section: Showing) -> Bool { self == .all || self == section }
	}

	/// The sections and order, while either isn't the default.
	private var filterSummary: String? {
		var parts: [String] = []
		switch showing {
		case .all:      break
		case .pinned:   parts.append("Pinned only")
		case .verdicts: parts.append("By verdict only")
		case .yours:    parts.append("Yours only")
		}
		if showing.shows(.yours) && sort != ListOrder() { parts.append(sort.summary) }
		return parts.isEmpty ? nil : parts.joined(separator: " · ")
	}

	var body: some View {
		NavigationStack {
			ZStack {
				GlassBackground()
				ScrollView {
					VStack(alignment: .leading, spacing: 22) {
						VStack(alignment: .leading, spacing: 14) {
							ScreenHeader(title: "Collections")
							if let filterSummary {
								FilterSummaryButton(summary: filterSummary) { showingFilters = true }
									.padding(.horizontal, 20)
							}
						}
						if showing.shows(.pinned) { pinnedSection }
						if showing.shows(.verdicts) { verdictSection }
						if showing.shows(.yours) { yoursSection }
					}
					.padding(.bottom, 24)
				}
				.reportsListAtTop($atTop)
			}
			// Not shown, but it names the back button on a collection.
			.navigationTitle("Collections")
			.screenBar("Collections")
			.navigationDestination(item: $opened) { PhoneCollectionView(source: .mine($0)) }
			.newCollectionAlert(isPresented: $naming) { opened = $0.id }
			.confirmationDialog("Delete \u{201C}\(deleting?.name ?? "")\u{201D}?",
			                    isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
			                    titleVisibility: .visible, presenting: deleting) { collection in
				Button("Delete Collection", role: .destructive) {
					withAnimation(Glass.smooth) { ctx.delete(collection) }
				}
			} message: { _ in
				Text("Only the collection goes. Its titles stay in your library.")
			}
			.sheet(isPresented: $showingFilters) { filterSheet }
		}
	}

	private var filterSheet: some View {
		FilterSheet(title: "Filter & Sort", canReset: showing != .all || sort != ListOrder()) {
			showing = .all
			sort = ListOrder()
		} content: {
			SegmentedFilter(title: "Show", options: Showing.allCases, selection: $showing) { $0.title }
			SortSegments(title: "Sort Your Collections", order: $sort)
				.disabled(!showing.shows(.yours))
		}
	}

	// MARK: Pinned

	/// All Time Best, above the verdicts. It's always there, so it has no
	/// delete; its page takes titles in and out.
	@ViewBuilder private var pinnedSection: some View {
		if let pinned = CollectionsFeed.pinned(collections) {
			let items = CollectionsFeed.items(in: pinned, shows: shows, films: films)
			VStack(alignment: .leading, spacing: 10) {
				sectionTitle("Pinned")
				cardGrid {
					NavigationLink { PhoneCollectionView(source: .mine(pinned.id)) } label: {
						CollectionCard(title: pinned.name,
						               subtitle: CollectionsFeed.countLabel(items.count) + " · private",
						               locked: true,
						               posterURLs: items.map(\.posterURL),
						               tint: nil)
					}
					.buttonStyle(.pressable)
				}
			}
			.padding(.horizontal, 20)
		}
	}

	// MARK: By verdict

	private var verdictSection: some View {
		let verdicts = CollectionsFeed.byVerdict(shows: shows, films: films)
		return VStack(alignment: .leading, spacing: 10) {
			sectionTitle("By verdict")
			cardGrid {
				ForEach(verdicts) { collection in
					NavigationLink { PhoneCollectionView(source: .verdict(collection.rating)) } label: {
						CollectionCard(title: collection.rating.rawValue,
						               subtitle: CollectionsFeed.countLabel(collection.items.count),
						               posterURLs: collection.items.map(\.posterURL),
						               tint: Glass.tint(collection.rating))
					}
					.buttonStyle(.pressable)
					.disabled(collection.items.isEmpty)
				}
			}
		}
		.padding(.horizontal, 20)
	}

	// MARK: Your collections

	private var yoursSection: some View {
		let yours = CollectionsFeed.yours(collections)
		// Each collection's titles, worked out once for its card and for sorting by size.
		let titles = Dictionary(yours.map { ($0.id, CollectionsFeed.items(in: $0, shows: shows, films: films)) },
		                        uniquingKeysWith: { first, _ in first })
		let ordered = CollectionsFeed.sorted(yours, by: sort) { titles[$0.id]?.count ?? 0 }
		return VStack(alignment: .leading, spacing: 10) {
			sectionTitle("Your collections")
			if yours.isEmpty {
				Text("Make one for anything — comfort films, a watch party, a top ten.")
					.font(.system(size: 14, weight: .medium))
					.foregroundStyle(.secondary)
					.padding(.bottom, 2)
			}
			cardGrid {
				ForEach(ordered) { collection in
					let items = titles[collection.id] ?? []
					NavigationLink { PhoneCollectionView(source: .mine(collection.id)) } label: {
						CollectionCard(title: collection.name,
						               subtitle: CollectionsFeed.countLabel(items.count) + " · private",
						               locked: true,
						               posterURLs: items.map(\.posterURL),
						               tint: nil)
					}
					.buttonStyle(.pressable)
					.contextMenu {
						Button(role: .destructive) { deleting = collection } label: {
							Label("Delete Collection", systemImage: "trash")
						}
					}
				}
			}
			Button { naming = true } label: {
				HStack(spacing: 10) {
					Image(systemName: "plus")
						.font(.system(size: 15, weight: .semibold))
					Text("New collection")
						.font(.system(size: 15, weight: .semibold))
					Spacer()
				}
				.foregroundStyle(Glass.ink.opacity(0.8))
				.padding(.horizontal, 18)
				.frame(height: 58)
				.contentShape(Rectangle())
				.overlay(
					RoundedRectangle(cornerRadius: 20, style: .continuous)
						.strokeBorder(Glass.hairline.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
				)
			}
			.buttonStyle(.pressable)
		}
		.padding(.horizontal, 20)
	}

	/// One card a row on a phone; two or more across an iPad.
	private func cardGrid<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
		let columns = horizontalSizeClass == .regular
			? [GridItem(.adaptive(minimum: 340), spacing: 12)]
			: [GridItem(.flexible())]
		return LazyVGrid(columns: columns, spacing: 10) { content() }
	}

	private func sectionTitle(_ text: String) -> some View {
		Text(text)
			.font(.system(size: 20, weight: .bold))
			.foregroundStyle(Glass.ink)
			.accessibilityAddTraits(.isHeader)
	}
}

// MARK: - Card

/// A Collections card: dark, tinted from the leading edge, with the first four
/// posters fanned across the trailing end and running off its bottom. Without a
/// tint it takes its first poster's colour.
private struct CollectionCard: View {
	let title: String
	let subtitle: String
	let locked: Bool
	let posterURLs: [String]
	let tint: Color?

	@State private var sampled: UIColor?

	init(title: String, subtitle: String, locked: Bool = false, posterURLs: [String], tint: Color?) {
		self.title = title
		self.subtitle = subtitle
		self.locked = locked
		self.posterURLs = posterURLs
		self.tint = tint
		_sampled = State(initialValue: posterURLs.first.flatMap { PageTheme.cached($0) })
	}

	private var color: Color { tint ?? sampled.map { Color(uiColor: $0) } ?? Color(.collectionTintFallback) }

	var body: some View {
		let empty = posterURLs.isEmpty
		let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
		HStack(spacing: 8) {
			VStack(alignment: .leading, spacing: 3) {
				HStack(spacing: 6) {
					Text(title)
						.font(.system(size: 17, weight: .bold))
						.foregroundStyle(.white)
						.lineLimit(1)
					if locked {
						Image(systemName: "lock")
							.font(.system(size: 11, weight: .semibold))
							.foregroundStyle(.white.opacity(0.7))
					}
				}
				Text(subtitle)
					.font(.system(size: 12, weight: .medium))
					.foregroundStyle(.white.opacity(0.6))
			}
			Spacer(minLength: 0)
			FannedPosters(urls: Array(posterURLs.prefix(4)), posterWidth: 46)
				.offset(y: 16)
				.padding(.trailing, 12)
		}
		.padding(.leading, 18)
		.frame(height: 100)
		.background(LinearGradient(colors: [color.opacity(empty ? 0.12 : 0.5), .clear],
		                           startPoint: .leading, endPoint: .trailing))
		.background(Color(.collectionCardGround))
		.clipShape(shape)
		.overlay(shape.strokeBorder(color.opacity(empty ? 0.2 : 0.45), lineWidth: 1))
		.accessibilityElement(children: .combine)
		.task(id: posterURLs.first ?? "") {
			guard tint == nil, let url = posterURLs.first,
			      let tone = await PageTheme.load(url), !Task.isCancelled else { return }
			withAnimation(.easeOut(duration: 0.3)) { sampled = tone }
		}
	}
}
