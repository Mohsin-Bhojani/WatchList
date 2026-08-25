//
//  ImageCache.swift
//  WatchList
//
//  On-device image caching so posters/backdrops download only once. Images are
//  kept in a fast in-memory NSCache and persisted to disk (Caches directory),
//  keyed by a stable SHA-256 of the URL. After the first fetch a poster loads
//  instantly and works offline — no repeated TMDb requests.
//
//  `CachedAsyncImage` is a drop-in replacement for SwiftUI's `AsyncImage`: it
//  uses the same `AsyncImagePhase` content closure, so existing call sites only
//  need the type name changed.
//

import SwiftUI
import UIKit
import CryptoKit

// MARK: - Cache

actor ImageCache {
	static let shared = ImageCache()

	private let memory = NSCache<NSString, UIImage>()
	private let directory: URL
	private let fileManager = FileManager.default
	// Coalesce concurrent requests for the same URL into one download.
	private var inFlight: [String: Task<UIImage?, Never>] = [:]

	init() {
		let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
		directory = caches.appendingPathComponent("PosterCache", isDirectory: true)
		try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
		memory.countLimit = 300
	}

	private func key(for url: URL) -> String {
		let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
		return digest.map { String(format: "%02x", $0) }.joined()
	}

	func image(for url: URL) async -> UIImage? {
		let k = key(for: url)

		// 1. In-memory.
		if let cached = memory.object(forKey: k as NSString) { return cached }

		// 2. On disk (cache).
		let fileURL = directory.appendingPathComponent(k)
		if let data = try? Data(contentsOf: fileURL), let image = UIImage(data: data) {
			memory.setObject(image, forKey: k as NSString)
			return image
		}

		// 3. Local file (e.g. a manually-picked poster) — read directly, no network.
		if url.isFileURL {
			guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
			memory.setObject(image, forKey: k as NSString)
			return image
		}

		// 4. Download (de-duplicated).
		if let existing = inFlight[k] { return await existing.value }
		let task = Task<UIImage?, Never> {
			defer { inFlight[k] = nil }
			do {
				let (data, _) = try await URLSession.shared.data(from: url)
				guard let image = UIImage(data: data) else { return nil }
				memory.setObject(image, forKey: k as NSString)
				try? data.write(to: fileURL, options: .atomic)
				return image
			} catch {
				return nil
			}
		}
		inFlight[k] = task
		return await task.value
	}
}

// MARK: - Manual poster storage
//
// Manually-added shows/films have no TMDb poster to fall back on. When the
// user picks one from Photos, we save it permanently (NOT the purgeable
// Caches directory ImageCache uses) and hand back a file:// URL that works
// as a normal posterURL everywhere else in the app.

enum ManualPosterStore {
	private static var directory: URL {
		let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
		let dir = docs.appendingPathComponent("ManualPosters", isDirectory: true)
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir
	}

	/// Saves picked image data permanently; returns a posterURL string, or nil on failure.
	static func save(_ data: Data) -> String? {
		guard let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.85) else { return nil }
		let fileURL = directory.appendingPathComponent("\(UUID().uuidString).jpg")
		do {
			try jpeg.write(to: fileURL, options: .atomic)
			return fileURL.absoluteString
		} catch {
			return nil
		}
	}
}

// MARK: - Drop-in cached AsyncImage

struct CachedAsyncImage<Content: View>: View {
	private let url: URL?
	private let content: (AsyncImagePhase) -> Content

	@State private var phase: AsyncImagePhase = .empty

	init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
		self.url = url
		self.content = content
	}

	var body: some View {
		content(phase)
			.task(id: url) { await load() }
	}

	private func load() async {
		guard let url else { phase = .empty; return }
		// Keep an already-resolved image when the view re-renders.
		if case .success = phase { return }
		if let image = await ImageCache.shared.image(for: url) {
			phase = .success(Image(uiImage: image))
		} else {
			phase = .failure(URLError(.cannotDecodeContentData))
		}
	}
}
