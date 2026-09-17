//
//  PhoneHomeView.swift
//  WatchList
//
//  The iPhone Home tab, after the "1a Home" design:
//    - "Home" and a profile button across the top, over the hero — on an iPad,
//      either side of the floating tab bar
//    - a full-bleed hero with one swipeable page per show you're Watching,
//      showing the episode it's up to and Mark Watched
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

	/// The whole screen, bars included — what the design's proportions are of.
	/// Nonisolated because geometry is read off the main actor.
	private nonisolated struct ScreenMetrics: Equatable, Sendable {
		var width: CGFloat = 0
		var height: CGFloat = 0
		/// The status bar and Dynamic Island.
		var topInset: CGFloat = 0
	}

	/// Two-thirds of the screen, as drawn — never so short that the title and
	/// button crowd the artwork.
	private var heroHeight: CGFloat { max(screen.height * 0.65, 420) }

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
							             topPadding: max(screen.topInset, 20))
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
			.background(GlassBackground())
			.screenBar("Home", onBand: !watching.isEmpty)
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
						             onBand: { heroScroll.bands[show.id] = $0 },
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
			.overlay(alignment: .bottom) {
				if count > 1 { pageIndicator(count: count) }
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

	private var emptyHero: some View {
		VStack(spacing: 12) {
			Image(systemName: "play.tv")
				.font(.system(size: 42, weight: .light))
				.foregroundStyle(Glass.accent)
			Text("Nothing in progress")
				.font(.system(size: 26, weight: .bold))
				.foregroundStyle(Glass.ink)
			Text("Set a show to Watching and the episode you're up to shows up here.")
				.font(.system(size: 15))
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
			Button("Open Shows") { openTab(.shows) }
				.buttonStyle(.glass)
				.controlSize(.large)
				.padding(.top, 6)
		}
		.padding(.horizontal, 36)
		// Clear of the header laid over the top — on an iPad it's in the bar.
		.padding(.top, max(screen.topInset, 20) + (ScreenHeader.isInBar ? 0 : 56))
		.frame(maxWidth: .infinity)
		.frame(height: heroHeight * 0.8)
		.background(LinearGradient(colors: [Glass.accent.opacity(0.16), .clear],
		                           startPoint: .top, endPoint: .bottom))
	}

	// MARK: To Watch

	private var toWatch: some View {
		shelf("To Watch", items: HomeFeed.toWatch(shows: shows, films: films), showsRating: false,
		      empty: "Titles you add as To Watch wait here, newest first. Anything rated Skip is left out.") {
			ToWatchListView()
		}
	}

	// MARK: Recently watched

	private var recentlyWatched: some View {
		shelf("Recently watched",
		      items: HomeFeed.recentlyWatched(shows: shows, films: films),
		      showsRating: true,
		      empty: "Titles you mark Watched land here, the most recent first.") {
			RecentlyWatchedListView()
		}
	}

	/// A heading with All, then a sideways row of up to 20 poster cards — with
	/// their rating strip, or as posters alone.
	private func shelf<All: View>(_ title: String, items: [WatchedTitle], showsRating: Bool, empty: String,
	                              @ViewBuilder all: @escaping () -> All) -> some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(alignment: .firstTextBaseline) {
				Text(title)
					.font(.system(size: 22, weight: .bold))
					.foregroundStyle(Glass.ink)
				Spacer()
				if !items.isEmpty {
					NavigationLink { all() } label: {
						Text("All")
							.font(.system(size: 16, weight: .semibold))
							.foregroundStyle(Glass.accent)
					}
				}
			}
			.padding(.horizontal, 18)

			if items.isEmpty {
				Text(empty)
					.font(.system(size: 14, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(16)
					.glass(cornerRadius: 18)
					.padding(.horizontal, 18)
			} else {
				ScrollView(.horizontal) {
					LazyHStack(alignment: .top, spacing: 12) {
						ForEach(Array(items.prefix(20))) { item in
							NavigationLink { item.destination } label: {
								RecentlyWatchedCard(item: item, showsRating: showsRating)
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
}

// MARK: - All

/// Home's "All": every Watched show and film, most recently marked first.
struct RecentlyWatchedListView: View {
	@Query(sort: \Show.dateAdded, order: .reverse) private var shows: [Show]
	@Query(sort: \Film.dateAdded, order: .reverse) private var films: [Film]
	var body: some View {
		let recent = HomeFeed.recentlyWatched(shows: shows, films: films)
		ZStack {
			GlassBackground()
			ScrollView {
				LazyVStack(spacing: 10) {
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
	@Query(sort: \Show.dateAdded, order: .reverse) private var shows: [Show]
	@Query(sort: \Film.dateAdded, order: .reverse) private var films: [Film]

	var body: some View {
		ZStack {
			GlassBackground()
			ScrollView {
				LazyVStack(spacing: 10) {
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
