// swift-tools-version: 6.2
//
//  WatchListKit: the code the iPhone app, the watch app and the widget share,
//  built once as modules rather than compiled into each target from a folder.
//
//    WatchListCore     plain values, TMDb, air dates, and what the iPhone says
//                      to the watch and the widget. Foundation only; used by
//                      all three.
//    WatchListLibrary  the SwiftData models and the rules that read them —
//                      what's next, watched dates, ratings, collections,
//                      export and restore. Used by the iPhone app.
//
//  Built with the app targets' settings — Swift 5 mode, the main actor by
//  default, approachable concurrency — so code behaves as it did in the app.
//

import PackageDescription

let settings: [SwiftSetting] = [
	.defaultIsolation(MainActor.self),
	.enableUpcomingFeature("NonisolatedNonsendingByDefault"),
	.enableUpcomingFeature("InferIsolatedConformances"),
	.enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
	name: "WatchListKit",
	platforms: [.iOS("26.2"), .watchOS("26.0")],
	products: [
		.library(name: "WatchListCore", targets: ["WatchListCore"]),
		.library(name: "WatchListLibrary", targets: ["WatchListLibrary"]),
	],
	targets: [
		.target(name: "WatchListCore", swiftSettings: settings),
		.target(name: "WatchListLibrary", dependencies: ["WatchListCore"], swiftSettings: settings),
	],
	swiftLanguageModes: [.v5]
)
