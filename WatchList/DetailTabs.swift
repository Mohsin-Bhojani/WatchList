//
//  DetailTabs.swift
//  WatchList
//
//  The artwork gallery the title pages open from their menus: every poster,
//  backdrop, logo and still TMDb holds for a series, season, episode or film.
//  It fetches the first time it opens and reads from CreditsLoader's session
//  cache after that.
//

import SwiftUI
import SwiftData

// MARK: - Images

/// Which title's artwork the gallery shows; each differs only in the endpoint
/// behind it.
enum ImageSource: Hashable {
	case series(tvID: Int)
	case season(tvID: Int, season: Int)
	case episode(tvID: Int, season: Int, episode: Int)
	case movie(movieID: Int)
}

/// Every image TMDb holds for this title, season or episode — posters,
/// backdrops, logos and stills, grouped by kind and in every language, since
/// the untitled artwork is usually the point. Tapping one opens it full size,
/// with the rest of the gallery a swipe away.
struct ImagesTabView: View {
	let source: ImageSource
	/// Reports whether the first fetch found anything worth a tab.
	var onLoaded: (Bool) -> Void = { _ in }

	@State private var gallery = ImageGallery()
	@State private var loading = true
	@State private var viewing: ImageEntry?

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			HStack {
				SectionLabel(text: "Images", systemImage: "photo.on.rectangle.angled")
				Spacer()
				Text(loading ? "via TMDb" : "\(gallery.count) via TMDb")
					.font(.system(size: 12, weight: .medium, design: .rounded))
					.foregroundStyle(.tertiary)
			}

			if loading {
				HStack(spacing: 10) {
					ProgressView()
					Text("Pulling artwork from TMDb…")
						.font(.system(size: 14, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(16)
				.glass(cornerRadius: 18)
			} else {
				ForEach(gallery.groups) { group in
					VStack(alignment: .leading, spacing: 10) {
						// Only worth a heading when there's more than one kind —
						// a season's tab is posters and nothing else.
						if gallery.groups.count > 1 { heading(group) }
						grid(group)
					}
				}
			}
		}
		.task { await load() }
		.fullScreenCover(item: $viewing) { entry in
			ImageViewer(entries: gallery.all, start: entry)
		}
	}

	private func heading(_ group: ImageGroup) -> some View {
		HStack(spacing: 6) {
			Text(group.kind.title)
				.font(Glass.serif(15, .semibold))
				.foregroundStyle(.primary)
			Text("\(group.entries.count)")
				.font(.system(size: 12, weight: .semibold, design: .rounded))
				.foregroundStyle(.secondary)
		}
	}

	private func grid(_ group: ImageGroup) -> some View {
		LazyVGrid(columns: columns(for: group.kind), spacing: 10) {
			ForEach(group.entries) { entry in
				Button {
					Haptics.tap()
					viewing = entry
				} label: {
					ImageTile(entry: entry)
				}
				.buttonStyle(.pressable)
			}
		}
	}

	/// Portrait art packs tighter than landscape; the maximums stop a two-poster
	/// group stretching across an iPad.
	private func columns(for kind: ImageEntry.Kind) -> [GridItem] {
		switch kind {
		case .poster:           return [GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 10)]
		case .still, .backdrop: return [GridItem(.adaptive(minimum: 160, maximum: 260), spacing: 10)]
		case .logo:             return [GridItem(.adaptive(minimum: 130, maximum: 200), spacing: 10)]
		}
	}

	private func load() async {
		switch source {
		case .series(let tvID):
			gallery = await CreditsLoader.seriesImages(tvID: tvID)
		case .season(let tvID, let season):
			gallery = await CreditsLoader.seasonImages(tvID: tvID, season: season)
		case .episode(let tvID, let season, let episode):
			gallery = await CreditsLoader.episodeImages(tvID: tvID, season: season, episode: episode)
		case .movie(let movieID):
			gallery = await CreditsLoader.movieImages(movieID: movieID)
		}
		loading = false
		onLoaded(!gallery.isEmpty)
	}
}
