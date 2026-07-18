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
	let container: ModelContainer
	private let sync: LibrarySync
	@Environment(\.scenePhase) private var scenePhase

	init() {
		// Preference default; the user can change this in the iOS Settings app
		// (defined in Settings.bundle). Registering here keeps it ON until then.
		UserDefaults.standard.register(defaults: [
			"autoMarkEpisodesWatched": true,
			"accentColorID": "classicRed",
		])

		// Two stores in one container: the rich library stays local (in the same
		// default store the app already used — the local config is left unnamed so
		// its URL is unchanged and existing data migrates in place), while a lean
		// SyncedEntry mirrors to iCloud (see LibrarySync / SyncedEntry).
		let schema = Schema([Show.self, Season.self, Episode.self, Film.self, SyncedEntry.self])
		let richSchema = Schema([Show.self, Season.self, Episode.self, Film.self])
		func makeContainer(cloudKit: ModelConfiguration.CloudKitDatabase) throws -> ModelContainer {
			let local = ModelConfiguration(schema: richSchema, cloudKitDatabase: .none)
			let cloud = ModelConfiguration("Cloud", schema: Schema([SyncedEntry.self]), cloudKitDatabase: cloudKit)
			return try ModelContainer(for: schema, configurations: local, cloud)
		}
		do {
			container = try makeContainer(cloudKit: .automatic)
		} catch {
			// The iCloud capability may not be added yet (or the device isn't signed
			// into iCloud): fall back to a fully-local container so the app still runs.
			do {
				container = try makeContainer(cloudKit: .none)
			} catch {
				fatalError("Could not create ModelContainer: \(error)")
			}
		}
		sync = LibrarySync(container: container)
	}

	var body: some Scene {
		WindowGroup {
			RootView()
				.task {
					sync.start()
					await sync.reconcile()
				}
				.onChange(of: scenePhase) { _, phase in
					// Push local edits and pull remote changes when the app comes
					// forward or is about to be backgrounded.
					if phase == .active || phase == .background {
						Task { await sync.reconcile() }
					}
				}
		}
		.modelContainer(container)
	}
}
