//
//  Artwork.swift
//  WatchList Watch App
//
//  Posters and backdrops for the watch, straight from TMDb: fetched at a size
//  for the watch's screen, shrunk as they're decoded, and kept twice — in
//  memory for this launch, and in Caches so artwork already seen still shows
//  with no iPhone or Wi-Fi about. Each comes with its colour, taken from the
//  image and dimmed so white text reads on it.
//

import CryptoKit
import ImageIO
import OSLog
import SwiftUI
import UIKit

@MainActor
enum Artwork {
	struct Loaded {
		let image: UIImage
		/// The image's colour, dim enough for white text.
		let tone: Color
	}

	/// TMDb's poster at a size the watch draws crisply.
	static func poster(_ url: String) -> String { resized(url, to: "w342") }
	/// TMDb's backdrop at a size the watch draws crisply.
	static func backdrop(_ url: String) -> String { resized(url, to: "w780") }

	private static var memory: [String: Loaded] = [:]
	private static var inFlight: [String: Task<Loaded?, Never>] = [:]
	private static let log = Logger(subsystem: "com.mohsin.WatchList.watchkitapp", category: "Artwork")

	/// Already loaded this launch.
	static func cached(_ url: String) -> Loaded? { memory[url] }

	/// From memory, then disk, then TMDb — whichever has it first.
	static func load(_ url: String) async -> Loaded? {
		guard !url.isEmpty else { return nil }
		if let hit = memory[url] { return hit }
		if let running = inFlight[url] { return await running.value }
		let task = Task<Loaded?, Never> {
			defer { inFlight[url] = nil }
			guard let decoded = await Task.detached(priority: .utility, operation: { await fetch(url) }).value else {
				return nil
			}
			let loaded = Loaded(image: UIImage(cgImage: decoded.image),
			                    tone: Color(red: decoded.red, green: decoded.green, blue: decoded.blue))
			memory[url] = loaded
			return loaded
		}
		inFlight[url] = task
		return await task.value
	}

	/// Loads these ahead — while the iPhone or Wi-Fi is still about.
	static func prefetch(_ urls: [String]) {
		for url in urls where !url.isEmpty && memory[url] == nil {
			Task { _ = await load(url) }
		}
	}

	/// A steady colour for a title without artwork, picked from its name.
	static func placeholderTone(for title: String) -> Color {
		let tones: [(Double, Double, Double)] = [(0.20, 0.27, 0.35), (0.18, 0.33, 0.32), (0.35, 0.25, 0.18),
		                                         (0.29, 0.27, 0.19), (0.37, 0.29, 0.50), (0.25, 0.45, 0.52)]
		let sum = title.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
		let tone = tones[sum % tones.count]
		return Color(red: tone.0, green: tone.1, blue: tone.2)
	}

	// MARK: Off the main actor

	private struct Decoded: @unchecked Sendable {
		let image: CGImage
		let red: Double, green: Double, blue: Double
	}

	/// ".../t/p/w500/abc.jpg" at another of TMDb's sizes. Anything else as it was.
	nonisolated private static func resized(_ url: String, to size: String) -> String {
		guard let marker = url.range(of: "/t/p/"),
		      let end = url[marker.upperBound...].firstIndex(of: "/") else { return url }
		return url.replacingCharacters(in: marker.upperBound..<end, with: size)
	}

	nonisolated private static func fetch(_ url: String) async -> Decoded? {
		let file = cacheFile(for: url)
		if let data = try? Data(contentsOf: file), let decoded = decode(data) { return decoded }
		guard let address = URL(string: url),
		      let (data, response) = try? await URLSession.shared.data(from: address),
		      (response as? HTTPURLResponse)?.statusCode == 200,
		      let decoded = decode(data) else { return nil }
		do {
			try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
			try data.write(to: file, options: .atomic)
		} catch {
			Logger(subsystem: "com.mohsin.WatchList.watchkitapp", category: "Artwork")
				.error("Couldn't keep artwork: \(error.localizedDescription, privacy: .public)")
		}
		return decoded
	}

	nonisolated private static func cacheFile(for url: String) -> URL {
		let name = SHA256.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
		return URL.cachesDirectory.appending(path: "Artwork").appending(path: name)
	}

	/// Decoded no bigger than the watch needs, with its dimmed average colour.
	nonisolated private static func decode(_ data: Data) -> Decoded? {
		guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
		let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
		                                kCGImageSourceCreateThumbnailWithTransform: true,
		                                kCGImageSourceThumbnailMaxPixelSize: 520]
		guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }

		var pixel = [UInt8](repeating: 0, count: 4)
		let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
			guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
			                              bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
			                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
			context.interpolationQuality = .medium
			context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
			return true
		}
		var red = 0.2, green = 0.27, blue = 0.35
		if drawn {
			red = Double(pixel[0]) / 255
			green = Double(pixel[1]) / 255
			blue = Double(pixel[2]) / 255
			// Darkened until white text on it has a contrast of about 7:1.
			func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
			let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
			if luminance > 0.1 {
				let scale = pow(0.1 / luminance, 1 / 2.2)
				red *= scale; green *= scale; blue *= scale
			}
		}
		return Decoded(image: image, red: red, green: green, blue: blue)
	}
}

/// Artwork filling its frame, or `placeholder` until it's in.
struct ArtworkImage<Placeholder: View>: View {
	let url: String
	var onTone: (Color) -> Void = { _ in }
	@ViewBuilder let placeholder: Placeholder

	@State private var loaded: Artwork.Loaded?

	var body: some View {
		Color.clear
			.overlay {
				if let image = (loaded ?? Artwork.cached(url))?.image {
					Image(uiImage: image)
						.resizable()
						.scaledToFill()
						.transition(.opacity)
				} else {
					placeholder
				}
			}
			.clipped()
			.task(id: url) {
				if let hit = Artwork.cached(url) {
					loaded = hit
					onTone(hit.tone)
					return
				}
				guard let fresh = await Artwork.load(url) else { return }
				withAnimation(.easeOut(duration: 0.25)) { loaded = fresh }
				onTone(fresh.tone)
			}
	}
}
