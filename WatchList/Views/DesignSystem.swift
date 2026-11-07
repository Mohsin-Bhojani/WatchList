//
//  DesignSystem.swift
//  WatchList
//
//  Liquid Glass, as the title pages already are: the page is a colour blur lit
//  by your accent palette over a cool neutral ground, and every card, chip and
//  control is translucent glass floating over it — never an opaque panel.
//  Follows the iPhone's light and dark. Serif headlines stay. The public API
//  (Glass, .glass(), GlassBackground, Haptics, etc.) is unchanged, so every
//  screen picks the look up from here.
//  Every colour is a colour set in Assets.xcassets, under Colors — light and
//  dark variants included — and is referred to here by its generated name.
//

import SwiftUI
import UIKit
import WatchListCore
import WatchListLibrary

// MARK: - Palette

enum Glass {
	// Accent + supporting tones — user-selectable (see AppTheme / Settings).
	static var accent: Color  { AppTheme.shared.palette.accent }
	static var accent2: Color { AppTheme.shared.palette.accent2 }
	static var accent3: Color { AppTheme.shared.palette.accent3 }

	// Status tints, light and dark (Colors/Status).
	static let toWatch     = Color(.statusToWatch)    // ochre
	static let watching    = Color(.statusWatching)   // red
	static let watched     = Color(.statusWatched)    // muted green

	// Rating tints (best -> worst), light and dark (Colors/Verdicts).
	static let ratingPerfection = Color(.ratingPerfection)   // teal-green
	static let ratingGoForIt    = Color(.ratingGoForIt)      // olive
	static let ratingTimepass   = Color(.ratingTimepass)     // amber
	static let ratingSkip       = Color(.ratingSkip)         // brick red

	// Episode rewatch-tier tints (worst -> best) (Colors/Episode Tiers).
	static let tierSkip    = Color(.tierSkip)      // muted taupe
	static let tierWatch   = Color(.tierWatch)     // green
	static let tierRewatch = Color(.tierRewatch)   // gold

	// The ground under the blur, the glass's tint, edges and text, light and dark
	// (Colors/Paper — the name is older than the look).
	static let paper    = Color(.paper)
	static let surface  = Color(.surface)
	static let hairline = Color(.hairline)
	static let ink      = Color(.ink)

	/// Text and symbols set on a solid meaning colour: near-black, which every
	/// status, verdict and tier colour carries at 7:1 or more in both themes.
	static let onTint = Color(red: 0.04, green: 0.05, blue: 0.07)

	// Default corner radii — editorial favours gentle, restrained rounding.
	static let corner: CGFloat = 14
	static let cornerSmall: CGFloat = 10

	// Springs.
	static let pop    = Animation.spring(response: 0.32, dampingFraction: 0.78)
	static let smooth = Animation.spring(response: 0.45, dampingFraction: 0.88)

	static func tint(_ status: WatchStatus) -> Color {
		switch status {
		case .toWatch:  return toWatch
		case .watching: return watching
		case .watched:  return watched
		}
	}

	static func tint(_ rating: Rating) -> Color {
		switch rating {
		case .perfection: return ratingPerfection
		case .goForIt:    return ratingGoForIt
		case .timepass:   return ratingTimepass
		case .skip:       return ratingSkip
		}
	}

	static func tint(_ tier: EpisodeTier) -> Color {
		switch tier {
		case .skip:    return tierSkip
		case .watch:   return tierWatch
		case .rewatch: return tierRewatch
		}
	}

	/// Serif headline font helper.
	static func serif(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
		.system(size: size, weight: weight, design: .serif)
	}

	// Retained for source compatibility (no longer drawn as drifting blobs).
	static let ambient: [Color] = [paper, surface, paper, surface]
}

// MARK: - Colour blur backdrop

/// What lights the backdrop: the artwork colour of the show you're most into
/// — the first one set to Watching, as Home samples it for its hero. Nil with
/// nothing Watching, when the accent palette lights the page instead.
@Observable
final class BackdropLight {
	static let shared = BackdropLight()
	var tone: UIColor?
}

