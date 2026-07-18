//
//  DesignSystem.swift
//  WatchList
//
//  "Editorial Paper" design language: a calm, warm off-white paper canvas,
//  refined serif headlines, hairline-bordered cards, generous whitespace and a
//  single warm-red accent. Sophisticated magazine / print feel, adapts to
//  light & dark. The public API (Glass, .glass(), GlassBackground, Haptics,
//  etc.) is intentionally unchanged so every screen restyles automatically.
//

import SwiftUI
import UIKit

// MARK: - Palette

enum Glass {
	// Accent + supporting tones — user-selectable (see AppTheme / Settings).
	static var accent: Color  { AppTheme.shared.palette.accent }
	static var accent2: Color { AppTheme.shared.palette.accent2 }
	static var accent3: Color { AppTheme.shared.palette.accent3 }

	// Status tints, kept muted and editorial.
	static let toWatch     = Color(hex: "#A9762F")   // ochre
	static let watching    = Color(hex: "#B23A2F")   // red
	static let watched     = Color(hex: "#4F6B4E")   // muted green

	// Paper surfaces (adapt to light / dark).
	static let paper    = Color(light: "#F3ECDD", dark: "#141109")
	static let surface  = Color(light: "#FBF7EE", dark: "#211C14")
	static let hairline = Color(light: "#241F1A", dark: "#F0E9DB")
	static let ink      = Color(light: "#26211C", dark: "#F2ECE0")

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

	/// Serif headline font helper.
	static func serif(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
		.system(size: size, weight: weight, design: .serif)
	}

	// Retained for source compatibility (no longer drawn as drifting blobs).
	static let ambient: [Color] = [paper, surface, paper, surface]
}

// MARK: - Color helpers

extension Color {
	init(hex: String) {
		let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
		var int: UInt64 = 0
		Scanner(string: hex).scanHexInt64(&int)
		let r = Double((int >> 16) & 0xFF) / 255
		let g = Double((int >> 8) & 0xFF) / 255
		let b = Double(int & 0xFF) / 255
		self.init(red: r, green: g, blue: b)
	}

	/// A color that resolves differently in light vs dark mode.
	init(light: String, dark: String) {
		self.init(UIColor { trait in
			trait.userInterfaceStyle == .dark
				? UIColor(Color(hex: dark))
				: UIColor(Color(hex: light))
		})
	}
}

// MARK: - Paper background

/// A calm, flat warm-paper canvas with a whisper of warmth at the top. This is
/// the editorial counterpart to the old ambient gradient.
struct GlassBackground: View {
	var tints: [Color] = Glass.ambient
	var body: some View {
		ZStack {
			Glass.paper.ignoresSafeArea()
			LinearGradient(colors: [Glass.accent.opacity(0.05), .clear],
			               startPoint: .top, endPoint: .center)
				.ignoresSafeArea()
		}
	}
}

// MARK: - Card surface

/// The workhorse surface used by every card, chip and control: a clean paper
/// panel with a fine hairline border and a soft, restrained shadow.
struct GlassSurface: ViewModifier {
	var cornerRadius: CGFloat = Glass.corner
	var material: Material = .ultraThinMaterial   // kept for API compatibility
	var strokeOpacity: Double = 0.16
	var shadow: Double = 0.05

	func body(content: Content) -> some View {
		let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
		return content
			.background(Glass.surface, in: shape)
			.overlay(shape.strokeBorder(Glass.hairline.opacity(strokeOpacity), lineWidth: 1))
			.shadow(color: .black.opacity(shadow), radius: 10, x: 0, y: 6)
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

struct StatusBadge: View {
	let status: WatchStatus
	var compact: Bool = false
	var body: some View {
		HStack(spacing: 5) {
			Image(systemName: status.systemImage)
				.font(.system(size: compact ? 10 : 12, weight: .bold))
			if !compact {
				Text(status.rawValue)
					.font(.system(size: 12, weight: .semibold))
			}
		}
		.foregroundStyle(Glass.tint(status))
		.padding(.horizontal, compact ? 8 : 11)
		.padding(.vertical, compact ? 5 : 6)
		.background(Glass.tint(status).opacity(0.14), in: Capsule())
		.overlay(Capsule().strokeBorder(Glass.tint(status).opacity(0.4), lineWidth: 1))
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
