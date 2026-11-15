//
//  HomeHero.swift
//  WatchList
//
//  The pieces of the iPhone Home screen: a full-bleed hero page for a show in
//  progress, the colour backdrop the hero pages share, and the poster card on
//  the Recently watched row.
//

import SwiftUI
import UIKit
import Observation
import WatchListCore
import WatchListLibrary

/// One page of the Home hero, after the "1a Home" design. The artwork sits
/// clear of the status bar and Dynamic Island and fades at top and bottom into
/// the band colour behind it — drawn by `HeroBackdrop`, not the page, so it can
/// run on into the rest of Home and change as the hero is swiped. The page
/// samples that colour from its artwork (see `ArtworkBand`) and hands it up.
/// The episode the show is up to, its title and Mark Watched sit on the lower
/// fade; tapping anywhere else on the page opens the show, and the › beside
/// Mark Watched opens the episode itself — to rate it, date it or play it.
///
/// On an iPad wider than it's tall, the page is laid out sideways instead: the
/// artwork at its own shape on the trailing side, fading in from the band, and
/// on the leading side the episode, its name and synopsis, how far through the
/// show is, and Mark Watched.
struct HomeHeroPage: View {
	let show: Show
	let width: CGFloat
	let height: CGFloat
	/// The status bar and Dynamic Island's height; the artwork starts below it.
	let topInset: CGFloat
	/// Space under the button — more when page dots sit there.
	let textBottom: CGFloat
	/// The "Mark all episodes watched" setting, applied when Mark Watched
	/// finishes the show.
	let cascadeWatched: Bool
	/// The iPad's sideways layout.
	let wide: Bool
	/// Receives the band colour once the artwork is in.
	let onBand: (UIColor) -> Void
	/// Mark Watched with an episode to go: the rating sheet takes it from here.
	let onRateEpisode: (Episode) -> Void
	/// The › beside Mark Watched: the episode the show is up to.
	let onOpenEpisode: (Episode) -> Void
	let onOpen: () -> Void

	@State private var art: UIImage?
	/// The episode panel's height as laid out, so a phone's art runs down to it.
	@State private var panelHeight: CGFloat = 170
	/// The episode playing from YouTube where the artwork was, after ▶.
	@State private var playingVideo = false
	@AppStorage(ExperimentalFeatures.youTubeEpisodes) private var youTubeEpisodes = false

	/// Artwork already loaded this session, by page and size, so a page that's
	/// created fresh — like the real page the loop swaps in at either end —
	/// shows its art straight away instead of flashing the bare band.
	private static var loadedArt: [String: UIImage] = [:]

	init(show: Show, width: CGFloat, height: CGFloat, topInset: CGFloat, textBottom: CGFloat,
	     cascadeWatched: Bool, wide: Bool = false, onBand: @escaping (UIColor) -> Void,
	     onRateEpisode: @escaping (Episode) -> Void, onOpenEpisode: @escaping (Episode) -> Void,
	     onOpen: @escaping () -> Void) {
		self.show = show
		self.width = width
		self.height = height
		self.topInset = topInset
		self.textBottom = textBottom
		self.cascadeWatched = cascadeWatched
		self.wide = wide
		self.onBand = onBand
		self.onRateEpisode = onRateEpisode
		self.onOpenEpisode = onOpenEpisode
		self.onOpen = onOpen
		_art = State(initialValue: Self.loadedArt[loadKey])
	}

	// Proportions from the design: a 28pt gap under the status bar, the art's
	// lower edge 23pt above the band's, fading over its top quarter and its
	// bottom 40%.
	private var artTop: CGFloat { max(topInset, 20) + 28 }
	/// On a phone the episode panel sits under the art rather than over it, so
	/// the art ends above the room kept for the panel.
	private var artHeight: CGFloat {
		wide ? max(height - artTop - 23, 200)
		     : max(height - artTop - panelHeight - textBottom - 6, 200)
	}

	/// The height kept under a phone's art for the episode panel: Home adds it
	/// to the hero, so the art keeps its size and the page grows instead.
	static let panelRoom: CGFloat = 200
	/// Sideways, the art keeps a backdrop's 16:9 where the page is wide enough,
	/// leaving the leading third or more to the words.
	private var artWidth: CGFloat { wide ? min(width * 0.7, artHeight * 16 / 9) : width }

	/// Leading margin of the sideways layout's words.
	static let wideInset: CGFloat = 44