/// The page behind everything that isn't a title page: a cool neutral ground
/// with colour blurred into it, after design A of the alternatives — lit by
/// the show you're watching, its colour high on the left and a deeper shade of
/// it on the right, with your accent kept low as a small warm light (and in the
/// controls). With nothing Watching, the palette's three colours light it: the
/// main one high on the left, the third on the right, the deep one low.
struct GlassBackground: View {
	/// Kept for source compatibility; the palette's colours are used instead.
	var tints: [Color] = Glass.ambient
	@Environment(\.colorScheme) private var scheme

	var body: some View {
		GeometryReader { geometry in
			let width = geometry.size.width
			let height = geometry.size.height
			ZStack {
				Glass.paper
				if let tone = BackdropLight.shared.tone {
					light(Color(uiColor: tone), strength: 1.4, size: width * 1.15,
					      at: CGPoint(x: width * 0.18, y: height * 0.04))
					light(Color(uiColor: ArtworkBand.deeper(tone)), strength: 1.5, size: width * 1.0,
					      at: CGPoint(x: width * 1.0, y: height * 0.45))
					light(Glass.accent, strength: 0.6, size: width * 1.1,
					      at: CGPoint(x: width * 0.2, y: height * 1.0))
				} else {
					light(Glass.accent, size: width * 1.15, at: CGPoint(x: width * 0.12, y: height * 0.06))
					light(Glass.accent3, size: width * 0.95, at: CGPoint(x: width * 0.98, y: height * 0.38))
					// The deep shade lights the foot by day; at night it would only muddy
					// the dark, so the main colour comes back there instead.
					light(scheme == .dark ? Glass.accent : Glass.accent2,
					      size: width * 1.25, at: CGPoint(x: width * 0.25, y: height * 0.95))
				}
			}
			.drawingGroup()
			.animation(.easeInOut(duration: 0.6), value: BackdropLight.shared.tone)
		}
		.ignoresSafeArea()
		.accessibilityHidden(true)
	}

	private func light(_ color: Color, strength: Double = 1, size: CGFloat, at point: CGPoint) -> some View {
		Circle()
			.fill(color.opacity(min((scheme == .dark ? 0.36 : 0.32) * strength, 0.6)))
			.frame(width: size, height: size)
			.position(point)
			.blur(radius: size * 0.32)
	}
}

// MARK: - Card surface

/// The workhorse surface used by every card, chip and control: Liquid Glass,
/// tinted a little toward the ground so text reads on it by day and night,
/// with a fine edge where the glass meets a pale page.
struct GlassSurface: ViewModifier {
	var cornerRadius: CGFloat = Glass.corner
	var material: Material = .ultraThinMaterial   // kept for API compatibility
	var strokeOpacity: Double = 0.16
	var shadow: Double = 0.05                      // kept for API compatibility

	func body(content: Content) -> some View {
		let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
		return content
			.glassEffect(.regular.tint(Glass.surface), in: shape)
			.overlay(shape.strokeBorder(Glass.hairline.opacity(strokeOpacity * 0.45), lineWidth: 0.5))
	}
}

extension View {
	func glass(cornerRadius: CGFloat = Glass.corner,
	           material: Material = .ultraThinMaterial,
	           strokeOpacity: Double = 0.16,
	           shadow: Double = 0.05) -> some View {
		modifier(GlassSurface(cornerRadius: cornerRadius, material: material,
		                      strokeOpacity: strokeOpacity, shadow: shadow))
	}
}

// MARK: - Haptics

enum Haptics {
	static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
		let g = UIImpactFeedbackGenerator(style: style)
		g.prepare(); g.impactOccurred()
	}
	static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
	static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
	static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

// MARK: - Button styles

/// A gentle press-scale that fits the calm editorial motion language.
struct PressableStyle: ButtonStyle {
	var scale: CGFloat = 0.97
	var haptic: Bool = true
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.scaleEffect(configuration.isPressed ? scale : 1)
			.animation(Glass.pop, value: configuration.isPressed)
			.onChange(of: configuration.isPressed) { _, pressed in
				if pressed && haptic { Haptics.tap(.soft) }
			}
	}
}

extension ButtonStyle where Self == PressableStyle {
	static var pressable: PressableStyle { PressableStyle() }
}

// MARK: - Status pill / dot

