//
//  UpNextPage.swift
//  WatchList Watch App
//
//  Up Next, after the iPhone's Home hero: a page for each show set to Watching,
//  swiped through sideways, each with the show's artwork fading into its colour,
//  the episode it's up to and Mark Watched. Mark Watched opens the rating —
//  Skip, Watch or Rewatch — and picking one is what marks the episode; closing
//  it changes nothing. Double Tap presses Mark Watched on the show in view.
//  Once marked, the button makes way for a note saying so, with Undo, for a
//  few seconds.
//

import SwiftUI

struct UpNextPage: View {
	@Environment(WatchStore.self) private var store

	@State private var selection: UUID?
	@State private var rating: UpNextItem?
	@State private var note: MarkedNote?
	/// Each show's colour, once its artwork is in.
	@State private var tones: [UUID: Color] = [:]

	var body: some View {
		let items = store.upNext
		Group {
			if items.isEmpty {
				emptyMessage
					.containerBackground(Color.black.gradient, for: .tabView)
			} else {
				pager(items)
			}
		}
		.sheet(item: $rating) { item in
			if let episode = item.next {
				EpisodeRatingView(showTitle: item.show.title, episode: episode) { tier in
					rating = nil
					mark(episode, of: item.show, tier: tier)
				}
			}
		}
		.onChange(of: items.map(\.show.artworkURL), initial: true) { _, urls in
			// While the iPhone or Wi-Fi is about, so the art is there without them.
			Artwork.prefetch(urls.map(Artwork.backdrop))
		}
	}

	private func pager(_ items: [UpNextItem]) -> some View {
		let current = selection ?? items.first?.id
		return TabView(selection: $selection) {
			ForEach(items) { item in
				ShowPage(item: item, isCurrent: item.id == current,
				         note: note?.showID == item.id ? note : nil,
				         onTone: { tones[item.id] = $0 },
				         onMarkWatched: { rating = item },
				         onUndo: undo)
					.containerBackground(tone(for: item).gradient, for: .tabView)
					.tag(Optional(item.id))
			}
		}
		.tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .always : .never))
	}

	@ViewBuilder
	private var emptyMessage: some View {
		switch (store.snapshot, store.phone) {
		case (nil, .notInstalled):
			MessageView(systemImage: "iphone", title: "Up Next comes from your iPhone",
			            detail: "Install WatchList on your iPhone and set a show to Watching.")
		case (nil, _):
			MessageView(systemImage: "iphone", title: "Open WatchList on your iPhone",
			            detail: "Your shows appear here once it has synced.")
		default:
			MessageView(systemImage: "play.tv", title: "Nothing in progress",
			            detail: "Set a show to Watching on your iPhone.")
		}
	}

	private func tone(for item: UpNextItem) -> Color {
		tones[item.id] ?? Artwork.cached(Artwork.backdrop(item.show.artworkURL))?.tone
			?? Artwork.placeholderTone(for: item.show.title)
	}

	private func mark(_ episode: UpNextEpisode, of show: UpNextShow, tier: EpisodeTier?) {
		store.markWatched(episode, tier: tier)
		Haptics.success()
		let marked = MarkedNote(showID: show.id, episode: episode, tier: tier)
		withAnimation(.smooth) { note = marked }
		Task {
			try? await Task.sleep(for: .seconds(4))
			if note?.id == marked.id { withAnimation(.smooth) { note = nil } }
		}
	}

	private func undo(_ marked: MarkedNote) {
		store.undoWatched(marked.episode)
		Haptics.click()
		withAnimation(.smooth) { note = nil }
	}
}

// MARK: - A show's page

private struct ShowPage: View {
	let item: UpNextItem
	/// The page in view: only its button answers Double Tap.
	let isCurrent: Bool
	/// The episode just marked on this show, while Undo is offered.
	let note: MarkedNote?
	let onTone: (Color) -> Void
	let onMarkWatched: () -> Void
	let onUndo: (MarkedNote) -> Void

	var body: some View {
		ZStack(alignment: .bottom) {
			artwork
			details
		}
	}

	/// Across the top, fading in from above and out into the page's colour below.
	private var artwork: some View {
		GeometryReader { proxy in
			ArtworkImage(url: Artwork.backdrop(item.show.artworkURL), onTone: onTone) {
				Image(systemName: "tv")
					.font(.largeTitle)
					.foregroundStyle(.white.opacity(0.25))
			}
			.frame(width: proxy.size.width, height: proxy.size.height * 0.62)
			.mask {
				LinearGradient(stops: [.init(color: .clear, location: 0),
				                       .init(color: .black, location: 0.25),
				                       .init(color: .black, location: 0.55),
				                       .init(color: .clear, location: 1)],
				               startPoint: .top, endPoint: .bottom)
			}
		}
		.ignoresSafeArea()
		.accessibilityHidden(true)
	}

	private var details: some View {
		VStack(spacing: 2) {
			Text(progressLine)
				.font(.footnote.weight(.medium))
				.foregroundStyle(.white.opacity(0.9))
				.lineLimit(1)
			Text(item.show.title)
				.font(.title3.bold())
				.multilineTextAlignment(.center)
				.lineLimit(2)
				.minimumScaleFactor(0.8)
			if let note {
				MarkedNoteView(note: note) { onUndo(note) }
					.padding(.top, 6)
					.transition(.opacity)
			} else if item.next != nil {
				Button(action: onMarkWatched) {
					Text("Mark Watched")
						.frame(maxWidth: .infinity)
				}
				.buttonStyle(.borderedProminent)
				.handGestureShortcut(.primaryAction, isEnabled: isCurrent)
				.padding(.top, 6)
				.accessibilityHint(item.next.map { "Rates \($0.code) and marks it watched" } ?? "")
			}
		}
		.shadow(color: .black.opacity(0.5), radius: 4, y: 1)
		.padding(.horizontal, 8)
		.padding(.bottom, 14)
	}

	/// The episode it's up to, or why there's none.
	private var progressLine: String {
		if let next = item.next {
			return next.title.isEmpty ? next.code : "\(next.code) · \(next.title)"
		}
		if item.show.episodeCount == 0 { return "No episodes tracked" }
		if item.show.remaining > item.show.upcoming.count { return "More on your iPhone" }
		return "All caught up"
	}
}

// MARK: - Marked

/// An episode just marked, for the note that offers Undo.
struct MarkedNote: Identifiable, Equatable {
	let id = UUID()
	let showID: UUID
	let episode: UpNextEpisode
	let tier: EpisodeTier?
}

/// "S1 · E4 watched", its rating, and Undo.
private struct MarkedNoteView: View {
	let note: MarkedNote
	let onUndo: () -> Void

	var body: some View {
		HStack(spacing: 6) {
			VStack(alignment: .leading, spacing: 0) {
				Label("Watched", systemImage: "checkmark")
					.font(.footnote.weight(.semibold))
				Text(note.tier.map { "\(note.episode.code) · \($0.rawValue)" } ?? note.episode.code)
					.font(.caption2)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			Spacer(minLength: 4)
			Button("Undo", action: onUndo)
				.buttonStyle(.bordered)
				.buttonBorderShape(.capsule)
				.fixedSize(horizontal: true, vertical: false)
		}
		.padding(.leading, 12)
		.padding(.trailing, 4)
		.padding(.vertical, 4)
		.background(.black.opacity(0.6), in: Capsule())
		.accessibilityElement(children: .contain)
	}
}
