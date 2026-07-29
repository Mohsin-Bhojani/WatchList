//
//  WatchListApp.swift
//  WatchList
//
//  App entry point. Registers the new SwiftData models.
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
			// Similar tab: where the Mac helper that holds the API key lives.
			// 127.0.0.1 works from the Simulator (it shares the Mac's network
			// stack); a device needs the Mac's Wi-Fi address instead.
			"similarProxyHost": "127.0.0.1",
			"similarProxyPort": 8787,
		])
	}

	var body: some Scene {
		WindowGroup {
			RootView()
		}
		.modelContainer(for: [Show.self, Season.self, Episode.self, Film.self, Suggestion.self])
	}
}
