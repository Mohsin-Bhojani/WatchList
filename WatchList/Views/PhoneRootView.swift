//
//  PhoneRootView.swift
//  WatchList
//
//  The app's shell: Home, Shows, Discover and Collections, and Search set
//  apart — where titles get added.
//    - iPhone: LiquidDock along the bottom in place of the system tab bar — the
//      four tabs in one glass capsule, "Add a title" beside them
//    - iPad: the same tabs in the floating tab bar at the top, which opens out
//      into a sidebar; the sidebar also lists Top 4, the by-verdict
//      collections and your own, each opening straight onto its page
//  Tapping the tab you're on goes back to its list and up to its top, as the
//  system does; tapping Shows, Discover or Collections once it's there opens
//  its filters.
//

import SwiftUI
import SwiftData
import WatchListCore
import WatchListLibrary

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

	/// The dock's taps: the same rules as the system bar's, and a second tap on
	/// the tab you're on, anywhere but its top, takes its page back up.
	private func select(_ tapped: PhoneTab) {
		if tapped == selection {
			let atTop = (tapped == .shows && showsAtTop) || (tapped == .collections && collectionsAtTop)
				|| (tapped == .discover && discoverAtTop)
			if atTop {
				tabSelection.wrappedValue = tapped
			} else {
				NotificationCenter.default.post(name: .tabReselected, object: tapped)
			}
			return
		}
		Haptics.selection()
		selection = tapped
	}

	var body: some View {
		TabView(selection: tabSelection) {
			Tab("Home", systemImage: "house", value: PhoneTab.home) {
				PhoneHomeView { selection = $0 }
					.hidesSystemTabBar(!isPad)
			}
			Tab("Shows", systemImage: "popcorn", value: PhoneTab.shows) {
				PhoneShowsView(atTop: $showsAtTop, showingFilters: $showsFilters)
					.hidesSystemTabBar(!isPad)
			}
			Tab("Discover", systemImage: "sparkles", value: PhoneTab.discover) {
				PhoneDiscoverView(atTop: $discoverAtTop, showingFilters: $discoverFilters)
					.hidesSystemTabBar(!isPad)
			}
			Tab("Collections", systemImage: "square.grid.2x2", value: PhoneTab.collections) {
				PhoneCollectionsView(atTop: $collectionsAtTop, showingFilters: $collectionsFilters)
					.hidesSystemTabBar(!isPad)
			}
			Tab("Search", systemImage: "magnifyingglass", value: PhoneTab.search, role: .search) {
				PhoneAddSearchView()
					.hidesSystemTabBar(!isPad)
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
		.safeAreaInset(edge: .bottom, spacing: 0) {
			if !isPad && !DockCover.shared.isCovered {
				LiquidDock(selection: selection) { select($0) }
					.transition(.move(edge: .bottom).combined(with: .opacity))
			}
		}
		.animation(Glass.smooth, value: DockCover.shared.isCovered)
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
			guard let shows = try? ctx.fetch(FetchDescriptor<Show>()) else { return }
			if LibraryRefresher.autoCheckIsDue {
				_ = await LibraryRefresher.refreshAll(shows: shows, into: ctx)
			}
			// What's out is on Home now; the background won't announce it again.
			EpisodeAlerts.markSeen(in: shows)
		}
		// A collection deleted while its sidebar item is open falls back to Collections.
		.onChange(of: collections.map(\.id)) {
			if case .collection(let id) = selection, !collections.contains(where: { $0.id == id }) {
				selection = .collections
			}
		}
	}
}

private extension View {
	/// iPhone draws LiquidDock in the system tab bar's place.
	@ViewBuilder func hidesSystemTabBar(_ hide: Bool) -> some View {
		if hide {
			toolbarVisibility(.hidden, for: .tabBar)
				// The LiquidDock floats over the foot of every page in the tab,
				// pushed ones too, and its inset doesn't reach their scroll views:
				// room at the end of each, so the last row can scroll clear of it.
				.contentMargins(.bottom, LiquidDock.clearance, for: .scrollContent)
		} else { self }
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
