//
//  UpNextPage.swift
//  WatchList Watch App
//
//  Up Next, after the iPhone's Home hero: a page for each show set to Watching,
//  swiped sideways and round and round (HeroLoop, shared with the iPhone). Each
//  page has the hero's artwork fading into the show's colour, the episode it's
//  up to, its title, and Mark Watched in Liquid Glass. Mark Watched opens the
//  rating — Skip, Watch or Rewatch — and picking one is what marks the episode;
//  closing it changes nothing. Double Tap presses Mark Watched on the show in
//  view. Once marked, the button makes way for Undo for six seconds.
//

import SwiftUI

struct UpNextPage: View {
	@Environment(WatchStore.self) private var store
	@Environment(\.isPageInView) private var inView

	/// The page in view, among HeroLoop's pages — copies at either end included.
	@State private var page = 1
	@State private var rating: UpNextItem?
	@State private var note: MarkedNote?
	/// Each show's colour, once its artwork is in.
	@State private var tones: [UUID: Color] = [:]

	var body: some View {
		let items = store.upNext
		Group {
			if items.isEmpty {
				emptyMessage
					.background(Color.black.gradient, ignoresSafeAreaEdges: .all)
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
		.preference(key: PageSheetKey.self, value: rating != nil)
		.onChange(of: items.map(\.show.artworkURL), initial: true) { _, urls in
			// While the iPhone or Wi-Fi is about, so the art is there without them.
			Artwork.prefetch(urls.map(Artwork.backdrop))
		}
	}

	private func pager(_ items: [UpNextItem]) -> some View {
		let count = items.count
		let pages = HeroLoop.pages(count: count)
		let current = HeroLoop.showIndex(ofPage: page, count: count)
		return TabView(selection: $page) {
			ForEach(Array(pages.enumerated()), id: \.offset) { offset, index in
				let item = items[index]
				ShowPage(item: item, tone: tone(for: item), isCurrent: inView && offset == page,
				         note: note?.showID == item.id ? note : nil,
				         dots: count > 1 ? PageDots(count: count, current: index) : nil,
				         onTone: { tones[item.id] = $0 },
				         onMarkWatched: { rating = item },
				         onUndo: undo)
					.tag(offset)
			}
		}
		.tabViewStyle(.page(indexDisplayMode: .never))
		// Behind the time: the colour of the show in view.
		.background(tone(for: items[min(current, count - 1)]), ignoresSafeAreaEdges: .all)
		// A different set of shows starts again at the first.
		.id(items.map(\.show.id))
		.onChange(of: page) { _, landed in settle(landed, count: count) }
		.onChange(of: count, initial: true) { _, newCount in
			page = min(max(page, HeroLoop.start(count: newCount)), HeroLoop.pages(count: newCount).count - 1)
		}
	}

	/// Resting on a loop copy at either end, swaps to the real page it copies
	/// without animation, once the swipe has landed — the same show, so nothing
	/// visibly moves — and the swipe can carry on round.
	private func settle(_ landed: Int, count: Int) {
		let real = HeroLoop.settled(landed, count: count)
		guard real != landed else { return }
		Task {
			try? await Task.sleep(for: .milliseconds(350))
			guard page == landed else { return }
			var still = Transaction()
			still.disablesAnimations = true
			withTransaction(still) { page = real }
		}
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
			try? await Task.sleep(for: .seconds(6))
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

/// One show, laid out as the iPhone's hero page: the artwork across the top,
/// fading in at its top and out into the show's colour below, with the episode,
/// the title and Mark Watched on the fade.
private struct ShowPage: View {
	let item: UpNextItem
	let tone: Color
	/// The page in view: only its button answers Double Tap.
	let isCurrent: Bool
	/// The episode just marked on this show, while Undo is offered.
	let note: MarkedNote?
	let dots: PageDots?
	let onTone: (Color) -> Void
	let onMarkWatched: () -> Void
	let onUndo: (MarkedNote) -> Void

	var body: some View {
		ZStack(alignment: .bottom) {
			artwork
			details
		}
		.background { tone.ignoresSafeArea() }
		// Down into the space the page keeps free below, which the details
		// otherwise leave empty.
		.ignoresSafeArea(edges: .bottom)
	}

	/// The top two-thirds of the screen, faded as the iPhone's hero fades: over
	/// its top quarter and its bottom 40%.
	private var artwork: some View {
		GeometryReader { proxy in
			ArtworkImage(url: Artwork.backdrop(item.show.artworkURL), onTone: onTone) {
				Color.clear
			}
			.frame(width: proxy.size.width, height: proxy.size.height * 0.68)
			.mask {
				LinearGradient(stops: [.init(color: .clear, location: 0),
				                       .init(color: .black, location: 0.24),
				                       .init(color: .black, location: 0.6),
				                       .init(color: .clear, location: 1)],
				               startPoint: .top, endPoint: .bottom)
			}
		}
		.ignoresSafeArea()
		.allowsHitTesting(false)
		.accessibilityHidden(true)
	}

	private var details: some View {
		VStack(spacing: 1) {
			Text(progressLine)
				.font(.system(size: 13, weight: .medium))
				.foregroundStyle(.white.opacity(0.92))
				.lineLimit(1)
				.minimumScaleFactor(0.8)
				.shadow(color: .black.opacity(0.25), radius: 3, y: 1)
			Text(item.show.title)
				.font(.system(size: 18, weight: .bold))
				.foregroundStyle(.white)
				.multilineTextAlignment(.center)
				.lineLimit(2)
				.minimumScaleFactor(0.75)
				.shadow(color: .black.opacity(0.25), radius: 5, y: 1)

			Group {
				if let note {
					undoButton(note)
				} else if item.next != nil {
					Button(action: onMarkWatched) {
						GlassPill { Text("Mark Watched") }
					}
					.buttonStyle(.plain)
					.handGestureShortcut(.primaryAction, isEnabled: isCurrent)
					.accessibilityLabel(item.next.map { "Mark \($0.line) watched" } ?? "Mark Watched")
				}
			}
			.padding(.top, 6)
			.transition(.opacity)

			if let dots {
				dots.padding(.top, 5)
			}
		}
		.padding(.horizontal, 12)
		.padding(.bottom, dots == nil ? 12 : 8)
	}

	/// In Mark Watched's place for a few seconds after marking.
	private func undoButton(_ note: MarkedNote) -> some View {
		Button { onUndo(note) } label: {
			GlassPill { Label("Undo", systemImage: "arrow.uturn.backward") }
		}
		.buttonStyle(.plain)
		.accessibilityLabel("Undo, \(note.episode.line) watched")
	}

	/// What the hero says above the title: the episode it's up to, or why
	/// there's none.
	private var progressLine: String {
		if let next = item.next { return next.line }
		if item.show.episodeCount == 0 { return "No episodes tracked" }
		if item.show.remaining > item.show.upcoming.count { return "More on your iPhone" }
		return "All \(item.show.episodeCount) episodes watched"
	}
}

/// A button's label in a Liquid Glass capsule, sized to its text as the iPhone
/// hero's Mark Watched is — smaller than the watch's standard glass button,
/// with the tap area kept a little taller than the capsule.
private struct GlassPill<Content: View>: View {
	@ViewBuilder let content: Content

	var body: some View {
		content
			.font(.system(size: 14, weight: .medium))
			.foregroundStyle(.white)
			.lineLimit(1)
			.padding(.horizontal, 14)
			.padding(.vertical, 8)
			.glassEffect(.regular.interactive(), in: Capsule())
			.padding(.vertical, 4)
			.contentShape(Rectangle())
	}
}

/// Dots for a handful of shows, following the show in view; past that, a count.
private struct PageDots: View, Equatable {
	let count: Int
	let current: Int

	var body: some View {
		Group {
			if count <= 8 {
				HStack(spacing: 5) {
					ForEach(0..<count, id: \.self) { index in
						Circle()
							.fill(.white.opacity(index == current ? 0.95 : 0.4))
							.frame(width: 5, height: 5)
					}
				}
			} else {
				Text("\(current + 1) of \(count)")
					.font(.system(size: 11, weight: .semibold))
					.foregroundStyle(.white.opacity(0.85))
			}
		}
		.accessibilityElement()
		.accessibilityLabel("Show \(current + 1) of \(count)")
	}
}

// MARK: - Marked

/// An episode just marked, for Undo.
struct MarkedNote: Identifiable, Equatable {
	let id = UUID()
	let showID: UUID
	let episode: UpNextEpisode
	let tier: EpisodeTier?
}

extension UpNextEpisode {
	/// "Season 2 · Episode 8", as the iPhone's hero says it — "Specials" for season 0.
	var line: String {
		let season = seasonNumber == 0 ? "Specials" : "Season \(seasonNumber)"
		return "\(season) · Episode \(episodeNumber)"
	}
}
