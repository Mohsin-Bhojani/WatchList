//
//  WatchListWatchApp.swift
//  WatchList Watch App
//
//  The watch app's entry point. It runs on its own — it installs and opens
//  without the iPhone app — and syncs with the iPhone app when both are there
//  (PhoneSync). What it shows is kept on the watch (WatchStore).
//

import SwiftUI

@main
struct WatchListWatchApp: App {
	@State private var store: WatchStore
	private let sync: PhoneSync

	@Environment(\.scenePhase) private var scenePhase

	init() {
		let store = WatchStore()
		_store = State(initialValue: store)
		sync = PhoneSync(store: store)
		sync.start()
	}

	var body: some Scene {
		WindowGroup {
			SyncStatusView()
				.environment(store)
		}
		.onChange(of: scenePhase) { _, phase in
			if phase == .active { sync.refresh() }
		}
	}
}

/// What's arrived from the iPhone so far. Stands in until Up Next and Discover.
struct SyncStatusView: View {
	@Environment(WatchStore.self) private var store

	var body: some View {
		List {
			LabeledContent("iPhone app", value: "\(store.phone)")
			LabeledContent("Reachable", value: store.phoneIsReachable ? "Yes" : "No")
			if let snapshot = store.snapshot {
				LabeledContent("Up Next", value: "\(snapshot.upNext.count)")
				LabeledContent("Seeds", value: "\(snapshot.seeds.count)")
				LabeledContent("Sent", value: snapshot.sentAt.formatted(date: .omitted, time: .standard))
			} else {
				Text("Nothing from the iPhone yet")
			}
			LabeledContent("Outbox", value: "\(store.outbox.entries.count)")
		}
	}
}
