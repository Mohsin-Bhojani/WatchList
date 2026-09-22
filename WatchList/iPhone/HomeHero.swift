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

/// One page of the Home hero, after the "1a Home" design. The artwork sits
/// clear of the status bar and Dynamic Island and fades at top and bottom into
/// the band colour behind it — drawn by `HeroBackdrop`, not the page, so it can
/// run on into the rest of Home and change as the hero is swiped. The page
/// samples that colour from its artwork (see `ArtworkBand`) and hands it up.
/// The episode the show is up to, its title and Mark Watched sit on the lower
/// fade; tapping anywhere else on the page opens the show.
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
	let onOpen: () -> Void

	@State private var art: UIImage?

	/// Artwork already loaded this session, by page and size, so a page that's
	/// created fresh — like the real page the loop swaps in at either end —
	/// shows its art straight away instead of flashing the bare band.
	private static var loadedArt: [String: UIImage] = [:]

	init(show: Show, width: CGFloat, height: CGFloat, topInset: CGFloat, textBottom: CGFloat,
	     cascadeWatched: Bool, wide: Bool = false, onBand: @escaping (UIColor) -> Void,
	     onRateEpisode: @escaping (Episode) -> Void, onOpen: @escaping () -> Void) {
		self.show = show
		self.width = width
		self.height = height
		self.topInset = topInset
		self.textBottom = textBottom
		self.cascadeWatched = cascadeWatched
		self.wide = wide
		self.onBand = onBand
		self.onRateEpisode = onRateEpisode
		self.onOpen = onOpen
		_art = State(initialValue: Self.loadedArt[loadKey])
	}

	// Proportions from the design: a 28pt gap under the status bar, the art's
	// lower edge 23pt above the band's, fading over its top quarter and its
	// bottom 40%.
	private var artTop: CGFloat { max(topInset, 20) + 28 }
	private var artHeight: CGFloat { max(height - artTop - 23, 200) }
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
			artwork
				.padding(.top, artTop)

			if wide {
				wideDetails(progress: progress, next: next)
					.padding(.leading, Self.wideInset)
					.padding(.bottom, textBottom + 6)
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
			} else {
				details(progress: progress, next: next)
					.padding(.bottom, textBottom)
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
			}
		}
		.frame(height: height)
		.clipped()
		.contentShape(Rectangle())
		.onTapGesture(perform: onOpen)
		.accessibilityAction(named: "Open \(show.title)", onOpen)
		.task(id: loadKey) { await loadArt() }
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
					.init(color: .black, location: wide ? 0.72 : 0.6),
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

	private func details(progress: String, next: Episode?) -> some View {
		VStack(spacing: 2) {
			Text(progress)
				.font(.system(size: 15, weight: .medium))
				.foregroundStyle(.white.opacity(0.92))
				.shadow(color: .black.opacity(0.25), radius: 4, y: 1)
			Text(show.title)
				.font(.system(size: 22, weight: .bold))
				.foregroundStyle(.white)
				.multilineTextAlignment(.center)
				.lineLimit(2)
				.minimumScaleFactor(0.8)
				.shadow(color: .black.opacity(0.25), radius: 6, y: 1)
			Button(action: markWatched) {
				Text("Mark Watched")
					.font(.system(size: 16, weight: .medium))
					.foregroundStyle(.white)
					.padding(.horizontal, 6)
			}
			.buttonStyle(.glass)
			.controlSize(.large)
			.padding(.top, 10)
			.accessibilityLabel(next == nil ? "Mark \(show.title) watched" : "Mark \(progress) watched")
		}
		.padding(.horizontal, 24)
	}

	/// The sideways layout's words, left-aligned: where the show is up to, its
	/// name, the episode's name and synopsis, then Mark Watched beside how far
	/// through the show is.
	private func wideDetails(progress: String, next: Episode?) -> some View {
		let watched = show.watchedEpisodeCount
		let total = show.episodeCount
		let synopsis = [next?.synopsis ?? "", show.overview].first { !$0.isEmpty }
		return VStack(alignment: .leading, spacing: 4) {
			Text(progress.uppercased())
				.font(.system(size: 13, weight: .bold))
				.kerning(1)
				.foregroundStyle(.white.opacity(0.8))
			Text(show.title)
				.font(.system(size: 40, weight: .bold))
				.foregroundStyle(.white)
				.lineLimit(2)
				.minimumScaleFactor(0.7)
			if let next {
				Text(next.displayTitle)
					.font(.system(size: 18, weight: .semibold))
					.foregroundStyle(.white.opacity(0.92))
					.lineLimit(1)
			}
			if let synopsis {
				Text(synopsis)
					.font(.system(size: 15))
					.foregroundStyle(.white.opacity(0.78))
					.lineLimit(3)
					.padding(.top, 6)
			}
			HStack(spacing: 18) {
				Button(action: markWatched) {
					Text("Mark Watched")
						.font(.system(size: 16, weight: .medium))
						.foregroundStyle(.white)
						.padding(.horizontal, 6)
				}
				.buttonStyle(.glass)
				.controlSize(.large)
				.accessibilityLabel(next == nil ? "Mark \(show.title) watched" : "Mark \(progress) watched")
				if total > 0 {
					VStack(alignment: .leading, spacing: 6) {
						Text(ShowFacts.progressLine(watched: watched, total: total))
							.font(.system(size: 13, weight: .medium))
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

	/// With an episode to go, opens the rating sheet — rating it is what marks
	/// it Watched. With none left, finishes the show straight away.
	private func markWatched() {
		if let next = HomeFeed.nextEpisode(of: show) {
			Haptics.tap()
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
							.font(.system(size: 26, weight: .light))
						Text(item.title)
							.font(.system(size: 14, weight: .semibold))
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
					.font(.system(size: 10, weight: .bold))
				Text(rating.rawValue)
					.font(.system(size: 12, weight: .semibold))
			}
			.foregroundStyle(.white)
			.padding(.horizontal, 10)
			.padding(.vertical, 5)
			.background(Capsule().fill(.white.opacity(0.2)))
			.overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
		} else {
			Text("Unrated")
				.font(.system(size: 12, weight: .semibold))
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
