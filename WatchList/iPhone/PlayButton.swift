//
//  PlayButton.swift
//  WatchList
//
//  Play, on a film or episode page, for a title you can play — "Resume from
//  24:10" when you stopped part way. It looks on your Jellyfin server first,
//  then in the put.io file or folder linked to the film or show, when the page
//  opens; with neither, it isn't there at all. Watching it through counts as
//  watching it.
//

import SwiftUI

/// What the page is, for finding it on the server or in put.io.
enum PlayableTitle: Hashable {
	/// `id` is the film's own, which its put.io link is kept by.
	case film(id: UUID, tmdbID: Int?, imdbID: String?)
	/// `showID` is the show's own, which its put.io folder is kept by.
	case episode(showID: UUID?, showTMDbID: Int?, showIMDbID: String?, season: Int, episode: Int)

	/// The title whose put.io link plays it.
	fileprivate var linkedID: UUID? {
		switch self {
		case .film(let id, _, _): id
		case .episode(let showID, _, _, _, _): showID
		}
	}

	fileprivate func find() async -> PlaySource? {
		let jellyfin = JellyfinSession.shared
		if jellyfin.isSignedIn {
			let found: JellyfinItem? = switch self {
			case .film(_, let tmdbID, let imdbID):
				await jellyfin.movie(tmdbID: tmdbID, imdbID: imdbID)
			case .episode(_, let showTMDbID, let showIMDbID, let season, let episode):
				await jellyfin.episode(showTMDbID: showTMDbID, showIMDbID: showIMDbID, season: season, episode: episode)
			}
			if let found { return .jellyfin(found) }
		}
		let putio = PutioSession.shared
		guard putio.isConnected, let id = linkedID, let link = PutioLinks.shared.link(id) else { return nil }
		let file: PutioFile? = switch self {
		case .film: try? await putio.filmVideo(link)
		case .episode(_, _, _, let season, let episode): try? await putio.episodeVideo(link, season: season, episode: episode)
		}
		guard let file else { return nil }
		return .putio(file, resume: await putio.startFrom(file))
	}
}

/// Where a title plays from.
private enum PlaySource: Equatable {
	case jellyfin(JellyfinItem)
	case putio(PutioFile, resume: TimeInterval?)

	var resumeSeconds: TimeInterval? {
		switch self {
		case .jellyfin(let item): item.resumeSeconds
		case .putio(_, let resume): resume
		}
	}

	func stream(title: String, subtitle: String?) async throws -> PlayableStream {
		switch self {
		case .jellyfin(let item): try await JellyfinSession.shared.stream(for: item, title: title, subtitle: subtitle)
		case .putio(let file, _): try await PutioSession.shared.stream(for: file, title: title, subtitle: subtitle)
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

	@State private var source: PlaySource?
	@State private var starting = false
	@State private var failure: String?
	/// Bumped when the player closes, to fetch the new resume point.
	@State private var lookups = 0

	/// What finding it again depends on: the title, either source's sign-in,
	/// the title's put.io link, and each close of the player.
	private struct Lookup: Hashable {
		let title: PlayableTitle
		let server: JellyfinAccount?
		let putio: String?
		let link: PutioLink?
		let count: Int
	}

	var body: some View {
		Group {
			if let source {
				Button { Task { await play(source) } } label: {
					HStack(spacing: 8) {
						if starting {
							ProgressView().tint(.black)
						} else {
							Image(systemName: "play.fill")
						}
						Text(label(source))
					}
					.font(.system(size: 16, weight: .semibold))
					.foregroundStyle(.black)
					.frame(maxWidth: .infinity, minHeight: GlassControl.height)
					.background(.white, in: Capsule())
				}
				.buttonStyle(.pressable)
				.disabled(starting)
				.accessibilityHint(source.isPutio ? "Plays from put.io" : "Plays from your Jellyfin server")
				.transition(.opacity.combined(with: .scale(scale: 0.97)))
			}
		}
		.task(id: Lookup(title: title, server: JellyfinSession.shared.account, putio: PutioSession.shared.userName,
		                 link: title.linkedID.flatMap { PutioLinks.shared.link($0) }, count: lookups)) {
			let found = await title.find()
			guard !Task.isCancelled else { return }
			withAnimation(Glass.smooth) { source = found }
		}
		.alert("Can't play this", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
			Button("OK", role: .cancel) {}
		} message: {
			Text(failure ?? "")
		}
	}

	private func label(_ source: PlaySource) -> String {
		source.resumeSeconds.map { "Resume from \(MediaPlayback.clock($0))" } ?? "Play"
	}

	private func play(_ source: PlaySource) async {
		Haptics.tap()
		starting = true
		defer { starting = false }
		do {
			let stream = try await source.stream(title: name, subtitle: subtitle)
			MediaPlayer.play(stream) { watched in
				if watched { onWatched() }
				lookups += 1
			}
		} catch {
			failure = error.localizedDescription
		}
	}
}

private extension PlaySource {
	var isPutio: Bool {
		if case .putio = self { return true }
		return false
	}
}
