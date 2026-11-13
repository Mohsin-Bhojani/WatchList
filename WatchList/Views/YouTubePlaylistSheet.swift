//
//  YouTubePlaylistSheet.swift
//  WatchList
//
//  Paste a YouTube playlist link and see what's in it — its name, channel and
//  how many episodes were found — then either link it to a show's season, so
//  those episodes play in the app, or add it as a new show (for a drama TMDb
//  doesn't have).
//

import SwiftUI
import SwiftData
import WatchListCore
import WatchListLibrary

struct YouTubePlaylistSheet: View {
	enum Mode {
		/// Link to one of this show's seasons.
		case link(Show)
		/// Make a new show from it.
		case add
	}

	let mode: Mode
	/// Called with what happened, once it's done: "24 episodes play from YouTube".
	var onDone: (String) -> Void = { _ in }

	@Environment(\.modelContext) private var ctx
	@Environment(\.dismiss) private var dismiss

	@State private var link = ""
	@State private var loading = false
	@State private var error: String?
	@State private var playlist: YouTubePlaylist?
	@State private var name = ""
	@State private var seasonID: UUID?

	private var matches: [Int: YouTubeVideo] { playlist.map { YouTubeEpisodes.match($0.videos) } ?? [:] }

	private var show: Show? {
		if case .link(let show) = mode { return show }
		return nil
	}

	private var seasons: [Season] { show?.sortedSeasons.filter { $0.seasonNumber > 0 } ?? [] }

	var body: some View {
		NavigationStack {
			Form {
				Section {
					HStack {
						TextField("youtube.com/playlist?list=…", text: $link)
							.textInputAutocapitalization(.never)
							.autocorrectionDisabled()
							.keyboardType(.URL)
							.onSubmit { Task { await load() } }
						PasteButton(payloadType: String.self) { strings in
							guard let first = strings.first else { return }
							Task { @MainActor in
								link = first
								await load()
							}
						}
						.labelStyle(.iconOnly)
						.buttonBorderShape(.circle)
					}
					Button {
						Task { await load() }
					} label: {
						HStack {
							Text("Find Episodes")
							if loading {
								Spacer()
								ProgressView()
							}
						}
					}
					.disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || loading)
				} header: {
					Text("Playlist link")
				} footer: {
					Text("On YouTube, open the playlist with every episode, tap Share and copy the link. Episodes play here in YouTube's player, like trailers.")
				}

				if let error {
					Section {
						Label(error, systemImage: "exclamationmark.triangle.fill")
							.foregroundStyle(.orange)
					}
				}

				if let playlist {
					preview(playlist)
				}
			}
			.navigationTitle(show == nil ? "Add from YouTube" : "Link YouTube Playlist")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button(show == nil ? "Add" : "Link", systemImage: "checkmark", role: .confirm, action: confirm)
						.disabled(playlist == nil || matches.isEmpty
						          || (show == nil && name.trimmingCharacters(in: .whitespaces).isEmpty))
				}
			}
			.onAppear {
				seasonID = seasons.last(where: { $0.youtubePlaylistID == nil })?.id ?? seasons.last?.id
				if !YouTubeConfig.isConfigured { error = YouTubeError.notConfigured.errorDescription }
			}
		}
	}

	@ViewBuilder private func preview(_ playlist: YouTubePlaylist) -> some View {
		Section("Found") {
			HStack(spacing: 12) {
				PosterImage(urlString: playlist.thumbnailURL, systemPlaceholder: "play.rectangle")
					.aspectRatio(16 / 9, contentMode: .fill)
					.frame(width: 96, height: 54)
					.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
				VStack(alignment: .leading, spacing: 3) {
					Text(playlist.title)
						.font(.subheadline.weight(.semibold))
						.lineLimit(2)
					if !playlist.channel.isEmpty {
						Text(playlist.channel)
							.font(.caption)
							.foregroundStyle(.secondary)
					}
				}
			}
			LabeledContent("Episodes", value: episodeLine)
			let skipped = playlist.videos.count - matches.count
			if skipped > 0 {
				LabeledContent("Left out", value: "\(skipped) other video\(skipped == 1 ? "" : "s")")
			}
		}
		if show == nil {
			Section("Show name") {
				TextField("Name", text: $name)
			}
		} else if seasons.count > 1 {
			Section("Season") {
				Picker("Season", selection: $seasonID) {
					ForEach(seasons) { season in
						Text(season.displayName).tag(Optional(season.id))
					}
				}
			}
		}
	}

	/// "26 · episodes 1–26", or the count alone when they don't run in a line.
	private var episodeLine: String {
		let numbers = matches.keys.sorted()
		guard let first = numbers.first, let last = numbers.last else { return "None found" }
		return numbers.count == last - first + 1 ? "\(numbers.count) · episodes \(first)–\(last)" : "\(numbers.count)"
	}

	private func load() async {
		error = nil
		guard let id = YouTubePlaylistLink.id(from: link) else {
			error = YouTubeError.badLink.errorDescription
			return
		}
		loading = true
		defer { loading = false }
		do {
			let found = try await YouTubeService.shared.playlist(id: id)
			withAnimation(Glass.smooth) {
				playlist = found
				if name.isEmpty { name = YouTubeEpisodes.showName(fromPlaylist: found.title) }
			}
			if YouTubeEpisodes.match(found.videos).isEmpty {
				error = "No episodes found in that playlist — only teasers and clips, or it's empty."
			}
		} catch {
			self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
		}
	}

	private func confirm() {
		guard let playlist else { return }
		let summary: String
		if let show {
			let season = seasons.first { $0.id == seasonID } ?? seasons.last ?? {
				let first = Season(seasonNumber: 1)
				first.show = show
				show.seasons.append(first)
				return first
			}()
			summary = YouTubeLinker.link(playlist, to: season, context: ctx).summary
		} else {
			let added = YouTubeLinker.addShow(named: name.trimmingCharacters(in: .whitespaces), from: playlist, context: ctx)
			summary = added.title
		}
		Haptics.success()
		onDone(summary)
		dismiss()
	}
}

