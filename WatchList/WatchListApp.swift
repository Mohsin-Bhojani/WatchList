//
//  WatchListApp.swift
//  WatchList
//
//  App entry point. Registers the new SwiftData models, and starts the link
//  with the watch app (WatchSync).
//

import SwiftUI
import SwiftData
import WatchListCore
import WatchListLibrary

@main
struct WatchListApp: App {
	/// Versioned, with a migration plan for later changes (LibrarySchema.swift).
	private let container = LibraryStore.makeContainer()
	@Environment(\.scenePhase) private var scenePhase

	init() {
		// Preference default; the user can change this in the iOS Settings app
		// (defined in Settings.bundle). Registering here keeps it ON until then.
		UserDefaults.standard.register(defaults: [
			"autoMarkEpisodesWatched": true,
			"accentColorID": "classicRed",
			// Shows gain seasons after you add them; check once a day.
			"autoCheckNewEpisodes": true,
		])
		// Before any window, so the watch's actions can arrive with the app in the background.
		WatchSync.shared.activate()
	}

	var body: some Scene {
		WindowGroup {
			RootView()
				.syncsWithWatch()
				.onChange(of: scenePhase) { _, phase in
					// Leaving the app is when to book the next background check.
					if phase == .background { BackgroundRefresh.schedule() }
				}
		}
		.modelContainer(container)
		.backgroundTask(.appRefresh(BackgroundRefresh.identifier)) { [container] in
			await BackgroundRefresh.run(in: container)
		}
	}
}
