//
//  PhoneHomeView.swift
//  WatchList
//
//  The iPhone Home tab, after the "1a Home" design:
//    - "Home" and a profile button across the top, over the hero — on an iPad,
//      either side of the floating tab bar, in a bar that's see-through over
//      the hero until the page scrolls
//    - a full-bleed hero with one swipeable page per show you're Watching,
//      showing the episode it's up to and Mark Watched — on an iPad held
//      sideways, laid out sideways too (HomeHeroPage)
//    - To Watch: shows and films still to watch, newest added first, leaving out
//      any rated Skip
//    - Recently watched: shows and films in the order they were marked Watched
//
//  The navigation bar is hidden so the hero's colour band runs up under the
//  status bar; the artwork itself starts below it. The band sits behind the
//  whole page and fades into it, turning over to the next show's colour as the
//  hero is swiped.
//

import SwiftUI
import SwiftData
import WatchListCore
import WatchListLibrary

struct PhoneHomeView: View {
	/// Switches tabs — the empty hero points at Shows.
	let openTab: (PhoneTab) -> Void

	@Query(sort: \Show.dateAdded, order: .reverse) private var shows: [Show]
	@Query(sort: \Film.dateAdded, order: .reverse) private var films: [Film]
	@AppStorage("autoMarkEpisodesWatched") private var cascadeWatched = true

	@State private var screen = ScreenMetrics()
	/// The hero page in view: an index into the looping pages, copies included.
	@State private var heroPage: Int?
	@State private var heroScroll = HeroScroll()
	@State private var openedShow: Show?
	/// The episode Mark Watched is asking to rate.
	@State private var ratingEpisode: Episode?
	@State private var barScroll = BarScroll()

	/// How far Home has scrolled, as far as an iPad's bar cares.
	private struct BarScroll: Equatable {
		/// Off the top: the bar's soft edge comes back, so nothing reads through
		/// it as it goes under.
		var moved = false
		/// The hero gone up from under the bar, so its words turn to ink.
		var pastHero = false
	}

	/// The whole screen, bars included — what the design's proportions are of.
	/// Nonisolated because geometry is read off the main actor.
	private nonisolated struct ScreenMetrics: Equatable, Sendable {
		var width: CGFloat = 0
		var height: CGFloat = 0
		/// The status bar and Dynamic Island.
		var topInset: CGFloat = 0
	}

	/// Two-thirds of the screen, as drawn — never so short that the title and
	/// button crowd the artwork. An iPad upright is taller than a backdrop needs
	/// at its width, so there it stops at about the art's own shape.
	private var heroHeight: CGFloat {
		let tall = max(screen.height * 0.65, 420)
		return isPad ? min(tall, max(screen.width * 0.72, 420)) : tall
	}

	/// Keyed on the device, like the app's shell.
	private var isPad: Bool { ScreenHeader.isInBar }

	/// An iPad held sideways — or any page wider than it's tall — gets the
	/// hero's sideways layout.
	private var wideHero: Bool { isPad && screen.width > screen.height }

