//
//  WatchedTitleDestination.swift
//  WatchList
//
//  Where a Home or Profile card opens to, and Home's hero artwork pick — the
//  parts of HomeFeed that need the app's screens or TMDb's gallery. The rest
//  of HomeFeed is in WatchListKit's Library.
//

import SwiftUI
import WatchListCore
import WatchListLibrary

extension WatchedTitle {
	@ViewBuilder var destination: some View {
		switch self {
		case .show(let show): PhoneShowDetailView(show: show)
		case .film(let film): PhoneFilmDetailView(film: film)
		}
	}
}

extension HomeFeed {
	/// The hero's artwork, best first, for the design's wide frame: the landscape
	/// picture chosen by hand when there is one (`chosenByHand`), then a textless
	/// backdrop (no printed title under the one Home draws), then a textless
	/// poster, then whatever backdrop or poster the show was saved with.
	static func heroArtURL(for show: Show, gallery: ImageGallery?, chosenByHand: Bool = false) -> String {
		if chosenByHand, !show.backdropURL.isEmpty {
			return show.backdropURL.replacingOccurrences(of: "/t/p/w780/", with: "/t/p/w1280/")
		}
		if let gallery {
			if let backdrop = textless(.backdrop, in: gallery) {
				// A 1080p original reads sharp at hero size; bigger originals run
				// to megabytes, so those come down at 1280.
				let size = (1...1920).contains(backdrop.width) ? "original" : "w1280"
				return "\(TMDbConfig.imageBase)/\(size)\(backdrop.id)"
			}
			if let poster = textless(.poster, in: gallery) {
				return "\(TMDbConfig.imageBase)/w780\(poster.id)"
			}
		}
		// What the show was saved with is sized for detail headers and grid cards,
		// so ask for the next size up. Posters picked from Photos are file URLs
		// and pass through untouched.
		if !show.backdropURL.isEmpty {
			return show.backdropURL.replacingOccurrences(of: "/t/p/w780/", with: "/t/p/w1280/")
		}
		return show.posterURL.replacingOccurrences(of: "/t/p/w500/", with: "/t/p/w780/")
	}

	/// Galleries arrive best-rated first, so the first untagged entry wins.
	private static func textless(_ kind: ImageEntry.Kind, in gallery: ImageGallery) -> ImageEntry? {
		gallery.groups.first { $0.kind == kind }?.entries.first { $0.language == nil }
	}
}
