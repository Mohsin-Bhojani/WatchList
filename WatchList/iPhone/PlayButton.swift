//
//  PlayButton.swift
//  WatchList
//
//  Play, on a film or episode page, for a title that's on your Jellyfin
//  server — "Resume from 24:10" when you stopped part way. It looks for its
//  title when the page opens, and isn't there at all when you're not signed in
//  or the server hasn't got it. Watching it through counts as watching it.
//

import SwiftUI

/// What the page is, for finding it on the server.
enum PlayableTitle: Hashable {
	case film(tmdbID: Int?, imdbID: String?)
	case episode(showTMDbID: Int?, showIMDbID: String?, season: Int, episode: Int)

	fileprivate func find(in session: JellyfinSession) async -> JellyfinItem? {
		switch self {
		case .film(let tmdbID, let imdbID):
			return await session.movie(tmdbID: tmdbID, imdbID: imdbID)
		case .episode(let showTMDbID, let showIMDbID, let season, let episode):
			return await session.episode(showTMDbID: showTMDbID, showIMDbID: showIMDbID,
			                             season: season, episode: episode)
		}
	}
}

struct PagePlayButton: View {
	let title: PlayableTitle
	/// The player's title and the line under it.
	let name: String
	var subtitle: String? = nil
	/// Played through: the page marks it Watched.
	let onWatched: () -> Void

	private var session: JellyfinSession { .shared }
	@State private var item: JellyfinItem?
	@State private var starting = false
	@State private var failure: String?
	/// Bumped when the player closes, to fetch the new resume point.
	@State private var lookups = 0

	private struct Lookup: Hashable {
		let title: PlayableTitle
		let server: JellyfinAccount?
		let count: Int
	}

	var body: some View {
		Group {
			if let item {
				Button { Task { await play(item) } } label: {
					HStack(spacing: 8) {
						if starting {
							ProgressView().tint(.black)
						} else {
							Image(systemName: "play.fill")
						}
						Text(label(item))
					}
					.font(.system(size: 16, weight: .semibold))
					.foregroundStyle(.black)
					.frame(maxWidth: .infinity, minHeight: GlassControl.height)
					.background(.white, in: Capsule())
				}
				.buttonStyle(.pressable)
				.disabled(starting)
				.accessibilityHint("Plays from your Jellyfin server")
				.transition(.opacity.combined(with: .scale(scale: 0.97)))
			}
		}
		.task(id: Lookup(title: title, server: session.account, count: lookups)) {
			guard session.isSignedIn else {
				item = nil
				return
			}
			let found = await title.find(in: session)
			guard !Task.isCancelled else { return }
			withAnimation(Glass.smooth) { item = found }
		}
		.alert("Can't play this", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
			Button("OK", role: .cancel) {}
		} message: {
			Text(failure ?? "")
		}
	}

	private func label(_ item: JellyfinItem) -> String {
		item.resumeSeconds.map { "Resume from \(MediaPlayback.clock($0))" } ?? "Play"
	}

	private func play(_ item: JellyfinItem) async {
		Haptics.tap()
		starting = true
		defer { starting = false }
		do {
			let stream = try await session.stream(for: item, title: name, subtitle: subtitle)
			MediaPlayer.play(stream) { watched in
				if watched { onWatched() }
				lookups += 1
			}
		} catch {
			failure = error.localizedDescription
		}
	}
}
