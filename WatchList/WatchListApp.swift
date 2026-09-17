//
//  WatchListApp.swift
//  WatchList
//
//  App entry point. Registers the new SwiftData models, and starts the link
//  with the watch app (WatchSync).
//

import SwiftUI
import SwiftData

@main
struct WatchListApp: App {
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
		}
		.modelContainer(for: [Show.self, Season.self, Episode.self, Film.self, TitleCollection.self,
		                      SuggestionDecision.self])
	}
}
