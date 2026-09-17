//
//  ArtworkBand.swift
//  WatchList
//
//  Colours taken from artwork for the iPhone redesign:
//    - Home's hero band: the colour its artwork fades into above and below. In
//      the "1a Home" design that's a blue lifted from the sample art's sky, so
//      it's taken the same way from each show's art — the average of the top
//      edge of what's on screen.
//    - A film page's theme: the average of the whole poster, made a little
//      more vivid.
//  Both are dimmed if needed so the white text on them stays readable.
//

import SwiftUI
import UIKit

/// Not tied to the main actor: views sample through `sampledColor` and
/// `sampledThemeColor`, which do the work off the main thread.
nonisolated enum ArtworkBand {
	/// The design's blue: shown until the artwork loads, or when a show has none.
	static let fallback = UIColor(resource: .artworkFallback)

	/// Past this relative luminance, white text drops below 3:1 contrast (the
	/// large-text minimum), so brighter samples are dimmed down to it.
	static let maxLuminance: CGFloat = 0.3

	/// The band colour for `image` drawn scaled-to-fill in `box`, or nil when
	/// the image can't be read. Dimmed for white text unless told otherwise —
	/// the Recently watched cards sample their poster tops as they are.
	static func color(for image: UIImage, in box: CGSize, dimmedForWhiteText dims: Bool = true) -> UIColor? {
		guard let cgImage = image.cgImage else { return nil }
		let pixels = CGSize(width: cgImage.width, height: cgImage.height)
		let strip = topStrip(of: visibleRect(imageSize: pixels, in: box))
		guard let average = averageColor(of: cgImage, in: strip) else { return nil }
		return dims ? dimmedForWhiteText(average) : average
	}

	/// `color(for:in:dimmedForWhiteText:)`, worked out off the main thread so a
	/// row of cards coming into view doesn't hold up the scroll.
	static func sampledColor(for image: UIImage, in box: CGSize, dimmedForWhiteText dims: Bool = true) async -> UIColor? {
		await Task.detached(priority: .userInitiated) { color(for: image, in: box, dimmedForWhiteText: dims) }.value
	}

	/// A film page's colour: the whole image's average, pushed more vivid so a
	/// poster's colour reads as a colour rather than a muddy grey — a genuinely
	/// grey poster stays grey — then dimmed for white text.
	static func themeColor(for image: UIImage) -> UIColor? {
		guard let cgImage = image.cgImage else { return nil }
		let whole = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
		guard let average = averageColor(of: cgImage, in: whole) else { return nil }
		return dimmedForWhiteText(saturated(average, by: 1.35))
	}

	/// `themeColor(for:)`, worked out off the main thread.
	static func sampledThemeColor(for image: UIImage) async -> UIColor? {
		await Task.detached(priority: .userInitiated) { themeColor(for: image) }.value
	}

	/// The part of an image that `scaledToFill` leaves on screen in `box`, in
	/// the image's own coordinates (origin top-left).
	static func visibleRect(imageSize: CGSize, in box: CGSize) -> CGRect {
		guard imageSize.width > 0, imageSize.height > 0, box.width > 0, box.height > 0 else {
			return CGRect(origin: .zero, size: imageSize)
		}
		let scale = max(box.width / imageSize.width, box.height / imageSize.height)
		let size = CGSize(width: box.width / scale, height: box.height / scale)
		return CGRect(x: (imageSize.width - size.width) / 2, y: (imageSize.height - size.height) / 2,
		              width: size.width, height: size.height)
	}

	/// The sliver along the top of what's visible — the colour the band carries on.
	static func topStrip(of visible: CGRect) -> CGRect {
		CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: max(visible.height * 0.08, 1))
	}

	/// WCAG relative luminance, 0 (black) to 1 (white).
	static func relativeLuminance(_ color: UIColor) -> CGFloat {
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		guard color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return 0 }
		func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
		return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
	}

	/// Darkens a colour just enough to bring it down to `maxLuminance`, keeping
	/// its hue. The design's blue is already under it and comes back unchanged.
	static func dimmedForWhiteText(_ color: UIColor) -> UIColor {
		let luminance = relativeLuminance(color)
		guard luminance > maxLuminance else { return color }
		var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		color.getRed(&r, green: &g, blue: &b, alpha: &a)
		let k = pow(maxLuminance / luminance, 1 / 2.2)
		return UIColor(red: r * k, green: g * k, blue: b * k, alpha: 1)
	}

	/// Scales a colour's saturation, up to full.
	static func saturated(_ color: UIColor, by factor: CGFloat) -> UIColor {
		var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		guard color.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return color }
		return UIColor(hue: h, saturation: min(s * factor, 1), brightness: b, alpha: 1)
	}

	/// The same colour, darker — the far end of a page's gradient.
	static func deeper(_ color: UIColor, by factor: CGFloat = 0.6) -> UIColor {
		var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
		guard color.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else { return color }
		return UIColor(hue: h, saturation: s, brightness: b * factor, alpha: 1)
	}

	/// A straight blend from `a` to `b` — the colour between two hero pages
	/// part-way through a swipe.
	static func mix(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
		var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
		var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
		a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
		b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
		let t = min(max(t, 0), 1)
		return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t, alpha: 1)
	}

	/// True when the band is too dark for light mode's black status-bar text
	/// (under 3:1 against it).
	static func hidesDarkStatusBarText(_ color: UIColor) -> Bool {
		relativeLuminance(color) < 0.1
	}

	/// The average colour of `rect` (image pixels, origin top-left): that part
	/// of the image scaled down onto a few pixels, which are then averaged — a
	/// fraction of what a Core Image pass costs for one colour.
	private static func averageColor(of cgImage: CGImage, in rect: CGRect) -> UIColor? {
		guard let part = cgImage.cropping(to: rect.integral), let space = CGColorSpace(name: CGColorSpace.sRGB) else {
			return nil
		}
		let side = 8
		var pixels = [UInt8](repeating: 0, count: side * side * 4)
		let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
			guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
			                              bytesPerRow: side * 4, space: space,
			                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
			context.interpolationQuality = .medium
			context.draw(part, in: CGRect(x: 0, y: 0, width: side, height: side))
			return true
		}
		guard drawn else { return nil }
		var red = 0, green = 0, blue = 0
		for index in stride(from: 0, to: pixels.count, by: 4) {
			red += Int(pixels[index])
			green += Int(pixels[index + 1])
			blue += Int(pixels[index + 2])
		}
		let scale = CGFloat(side * side * 255)
		return UIColor(red: CGFloat(red) / scale, green: CGFloat(green) / scale, blue: CGFloat(blue) / scale, alpha: 1)
	}
}