	/// Re-runs the artwork load once the page knows its size.
	private var loadKey: String { "\(show.id)-\(Int(artWidth))-\(Int(artHeight))" }

	var body: some View {
		let next = HomeFeed.nextEpisode(of: show)
		let progress = HomeFeed.progressLine(for: show, next: next)
		ZStack(alignment: .top) {
			// The artwork opens the show; the panel over it has its own buttons.
			Button(action: onOpen) {
				artwork
					.padding(.top, artTop)
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
					.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Open \(show.title)")

			if playingVideo, let next, let videoID = playable(next) {
				player(next, videoID: videoID)
			}

			if wide {
				wideDetails(progress: progress, next: next)
					.padding(.leading, Self.wideInset)
					.padding(.bottom, textBottom + 6)
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
			} else {
				details(progress: progress, next: next)
					.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { panelHeight = $0 }
					.padding(.bottom, textBottom)
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
			}
		}
		.frame(height: height)
		.clipped()
		.task(id: loadKey) { await loadArt() }
		// Marked watched or swiped away, the video stops.
		.onChange(of: next?.id) { playingVideo = false }
		.onDisappear { playingVideo = false }
	}

	/// The episode's YouTube video, when it has one and YouTube episodes are on.
	private func playable(_ episode: Episode?) -> String? {
		guard youTubeEpisodes else { return nil }
		return episode?.youtubeVideoID
	}

	/// ▶ beside Mark Watched, for an episode that plays from YouTube.
	private func playButton(_ next: Episode) -> some View {
		Button {
			Haptics.selection()
			withAnimation(Glass.smooth) { playingVideo.toggle() }
		} label: {
			Image(systemName: playingVideo ? "stop.fill" : "play.fill")
				.font(.system(.callout, weight: .semibold))
				.foregroundStyle(.white)
				.frame(width: GlassControl.height, height: GlassControl.height)
				.contentShape(Circle())
		}
		.buttonStyle(.plain)
		.glassEffect(.regular.tint(.red.opacity(0.55)).interactive(), in: Circle())
		.accessibilityLabel(playingVideo ? "Stop" : "Play \(HomeFeed.episodeLine(next)) here")
	}

	/// The episode playing where the artwork was, with ✕ to stop it; on a
	/// sideways iPad, on the artwork's side.
	private func player(_ next: Episode, videoID: String) -> some View {
		EpisodeYouTubeCard(videoID: videoID, thumbnailURL: next.stillURL, title: next.displayTitle,
		                   playlistID: next.season?.youtubePlaylistID, autoplay: true)
			.overlay(alignment: .topTrailing) {
				Button {
					withAnimation(Glass.smooth) { playingVideo = false }
				} label: {
					Image(systemName: "xmark")
						.font(.system(.footnote, weight: .bold))
						.foregroundStyle(.white)
						.frame(width: 32, height: 32)
						.contentShape(Circle())
				}
				.buttonStyle(.plain)
				.glassEffect(.regular.interactive(), in: Circle())
				.padding(8)
				.accessibilityLabel("Stop playing")
			}
			.frame(maxWidth: wide ? min(artWidth, 620) : .infinity)
			.padding(.horizontal, 16)
			// Clear of "Home", its count and the profile button over the top of
			// the page on a phone; on an iPad they're in the bar.
			.padding(.top, wide ? artTop : artTop + 72)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: wide ? .topTrailing : .top)
			.transition(.opacity.combined(with: .scale(scale: 0.97)))
	}

	private var artwork: some View {
		Color.clear
			.frame(width: artWidth, height: artHeight)
			.overlay {
				if let art {
					Image(uiImage: art)
						.resizable()
						.scaledToFill()
						.transition(.opacity)
				}
			}
			.clipped()
			// Sideways, the words aren't on it, so it keeps more of its lower half.
			.mask {
				LinearGradient(stops: [
					.init(color: .clear, location: 0),
					.init(color: .black, location: wide ? 0.2 : 0.24),
					// The panel is under it now, so on a phone only its very foot fades.
					.init(color: .black, location: wide ? 0.72 : 0.9),
					.init(color: .clear, location: 1),
				], startPoint: .top, endPoint: .bottom)
			}
			// And comes in out of the band on its leading edge.
			.mask {
				LinearGradient(stops: [
					.init(color: wide ? .clear : .black, location: 0),
					.init(color: .black, location: wide ? 0.42 : 0),
				], startPoint: .leading, endPoint: .trailing)
			}
			.frame(maxWidth: .infinity, alignment: .trailing)
			.allowsHitTesting(false)
	}

