//
//  PhoneRootView.swift
//  WatchList
//
//  The app's shell, after the "Liquid Dock" design: Home, Shows, Discover and
//  Collections, and Search set apart as the search-role tab — where titles get
//  added.
//    - iPhone: the Liquid Glass tab bar along the bottom, Search in its own
//      circle on the trailing edge
//    - iPad: the same tabs in the floating tab bar at the top, which opens out
//      into a sidebar; the sidebar also lists Top 4, the by-verdict
//      collections and your own, each opening straight onto its page
//  Tapping the tab you're on goes back to its list and up to its top, as the
//  system does; tapping Shows, Discover or Collections once it's there opens
//  its filters.
//

import SwiftUI
import SwiftData

enum PhoneTab: Hashable {
	case home, shows, discover, collections, search
	/// iPad's sidebar only: a by-verdict collection, or one of yours.
	case verdict(Rating)
	case collection(UUID)
}

struct PhoneRootView: View {
	@State private var selection: PhoneTab = .home
	@Environment(\.modelContext) private var ctx
	@Query(sort: \TitleCollection.created) private var collections: [TitleCollection]

	@State private var showsAtTop = false
	@State private var showsFilters = false
	@State private var collectionsAtTop = false
	@State private var collectionsFilters = false
	@State private var discoverAtTop = false
	@State private var discoverFilters = false
	/// A friend's link or collection file the app was opened with.
	@State private var incoming: IncomingShare?

	/// Keyed on the device rather than the size class, so an iPad in Split View
	/// or Slide Over keeps its sidebar.
	private let isPad = UIDevice.current.userInterfaceIdiom == .pad

	/// The tab bar's selection. A tap on the tab already chosen still comes
	/// through here, which is how a second tap on Shows, Discover or Collections
	/// at the top of its page opens the filters.
	private var tabSelection: Binding<PhoneTab> {
		Binding {
			selection
		} set: { tapped in
			if tapped == selection {
				if tapped == .shows && showsAtTop { showsFilters = true }
				if tapped == .collections && collectionsAtTop { collectionsFilters = true }
				if tapped == .discover && discoverAtTop { discoverFilters = true }
			}
			selection = tapped
		}
	}

	var body: some View {
		TabView(selection: tabSelection) {
			Tab("Home", systemImage: "house", value: PhoneTab.home) {
				PhoneHomeView { selection = $0 }
			}
			Tab("Shows", systemImage: "popcorn", value: PhoneTab.shows) {
				PhoneShowsView(atTop: $showsAtTop, showingFilters: $showsFilters)
			}
			Tab("Discover", systemImage: "sparkles", value: PhoneTab.discover) {
				PhoneDiscoverView(atTop: $discoverAtTop, showingFilters: $discoverFilters)
			}
			Tab("Collections", systemImage: "square.grid.2x2", value: PhoneTab.collections) {
				PhoneCollectionsView(atTop: $collectionsAtTop, showingFilters: $collectionsFilters)
			}
			Tab("Search", systemImage: "magnifyingglass", value: PhoneTab.search, role: .search) {
				PhoneAddSearchView()
			}

			if isPad {
				// In the sidebar only — the floating tab bar keeps to the five above.
				TabSection("Pinned") {
					ForEach(collections.filter(\.isPinned)) { collection in
						Tab(collection.name, systemImage: "star", value: PhoneTab.collection(collection.id)) {
							NavigationStack { PhoneCollectionView(source: .mine(collection.id)) }
						}
					}
				}
				.defaultVisibility(.hidden, for: .tabBar)

				TabSection("By Verdict") {
					ForEach(Rating.allCases) { rating in
						Tab(rating.rawValue, systemImage: rating.systemImage, value: PhoneTab.verdict(rating)) {
							NavigationStack { PhoneCollectionView(source: .verdict(rating)) }
						}
					}
				}
				.defaultVisibility(.hidden, for: .tabBar)

				TabSection("Your Collections") {
					ForEach(CollectionsFeed.yours(collections)) { collection in
						Tab(collection.name, systemImage: "rectangle.stack",
						    value: PhoneTab.collection(collection.id)) {
							NavigationStack { PhoneCollectionView(source: .mine(collection.id)) }
						}
					}
				}
				.defaultVisibility(.hidden, for: .tabBar)
			}
		}
		.modifier(DockStyle(isPad: isPad))
		.onOpenURL { url in incoming = FriendShare.incoming(from: url) }
		.sheet(item: $incoming) { IncomingShareSheet(share: $0) }
		.task {
			// Every library has Top 4, pinned above the verdicts.
			ctx.ensurePinnedCollection()
			// Downloaded artwork is kept to a size; anything dropped downloads again.
			Task.detached(priority: .background) { ImageCache.trimDisk() }
			// Watched dates, stars and your collections now live in the library.
			// The old side stores sat in UserDefaults, read in whole at every
			// launch, and in a JSON file of their own.
			for key in ["watchedDates", "starRatings"] { UserDefaults.standard.removeObject(forKey: key) }
			let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
			try? FileManager.default.removeItem(at: documents.appendingPathComponent("Collections", isDirectory: true))
			// Tops shows up with newly aired episodes, at most once a day.
			guard LibraryRefresher.autoCheckIsDue,
			      let shows = try? ctx.fetch(FetchDescriptor<Show>()) else { return }
			_ = await LibraryRefresher.refreshAll(shows: shows, into: ctx)
		}
		// A collection deleted while its sidebar item is open falls back to Collections.
		.onChange(of: collections.map(\.id)) {
			if case .collection(let id) = selection, !collections.contains(where: { $0.id == id }) {
				selection = .collections
			}
		}
	}
}

/// iPad's tab bar floats at the top and opens out into a sidebar; iPhone keeps
/// the system dock. Its height is the system's: neither a compact size class
/// on the TabView nor one on the tab bar itself changes it.
private struct DockStyle: ViewModifier {
	let isPad: Bool

	func body(content: Content) -> some View {
		if isPad {
			content.tabViewStyle(.sidebarAdaptable)
		} else {
			content
		}
	}
}
