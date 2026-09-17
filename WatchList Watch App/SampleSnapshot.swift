//
//  SampleSnapshot.swift
//  WatchList Watch App
//
//  A made-up library for trying the watch app with no iPhone: launch a Debug
//  build with -WatchListSample, or open a preview. Up Next is invented; Discover
//  starts from real TMDb titles, so it fetches real suggestions.
//

#if DEBUG
import Foundation
import SwiftUI

extension PhoneSnapshot {
	static let sample: PhoneSnapshot = {
		func episode(_ season: Int, _ number: Int, _ title: String) -> UpNextEpisode {
			UpNextEpisode(id: UUID(), seasonNumber: season, episodeNumber: number, title: title, runtimeMinutes: 48,
			              status: .toWatch, tier: nil)
		}
		return PhoneSnapshot(
			upNext: [
				UpNextShow(id: UUID(), title: "Lanternfall", artworkURL: "",
				           upcoming: [episode(2, 5, "The Long Tide"), episode(2, 6, "Salt in the Lamps")],
				           remaining: 2, episodeCount: 16),
				UpNextShow(id: UUID(), title: "Salt & Signal", artworkURL: "",
				           upcoming: [episode(1, 4, "Low Water")], remaining: 1, episodeCount: 8),
			],
			seeds: [DiscoverSeed(id: UUID(), kind: .film, tmdbID: 329865, title: "Arrival"),
			        DiscoverSeed(id: UUID(), kind: .show, tmdbID: 95396, title: "Severance")],
			library: ["Film-329865", "Show-95396"], notInterested: [], putOff: [:], applied: [], sentAt: .distantPast)
	}()
}

#Preview {
	WatchRootView()
		.environment(WatchStore(preview: .sample))
}
#endif