	/// The season the show is in, an episode a segment: watched ones in their
	/// rating's colour — white when unrated — and ones to go faint; then how
	/// far through the season is.
	private func seasonStrip(_ season: Season) -> some View {
		let episodes = season.sortedEpisodes
		let watched = episodes.filter { $0.status == .watched }.count
		return HStack(spacing: 8) {
			HStack(spacing: episodes.count > 40 ? 1 : 2) {
				ForEach(episodes) { episode in
					Capsule()
						.fill(episode.status != .watched ? .white.opacity(0.22)
						      : episode.episodeTier.map(Glass.tint) ?? .white)
				}
			}
			.frame(height: 5)
			Text("\(season.seasonNumber == 0 ? "Specials" : "S\(season.seasonNumber)") · \(watched) of \(episodes.count)")
				.font(.system(.caption, weight: .medium).monospacedDigit())
				.foregroundStyle(.white.opacity(0.78))
				.fixedSize()
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("\(season.displayName): \(watched) of \(episodes.count) episodes watched")
	}

	/// The episode watched last and how it was rated, in the rating's colour;
	/// a tap opens it, to change the rating.
	private func lastLine(_ episode: Episode) -> some View {
		Button { onOpenEpisode(episode) } label: {
			HStack(spacing: 6) {
				Text("Last: \(ShowFacts.code(episode))")
					.foregroundStyle(.white.opacity(0.78))
				if let tier = episode.episodeTier {
					Label(tier.rawValue, systemImage: tier.systemImage)
						.foregroundStyle(Glass.tint(tier))
				} else {
					Text("Not rated")
						.foregroundStyle(.white.opacity(0.6))
				}
				Image(systemName: "chevron.right")
					.font(.system(.caption2, weight: .bold))
					.foregroundStyle(.white.opacity(0.5))
			}
			.font(.system(.caption, weight: .semibold))
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel("Last watched \(HomeFeed.episodeLine(episode)), \(episode.episodeTier?.rawValue ?? "not rated")")
		.accessibilityHint("Opens the episode")
	}

	/// The episode panel, after design A of the alternatives: Liquid Glass under
	/// the art — the episode and its length, the show and the
	/// episode's name, how far through the show is, then Mark Watched and a way
	/// into the show. Caught up, it says when the next one airs instead.
	private func details(progress: String, next: Episode?) -> some View {
		let watched = show.watchedEpisodeCount
		let total = show.episodeCount
		let runtime = next.flatMap { $0.runtimeMinutes ?? $0.specs?.runtimeMinutes }
		return VStack(alignment: .leading, spacing: 10) {
			Text([next.map(ShowFacts.code), runtime.map { "\($0) min" }].compactMap { $0 }.joined(separator: " · ")
			     .ifEmpty(progress))
				.font(.system(.caption, weight: .semibold))
				.foregroundStyle(.white.opacity(0.78))
			VStack(alignment: .leading, spacing: 2) {
				Text(show.title)
					.font(.system(.title2, weight: .bold))
					.foregroundStyle(.white)
					.lineLimit(2)
					.minimumScaleFactor(0.8)
				// An episode whose only name is its own code ("S2E2") would just
				// repeat the line above, so it is left out.
				if let name = next.map(ShowFacts.distinctName) ?? progress {
					Text(name)
						.font(.system(.subheadline, weight: .regular))
						.foregroundStyle(.white.opacity(0.88))
						.lineLimit(1)
				}
			}
			if let season = HomeFeed.currentSeason(of: show, next: next) {
				seasonStrip(season)
			} else if total > 0 {
				HStack(spacing: 8) {
					Capsule()
						.fill(.white.opacity(0.22))
						.frame(height: 5)
						.overlay(alignment: .leading) {
							GeometryReader { bar in
								Capsule().fill(.white)
									.frame(width: bar.size.width * ShowFacts.fraction(watched: watched, total: total))
							}
						}
					Text("\(watched) of \(total)")
						.font(.system(.caption, weight: .medium).monospacedDigit())
						.foregroundStyle(.white.opacity(0.78))
				}
				.accessibilityElement(children: .ignore)
				.accessibilityLabel("\(watched) of \(total) episodes watched")
			}
			if let last = HomeFeed.lastWatched(in: show) {
				lastLine(last)
			}
			HStack(spacing: 8) {
				if let next, playable(next) != nil { playButton(next) }
				// Caught up, there's nothing out to mark until the next one airs.
				if !caughtUp(next: next) {
					Button(action: markWatched) {
						Label("Mark Watched", systemImage: "checkmark")
							.font(.system(.callout, weight: .semibold))
							.foregroundStyle(.black)
							.frame(maxWidth: .infinity, minHeight: GlassControl.height)
							.background(.white, in: Capsule())
							.contentShape(Capsule())
					}
					.buttonStyle(.pressable)
					.accessibilityLabel(next == nil ? "Mark \(show.title) watched" : "Mark \(progress) watched")
				} else {
					Spacer(minLength: 0)
				}
				Button {
					if let next { onOpenEpisode(next) } else { onOpen() }
				} label: {
					Image(systemName: "chevron.right")
						.font(.system(.callout, weight: .semibold))
						.foregroundStyle(.white)
						.frame(width: GlassControl.height, height: GlassControl.height)
						.contentShape(Circle())
				}
				.buttonStyle(.plain)
				.glassEffect(.regular.interactive(), in: Circle())
				.accessibilityLabel(next.map { "Open \(HomeFeed.episodeLine($0))" } ?? "Open \(show.title)")
			}
		}
		.padding(16)
		.frame(maxWidth: .infinity, alignment: .leading)
		.glassEffect(.regular.tint(.black.opacity(0.28)), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
		.padding(.horizontal, 14)
	}

	/// The sideways layout's words, left-aligned: where the show is up to, its
	/// name, the episode's name and synopsis, then Mark Watched beside the
	/// season's rating-coloured strip, and the episode watched last.
	private func wideDetails(progress: String, next: Episode?) -> some View {
		let watched = show.watchedEpisodeCount
		let total = show.episodeCount
		let synopsis = [next?.synopsis ?? "", show.overview].first { !$0.isEmpty }
		return VStack(alignment: .leading, spacing: 4) {
			Text(progress.uppercased())
				.font(.system(.footnote, weight: .bold))
				.kerning(1)
				.foregroundStyle(.white.opacity(0.8))
			Text(show.title)
				.font(.system(.largeTitle, weight: .bold))
				.foregroundStyle(.white)
				.lineLimit(2)
				.minimumScaleFactor(0.7)
			if let next {
				Text(next.displayTitle)
					.font(.system(.body, weight: .semibold))
					.foregroundStyle(.white.opacity(0.92))
					.lineLimit(1)
			}
			if let synopsis {
				Text(synopsis)
					.font(.subheadline)
					.foregroundStyle(.white.opacity(0.78))
					.lineLimit(3)
					.padding(.top, 6)
			}
			HStack(spacing: 18) {
				if let next, playable(next) != nil { playButton(next) }
				if !caughtUp(next: next) {
					Button(action: markWatched) {
						Text("Mark Watched")
							.font(.system(.callout, weight: .medium))
							.foregroundStyle(.white)
							.lineLimit(1)
							.fixedSize()
							.padding(.horizontal, 6)
					}
					.buttonStyle(.glass)
					.controlSize(.large)
					.accessibilityLabel(next == nil ? "Mark \(show.title) watched" : "Mark \(progress) watched")
				}
				if let season = HomeFeed.currentSeason(of: show, next: next) {
					// The phone's rating-coloured strip, at a width that suits it here.
					seasonStrip(season)
						.frame(maxWidth: 220)
				} else if total > 0 {
					VStack(alignment: .leading, spacing: 6) {
						Text(ShowFacts.progressLine(watched: watched, total: total))
							.font(.system(.footnote, weight: .medium))
							.foregroundStyle(.white.opacity(0.8))
						Capsule()
							.fill(.white.opacity(0.22))
							.frame(width: 150, height: 4)
							.overlay(alignment: .leading) {
								Capsule()
									.fill(.white)
									.frame(width: 150 * ShowFacts.fraction(watched: watched, total: total))
							}
					}
					.accessibilityElement(children: .combine)
				}
			}
			.padding(.top, 16)
			if let last = HomeFeed.lastWatched(in: show) {
				lastLine(last)
					.padding(.top, 10)
			}
		}
		.shadow(color: .black.opacity(0.25), radius: 6, y: 1)
		.frame(width: max(min(width * 0.42, 460), 300), alignment: .leading)
	}

	private func loadArt() async {
		guard width > 0 else { return }
		var gallery: ImageGallery?
		if let tmdbID = show.tmdbID {
			// Shared with the Images tab's session cache, so this is one request a show.
			gallery = await CreditsLoader.seriesImages(tvID: tmdbID)
		}
		let urlString = HomeFeed.heroArtURL(for: show, gallery: gallery,
		                                    chosenByHand: ArtworkChoice.chosen(.landscape, for: show.id))
		guard !urlString.isEmpty, let url = URL(string: urlString),
		      let image = await ImageCache.shared.image(for: url),
		      !Task.isCancelled else { return }
		let sampled = await ArtworkBand.sampledColor(for: image, in: CGSize(width: artWidth, height: artHeight))
		guard !Task.isCancelled else { return }
		Self.loadedArt[loadKey] = image
		withAnimation(.easeOut(duration: 0.35)) {
			art = image
			if let sampled { onBand(sampled) }
		}
	}

	/// Every episode that's out is Watched, with more still to air.
	private func caughtUp(next: Episode?) -> Bool {
		next == nil && HomeFeed.nextToAir(of: show) != nil
	}

	/// With an episode to go, opens the rating sheet — rating it is what marks
	/// it Watched. With none left, finishes the show straight away.
	private func markWatched() {
		if let next = HomeFeed.nextEpisode(of: show) {
			onRateEpisode(next)
			return
		}
		/*withAnimation(Glass.smooth) {
			HomeFeed.markNextWatched(in: show, cascade: cascadeWatched)
		}*/
		Haptics.success()
	}
}

// MARK: - Shared backdrop

/// What the hero pages share with the backdrop behind them: how far the hero has
/// been swiped, and each show's band colour. Kept in an observable object so a
/// swipe, which changes `offset` every frame, only redraws the backdrop that
/// reads it — not the whole Home screen.
@Observable
final class HeroScroll {
	var offset: CGFloat = 0
	var bands: [UUID: UIColor] = [:]
}

/// The band colour behind the Home hero. It fills the hero — up under the status
/// bar, and past the top when the page is pulled down — then fades into the
/// page below so the hero has no edge. Mid-swipe it's a mix of the two shows'
/// colours in view, so the colour turns over with the page.
struct HeroBackdrop: View {
	let scroll: HeroScroll
	/// The show on each hero page as laid out, loop copies included, so the
	/// blend runs on round the ends too.
	let pages: [Show]
	let heroHeight: CGFloat
	let pageWidth: CGFloat
	/// The status bar's height, for the light-mode shade behind it.
	let topInset: CGFloat

	@Environment(\.colorScheme) private var colorScheme

	private var band: UIColor {
		guard !pages.isEmpty else { return ArtworkBand.fallback }
		let position = min(max(scroll.offset / max(pageWidth, 1), 0), CGFloat(pages.count - 1))
		let index = Int(position.rounded(.down))
		let next = min(index + 1, pages.count - 1)
		return ArtworkBand.mix(scroll.bands[pages[index].id] ?? ArtworkBand.fallback,
		                       scroll.bands[pages[next].id] ?? ArtworkBand.fallback,
		                       position - CGFloat(index))
	}

	var body: some View {
		let band = band
		let color = Color(uiColor: band)
		ZStack(alignment: .top) {
			color
				.frame(height: 400)
				.offset(y: -400)
			VStack(spacing: 0) {
				color
					.frame(height: heroHeight)
				LinearGradient(colors: [color, color.opacity(0)], startPoint: .top, endPoint: .bottom)
					.frame(height: 220)
			}
			if colorScheme == .light && ArtworkBand.hidesDarkStatusBarText(band) {
				LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
					.frame(height: max(topInset, 20) + 14)
			}
		}
		.allowsHitTesting(false)
	}
}

// MARK: - Recently watched card

/// A poster on the Recently watched row. The card runs from a colour taken off
/// the top of its poster down to its rating's colour — a neutral slate when
/// unrated — and the poster fades into both, like the hero. There's no title:
/// the poster carries its own, so the fades stay short enough to keep it
/// readable, and the rating pill gets its own strip underneath. A title with no
/// poster to show falls back to printing its name. Home's To Watch row uses the
/// same card as the poster alone: no rating strip, no fades.
struct RecentlyWatchedCard: View {
	let item: WatchedTitle
	/// The rating strip under the poster; off, the card is just the poster.
	var showsRating = true

	@State private var poster: UIImage?
	@State private var tone: UIColor?
	@State private var posterMissing = false

	private static let width: CGFloat = 132
	private static let posterHeight: CGFloat = 198
	private static let height: CGFloat = 234
	private static let unratedColor = Color(.unratedTone)

	/// Sampled poster colours by URL, so a card scrolled back into view doesn't
	/// flash through the placeholder tone again.
	private static var tones: [String: UIColor] = [:]

	private var topColor: Color { Color(uiColor: tone ?? UIColor(resource: .heroToneFallback)) }
	private var bottomColor: Color { item.rating.map { Glass.tint($0) } ?? Self.unratedColor }

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
		ZStack(alignment: .top) {
			LinearGradient(stops: [
				.init(color: topColor, location: 0),
				.init(color: topColor, location: 0.12),
				.init(color: showsRating ? bottomColor : topColor, location: 0.8),
				.init(color: showsRating ? bottomColor : topColor, location: 1),
			], startPoint: .top, endPoint: .bottom)

			artwork

			if showsRating {
				ratingPill
					.padding(.bottom, 9)
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
			}
		}
		.frame(width: Self.width, height: showsRating ? Self.height : Self.posterHeight)
		.clipShape(shape)
		.overlay(shape.strokeBorder(.white.opacity(0.12), lineWidth: 1))
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(item.title)
		.accessibilityValue(showsRating ? (item.rating?.rawValue ?? "Unrated") : item.kindLabel)
		.task(id: item.posterURL) { await load() }
	}

	/// The poster, fading in from the top colour and out into the rating colour —
	/// briefly at both ends, so a title printed near either edge stays legible.
	private var artwork: some View {
		Color.clear
			.frame(width: Self.width, height: Self.posterHeight)
			.overlay {
				if let poster {
					Image(uiImage: poster)
						.resizable()
						.scaledToFill()
						.transition(.opacity)
				} else if posterMissing {
					VStack(spacing: 8) {
						Image(systemName: item.placeholder)
							.font(.system(.title, weight: .light))
						Text(item.title)
							.font(.system(.subheadline, weight: .semibold))
							.multilineTextAlignment(.center)
							.lineLimit(3)
					}
					.foregroundStyle(.white.opacity(0.85))
					.padding(.horizontal, 10)
				}
			}
			.clipped()
			.mask {
				// The poster alone runs edge to edge.
				LinearGradient(stops: [
					.init(color: showsRating ? .clear : .black, location: 0),
					.init(color: .black, location: 0.1),
					.init(color: .black, location: 0.86),
					.init(color: showsRating ? .clear : .black, location: 1),
				], startPoint: .top, endPoint: .bottom)
			}
			.allowsHitTesting(false)
	}

	/// White on glass: a tinted pill would vanish into its own colour below it.
	@ViewBuilder private var ratingPill: some View {
		if let rating = item.rating {
			HStack(spacing: 4) {
				Image(systemName: rating.systemImage)
					.font(.system(.caption2, weight: .bold))
				Text(rating.rawValue)
					.font(.system(.caption, weight: .semibold))
			}
			.foregroundStyle(.white)
			.padding(.horizontal, 10)
			.padding(.vertical, 5)
			.background(Capsule().fill(.white.opacity(0.2)))
			.overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
		} else {
			Text("Unrated")
				.font(.system(.caption, weight: .semibold))
				.foregroundStyle(.white.opacity(0.85))
				.padding(.horizontal, 10)
				.padding(.vertical, 5)
				.overlay(Capsule().strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
		}
	}

	private func load() async {
		let key = item.posterURL
		guard !key.isEmpty, let url = URL(string: key) else {
			posterMissing = true
			return
		}
		if let cached = Self.tones[key] { tone = cached }
		let loaded = await ImageCache.shared.image(for: url)
		if Task.isCancelled { return }
		guard let image = loaded else {
			posterMissing = true
			return
		}
		// Sampled as-is: nothing white is written over the top of the card, so
		// a bright poster keeps a bright top instead of fading into grey.
		var sampled = Self.tones[key]
		if sampled == nil {
			sampled = await ArtworkBand.sampledColor(for: image, in: CGSize(width: Self.width, height: Self.posterHeight),
			                                         dimmedForWhiteText: false)
			if Task.isCancelled { return }
		}
		if let sampled { Self.tones[key] = sampled }
		withAnimation(.easeOut(duration: 0.3)) {
			poster = image
			if let sampled { tone = sampled }
		}
	}
}

private extension String {
	func ifEmpty(_ other: String) -> String { isEmpty ? other : self }
}