// MARK: - Episode player

/// At the top of an episode's page when it plays from YouTube, where its still
/// would be: the thumbnail with a play button, then YouTube's player in its
/// place, as trailers play. Open in YouTube is there for channels that don't
/// let their videos play outside YouTube.
struct EpisodeYouTubeCard: View {
	let videoID: String
	let thumbnailURL: String
	let title: String

	@Environment(\.openURL) private var openURL
	@State private var playing = false

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			ZStack {
				if playing {
					YouTubePlayer(videoKey: videoID)
						.onDisappear { playing = false }
				} else {
					Button {
						Haptics.selection()
						withAnimation(Glass.smooth) { playing = true }
					} label: {
						PosterImage(urlString: thumbnailURL, systemPlaceholder: "play.rectangle")
							.overlay { Color.black.opacity(0.2) }
							.overlay {
								Image(systemName: "play.fill")
									.font(.system(.title3, weight: .bold))
									.foregroundStyle(.white)
									.frame(width: 60, height: 60)
									.glassEffect(.regular, in: Circle())
							}
					}
					.buttonStyle(.plain)
					.accessibilityLabel("Play \(title)")
				}
			}
			.aspectRatio(16 / 9, contentMode: .fit)
			.frame(maxWidth: .infinity)
			.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
			.shadow(color: .black.opacity(0.4), radius: 20, y: 10)

			HStack(spacing: 8) {
				Label(playing ? "Playing here, from YouTube" : "Plays here, from YouTube", systemImage: "play.rectangle.fill")
					.font(.system(.caption, weight: .semibold))
					.foregroundStyle(.white.opacity(0.7))
				Spacer(minLength: 0)
				if let url = YouTubePlaylistLink.watchURL(videoID) {
					Button {
						playing = false
						openURL(url)
					} label: {
						Label("Open in YouTube", systemImage: "arrow.up.right")
							.font(.system(.caption, weight: .semibold))
							.foregroundStyle(.white)
					}
					.buttonStyle(.plain)
				}
			}
			.padding(.horizontal, 4)
		}
	}
}
