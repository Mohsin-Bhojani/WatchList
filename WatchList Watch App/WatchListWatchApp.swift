//
//  WatchListWatchApp.swift
//  WatchList Watch App
//
//  The watch app's entry point. It runs on its own — it installs and opens
//  without the iPhone app — and syncs with the iPhone app when both are there.
//

import SwiftUI

@main
struct WatchListWatchApp: App {
	var body: some Scene {
		WindowGroup {
			Text("WatchList")
				.font(.headline)
		}
	}
}