/// After design B of the alternatives: a glass pill with the status in ink —
/// legible in light and dark — and its colour carried by the icon alone.
struct StatusBadge: View {
	let status: WatchStatus
	var compact: Bool = false
	var body: some View {
		HStack(spacing: 5) {
			Image(systemName: status.systemImage)
				.font(.system(size: compact ? 10 : 12, weight: .bold))
				.foregroundStyle(Glass.tint(status))
			if !compact {
				Text(status.rawValue)
					.font(.system(size: 12, weight: .semibold))
					.foregroundStyle(Glass.ink)
			}
		}
		.padding(.horizontal, compact ? 8 : 11)
		.padding(.vertical, compact ? 5 : 6)
		.glassEffect(.regular, in: Capsule())
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(status.rawValue)
	}
}

/// The rating counterpart to `StatusBadge`, after design A: the verdict's own
/// colour, solid, with its symbol and name in near-black on it.
struct RatingBadge: View {
	let rating: Rating
	var compact: Bool = false
	var body: some View {
		HStack(spacing: 5) {
			Image(systemName: rating.systemImage)
				.font(.system(size: compact ? 10 : 12, weight: .bold))
			if !compact {
				Text(rating.rawValue)
					.font(.system(size: 12, weight: .bold))
			}
		}
		.foregroundStyle(Glass.onTint)
		.padding(.horizontal, compact ? 8 : 11)
		.padding(.vertical, compact ? 5 : 6)
		.background(Glass.tint(rating), in: Capsule())
		.accessibilityElement(children: .ignore)
		.accessibilityLabel(rating.rawValue)
	}
}

/// The episode rewatch-tier badge (Skip / Watch / Rewatch).
struct EpisodeTierBadge: View {
	let tier: EpisodeTier
	var compact: Bool = false
	var body: some View {
		HStack(spacing: 5) {
			Image(systemName: tier.systemImage)
				.font(.system(size: compact ? 10 : 12, weight: .bold))
			if !compact {
				Text(tier.rawValue)
					.font(.system(size: 12, weight: .semibold))
			}
		}
		.foregroundStyle(Glass.tint(tier))
		.padding(.horizontal, compact ? 8 : 11)
		.padding(.vertical, compact ? 5 : 6)
		.background(Glass.tint(tier).opacity(0.14), in: Capsule())
		.overlay(Capsule().strokeBorder(Glass.tint(tier).opacity(0.4), lineWidth: 1))
	}
}

// MARK: - Poster image

/// Loads a remote poster (TMDb) with a graceful placeholder.
struct PosterImage: View {
	let urlString: String
	var systemPlaceholder: String = "film"
	var body: some View {
		GeometryReader { geo in
			ZStack {
				Rectangle().fill(Glass.hairline.opacity(0.06))
				if let url = URL(string: urlString), !urlString.isEmpty {
					CachedAsyncImage(url: url) { phase in
						switch phase {
						case .success(let image):
							image.resizable().scaledToFill()
						case .failure:
							placeholder
						case .empty:
							ProgressView()
						@unknown default:
							placeholder
						}
					}
				} else {
					placeholder
				}
			}
			.frame(width: geo.size.width, height: geo.size.height)
			.clipped()
		}
	}

	private var placeholder: some View {
		Image(systemName: systemPlaceholder)
			.font(.system(size: 28, weight: .light))
			.foregroundStyle(Glass.accent3)
	}
}

// MARK: - Section header

struct SectionLabel: View {
	let text: String
	var systemImage: String? = nil
	var body: some View {
		HStack(spacing: 6) {
			if let s = systemImage { Image(systemName: s).font(.system(size: 11, weight: .bold)) }
			Text(text.uppercased())
				.font(.system(size: 12, weight: .semibold, design: .serif))
				.kerning(1.5)
		}
		.foregroundStyle(Glass.accent)
	}
}

// MARK: - Empty state

struct EmptyState: View {
	let icon: String
	let title: String
	let subtitle: String
	var body: some View {
		VStack(spacing: 12) {
			Image(systemName: icon)
				.font(.system(size: 38, weight: .light))
				.foregroundStyle(Glass.accent)
			Text(title)
				.font(Glass.serif(20, .bold))
				.foregroundStyle(Glass.ink)
			Text(subtitle)
				.font(.system(size: 14, weight: .regular))
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
		}
		.frame(maxWidth: .infinity)
		.padding(36)
		.glass(cornerRadius: Glass.corner)
		.padding(.horizontal, 20)
	}
}
