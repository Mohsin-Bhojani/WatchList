//
//  WatchListWatchApp.swift
//  WatchList Watch App
//
//  The watch app's entry point. It runs on its own — it installs and opens
//  without the iPhone app — and syncs with the iPhone app when both are there
//  (PhoneSync). What it shows is kept on the watch (WatchStore).
//
//  Two pages, a Crown turn apart: Up Next on top, Discover below.
//

import SwiftUI

@main
struct WatchListWatchApp: App {
	@State private var store: WatchStore
	private let sync: PhoneSync

	@Environment(\.scenePhase) private var scenePhase

	init() {
		let store = WatchStore.launching()
		_store = State(initialValue: store)
		sync = PhoneSync(store: store)
		sync.start()
	}

	var body: some Scene {
		WindowGroup {
			WatchRootView()
				.environment(store)
		}
		.onChange(of: scenePhase) { _, phase in
			guard phase == .active else { return }
			// Anything that failed to go, and whatever's changed on the iPhone.
			sync.flush()
			sync.refresh()
		}
	}
}

enum WatchPage: Hashable {
	case upNext, discover
}

/// Up Next above Discover, as vertical pages: turn the Crown or swipe to move
/// between them. The one NavigationStack holds both, and each page puts its
/// own buttons in its toolbar.
struct WatchRootView: View {
	@State private var page: WatchPage = .upNext

	var body: some View {
		NavigationStack {
			TabView(selection: $page) {
				UpNextPage()
					.tag(WatchPage.upNext)
				DiscoverPage(page: $page)
					.tag(WatchPage.discover)
			}
			.tabViewStyle(.verticalPage)
		}
	}
}

extension WatchStore {
	/// The store the app runs on. In a Debug build, -WatchListSample swaps in a
	/// made-up library that's never saved, to try the app with no iPhone.
	static func launching() -> WatchStore {
		#if DEBUG
		if ProcessInfo.processInfo.arguments.contains("-WatchListSample") {
			return WatchStore(preview: .sample)
		}
		#endif
		return WatchStore()
	}
}