	var body: some View {
		let watching = HomeFeed.watching(shows)
		let pages = HeroLoop.pages(count: watching.count).map { watching[$0] }
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 0) {
					hero(watching, pages: pages)
						// Over the hero rather than inside a page, so it stays put
						// while the hero is swiped and scrolls away with it.
						.overlay(alignment: .top) {
							ScreenHeader(title: "Home", onBand: !watching.isEmpty,
							             topPadding: max(screen.topInset, 20),
							             subtitle: watching.isEmpty ? nil : "\(watching.count) watching")
						}
					VStack(alignment: .leading, spacing: 30) {
						toWatch
						recentlyWatched
					}
					.padding(.top, 28)
					.padding(.bottom, 24)
				}
				// Inside the scroll content, so the colour scrolls with the hero.
				.background(alignment: .top) {
					if !watching.isEmpty {
						HeroBackdrop(scroll: heroScroll, pages: pages, heroHeight: heroHeight,
						             pageWidth: screen.width, topInset: screen.topInset)
					}
				}
			}
			.ignoresSafeArea(edges: .top)
			.scrollsToTopOnReselect(.home)
			// On an iPad the bar is over the hero: see-through while the page is at
			// its top, then the usual soft edge once anything scrolls under it.
			.onScrollGeometryChange(for: BarScroll.self) { geometry in
				let offset = geometry.contentOffset.y + geometry.contentInsets.top
				return BarScroll(moved: offset > 12,
				                 pastHero: offset > heroHeight - max(screen.topInset, 20) - 64)
			} action: { _, scroll in
				withAnimation(.easeInOut(duration: 0.2)) { barScroll = scroll }
			}
			.scrollEdgeEffectHidden(isPad && !watching.isEmpty && !barScroll.moved, for: .top)
			.background(GlassBackground())
			.screenBar("Home", onBand: !watching.isEmpty && !barScroll.pastHero)
			// Nothing Watching: the palette lights the pages again.
			.onChange(of: watching.first?.id, initial: true) { _, first in
				if first == nil { BackdropLight.shared.tone = nil }
			}
			.navigationDestination(item: $openedShow) { PhoneShowDetailView(show: $0) }
		}
		// Measured here, outside the scroll view that ignores the top safe area
		// and above the tab bar's bottom inset, so both bars count.
		.onGeometryChange(for: ScreenMetrics.self) { proxy in
			ScreenMetrics(width: proxy.size.width,
			              height: proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom,
			              topInset: proxy.safeAreaInsets.top)
		} action: { screen = $0 }
	}

	// MARK: Hero

	/// `pages` is the looping layout from `HeroLoop`: the shows with a copy of
	/// each end round the other.
	@ViewBuilder private func hero(_ watching: [Show], pages: [Show]) -> some View {
		if watching.isEmpty {
			emptyHero
		} else {
			let count = watching.count
			ScrollView(.horizontal) {
				LazyHStack(spacing: 0) {
					ForEach(Array(pages.enumerated()), id: \.offset) { _, show in
						HomeHeroPage(show: show,
						             width: screen.width,
						             height: heroHeight,
						             topInset: screen.topInset,
						             textBottom: count > 1 ? 34 : 23,
						             cascadeWatched: cascadeWatched,
						             wide: wideHero,
						             onBand: { tone in
						             	heroScroll.bands[show.id] = tone
						             	// The first Watching show lights every page's backdrop.
						             	if show.id == watching.first?.id { BackdropLight.shared.tone = tone }
						             },
						             onRateEpisode: { ratingEpisode = $0 }) {
							openedShow = show
						}
						.containerRelativeFrame(.horizontal)
					}
				}
				.scrollTargetLayout()
			}
			.scrollTargetBehavior(.paging)
			.scrollIndicators(.hidden)
			// Opens on the first real page rather than the copy in front of it.
			.scrollPosition(id: Binding(
				get: { heroPage.flatMap { $0 < pages.count ? $0 : nil } ?? HeroLoop.start(count: count) },
				set: { heroPage = $0 }))
			.onScrollPhaseChange { _, phase in
				if phase == .idle { settleHero(count: count) }
			}
			.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in
				heroScroll.offset = x
			}
			// A different set of shows rebuilds the pages, so none keeps the art
			// of the show that used to sit in its place.
			.id(watching.map(\.id))
			.onChange(of: count) { settleHero(count: count) }
			.sheet(item: $ratingEpisode) { EpisodeRatingSheet(episode: $0) }
			.frame(height: heroHeight)
			// Sideways, under the words they page through.
			.overlay(alignment: wideHero ? .bottomLeading : .bottom) {
				if count > 1 {
					pageIndicator(count: count)
						.padding(.leading, wideHero ? HomeHeroPage.wideInset : 0)
				}
			}
		}
	}

	/// Resting on a loop copy at either end, swaps to the real page it copies
	/// without animation — the same show, so nothing visibly moves — and the
	/// swipe can carry on round.
	private func settleHero(count: Int) {
		let settled = HeroLoop.settled(heroPage ?? HeroLoop.start(count: count), count: count)
		guard settled != heroPage else { return }
		var transaction = Transaction()
		transaction.disablesAnimations = true
		withTransaction(transaction) { heroPage = settled }
	}

	/// Dots for a handful of shows; past that a count reads better than a row
	/// of specks. Follows the show in view, so a loop copy lights its show's dot.
	@ViewBuilder private func pageIndicator(count: Int) -> some View {
		let current = HeroLoop.showIndex(ofPage: heroPage ?? HeroLoop.start(count: count), count: count)
		Group {
			if count <= 8 {
				HStack(spacing: 7) {
					ForEach(0..<count, id: \.self) { index in
						Circle()
							.fill(.white.opacity(index == current ? 0.95 : 0.4))
							.frame(width: 7, height: 7)
					}
				}
			} else {
				Text("\(current + 1) of \(count)")
					.font(.system(size: 12, weight: .semibold))
					.foregroundStyle(.white.opacity(0.85))
			}
		}
		.padding(.bottom, 12)
		.allowsHitTesting(false)
		.accessibilityHidden(true)
	}

	/// After design A of the alternatives: the shape of what goes here — a glass
	/// poster between two outlines — then what to do, two ways in.
	private var emptyHero: some View {
		VStack(spacing: 14) {
			ZStack {
				ForEach([-1.0, 1.0], id: \.self) { side in
					RoundedRectangle(cornerRadius: 12, style: .continuous)
						.strokeBorder(Glass.ink.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
						.frame(width: 76, height: 114)
						.rotationEffect(.degrees(9 * side))
						.offset(x: 44 * side, y: 8)
				}
				Image(systemName: "play.fill")
					.font(.system(size: 26))
					.foregroundStyle(Glass.accent)
					.frame(width: 76, height: 114)
					.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			}
			.frame(height: 130)
			.accessibilityHidden(true)
			Text("Nothing on Up Next")
				.font(.system(size: 24, weight: .bold))
				.foregroundStyle(Glass.ink)
			Text("Start a show and the next episode waits here, with Mark Watched one tap away.")
				.font(.system(size: 15))
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
			HStack(spacing: 10) {
				Button("Pick from your shows") { openTab(.shows) }
					.buttonStyle(.glassProminent)
				Button("Discover") { openTab(.discover) }
					.buttonStyle(.glass)
			}
			.controlSize(.large)
			.padding(.top, 4)
		}
		.padding(.horizontal, 30)
		// Clear of the header laid over the top — on an iPad it's in the bar.
		.padding(.top, max(screen.topInset, 20) + (ScreenHeader.isInBar ? 0 : 56))
		.frame(maxWidth: .infinity)
		.frame(height: heroHeight * 0.85)
	}

	// MARK: To Watch

	private var toWatch: some View {
		shelf("To Watch", items: HomeFeed.toWatch(shows: shows, films: films), showsRating: false,
		      empty: "Nothing waiting. Add a title from Discover or search.", emptyAction: ("Discover", .discover)) {
			ToWatchListView()
		}
	}

	// MARK: Recently watched

	private var recentlyWatched: some View {
		shelf("Recently watched",
		      items: HomeFeed.recentlyWatched(shows: shows, films: films),
		      showsRating: true,
		      empty: "Titles you mark Watched land here, the most recent first.", emptyAction: ("Shows", .shows)) {
			RecentlyWatchedListView()
		}
	}

	/// After design A of the alternatives: the heading, counted, is itself the
	/// way to the whole list; under it a sideways rail of title cards that lets
	/// the next one peek in, so there's plainly more. Empty, a glass row says so
	/// and offers a way in.
	private func shelf<All: View>(_ title: String, items: [WatchedTitle], showsRating: Bool, empty: String,
	                              emptyAction: (String, PhoneTab), @ViewBuilder all: @escaping () -> All) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			Group {
				if items.isEmpty {
					heading(title, count: 0, chevron: false)
				} else {
					NavigationLink { all() } label: { heading(title, count: items.count, chevron: true) }
						.buttonStyle(.plain)
				}
			}
			.padding(.horizontal, 18)

			if items.isEmpty {
				HStack(spacing: 12) {
					Text(empty)
						.font(.system(size: 14, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
						.frame(maxWidth: .infinity, alignment: .leading)
					Button(emptyAction.0) { openTab(emptyAction.1) }
						.buttonStyle(.glass)
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 12)
				.glass(cornerRadius: 18)
				.padding(.horizontal, 18)
			} else {
				ScrollView(.horizontal) {
					LazyHStack(alignment: .top, spacing: 12) {
						ForEach(Array(items.prefix(20))) { item in
							NavigationLink { item.destination } label: {
								FadedPosterCard(item: item)
									.frame(width: 128)
							}
							.buttonStyle(.pressable)
						}
					}
					.padding(.horizontal, 18)
				}
				.scrollIndicators(.hidden)
			}
		}
	}

	private func heading(_ title: String, count: Int, chevron: Bool) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: 6) {
			Text(title)
				.font(.system(size: 22, weight: .bold))
				.foregroundStyle(Glass.ink)
			Text("\(count)")
				.font(.system(size: 15, weight: .medium).monospacedDigit())
				.foregroundStyle(.secondary)
			if chevron {
				Image(systemName: "chevron.right")
					.font(.system(size: 14, weight: .bold))
					.foregroundStyle(.secondary)
			}
			Spacer(minLength: 0)
		}
		.contentShape(Rectangle())
		.accessibilityElement(children: .combine)
		.accessibilityHint(chevron ? "Shows them all" : "")
	}
}

// MARK: - All

/// The columns Home's "All" lists run in: one on a phone, as many as fit
/// across an iPad.
private func allListColumns(_ sizeClass: UserInterfaceSizeClass?) -> [GridItem] {
	sizeClass == .regular
		? [GridItem(.adaptive(minimum: 340), spacing: 12, alignment: .top)]
		: [GridItem(.flexible())]
}

/// Home's "All": every Watched show and film, most recently marked first.
struct RecentlyWatchedListView: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Query(sort: \Show.dateAdded, order: .reverse) private var shows: [Show]
	@Query(sort: \Film.dateAdded, order: .reverse) private var films: [Film]
	var body: some View {
		let recent = HomeFeed.recentlyWatched(shows: shows, films: films)
		ZStack {
			GlassBackground()
			ScrollView {
				LazyVGrid(columns: allListColumns(horizontalSizeClass), spacing: 10) {
					ForEach(recent) { item in
						NavigationLink { item.destination } label: {
							GlassRow(title: item.title, subtitle: subtitle(for: item),
							         thumbURL: item.posterURL, thumbPlaceholder: item.placeholder,
							         rating: item.rating)
						}
						.buttonStyle(.pressable)
					}
				}
				.padding(18)
			}
		}
		.navigationTitle("Recently Watched")
		.navigationBarTitleDisplayMode(.inline)
		.toolbarBackground(.hidden, for: .navigationBar)
	}

	private func subtitle(for item: WatchedTitle) -> String {
		guard let date = item.watchedAt else { return item.kindLabel }
		return "\(item.kindLabel) · Watched \(date.formatted(.relative(presentation: .named)))"
	}
}

// MARK: - To Watch

/// Home's To Watch "All": every show and film still To Watch and not rated
/// Skip, newest added first.
struct ToWatchListView: View {
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass
	@Query(sort: \Show.dateAdded, order: .reverse) private var shows: [Show]
	@Query(sort: \Film.dateAdded, order: .reverse) private var films: [Film]

	var body: some View {
		ZStack {
			GlassBackground()
			ScrollView {
				LazyVGrid(columns: allListColumns(horizontalSizeClass), spacing: 10) {
					ForEach(HomeFeed.toWatch(shows: shows, films: films)) { item in
						NavigationLink { item.destination } label: {
							GlassRow(title: item.title,
							         subtitle: "\(item.kindLabel) · Added \(item.dateAdded.formatted(.relative(presentation: .named)))",
							         thumbURL: item.posterURL, thumbPlaceholder: item.placeholder,
							         rating: item.rating)
						}
						.buttonStyle(.pressable)
					}
				}
				.padding(18)
			}
		}
		.navigationTitle("To Watch")
		.navigationBarTitleDisplayMode(.inline)
		.toolbarBackground(.hidden, for: .navigationBar)
	}
}
