//
//  ImageCache.swift
//  WatchList
//
//  On-device image caching so posters/backdrops download only once. Images are
//  kept decoded in a fast in-memory NSCache and persisted to disk (Caches
//  directory), keyed by a stable SHA-256 of the URL. After the first fetch a
//  poster loads instantly and works offline — no repeated TMDb requests.
//
//  Reading, downloading and decoding all happen off the main thread, several at
//  once, so drawing a poster never waits on decoding it. The disk cache is kept
//  under a size cap; anything trimmed downloads again when it's next needed.
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

	/// Decoded images by URL, costed by their bytes. NSCache is thread-safe, so
	/// views read it straight away for art that's already in.
	nonisolated(unsafe) private let memory = NSCache<NSString, UIImage>()
	// Coalesce concurrent requests for the same URL into one load.
	private var inFlight: [String: Task<UIImage?, Never>] = [:]

	init() {
		try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
		memory.countLimit = 400
		memory.totalCostLimit = 150 * 1024 * 1024
	}

	private nonisolated static var directory: URL {
		FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("PosterCache", isDirectory: true)
	}

	private nonisolated static func fileName(for url: URL) -> String {
		let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
		return digest.map { String(format: "%02x", $0) }.joined()
	}

	/// The image for `url` if it's already decoded in memory.
	nonisolated func cached(_ url: URL) -> UIImage? {
		memory.object(forKey: url.absoluteString as NSString)
	}

	func image(for url: URL) async -> UIImage? {
		let key = url.absoluteString
		if let cached = memory.object(forKey: key as NSString) { return cached }
		if let existing = inFlight[key] { return await existing.value }

		// Detached, so loads run side by side instead of queueing on this actor.
		let task = Task.detached(priority: .userInitiated) { await Self.load(url) }
		inFlight[key] = task
		let image = await task.value
		inFlight[key] = nil
		if let image {
			memory.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
		}
		return image
	}

	/// From the disk cache, a local file (a manually-picked poster) or the
	/// network, decoded ready to draw.
	private nonisolated static func load(_ url: URL) async -> UIImage? {
		let cacheFile = directory.appendingPathComponent(fileName(for: url))
		if let data = try? Data(contentsOf: cacheFile), let image = decoded(data) { return image }
		if url.isFileURL {
			return (try? Data(contentsOf: url)).flatMap(decoded)
		}
		guard let download = try? await URLSession.shared.data(from: url),
		      let image = decoded(download.0) else { return nil }
		try? download.0.write(to: cacheFile, options: .atomic)
		return image
	}

	/// Decodes now, rather than lazily on the main thread the first time the
	/// image is drawn.
	private nonisolated static func decoded(_ data: Data) -> UIImage? {
		guard let image = UIImage(data: data) else { return nil }
		return image.preparingForDisplay() ?? image
	}

	private nonisolated static func cost(of image: UIImage) -> Int {
		guard let cgImage = image.cgImage else { return 1 }
		return cgImage.bytesPerRow * cgImage.height
	}

	/// Keeps the disk cache under `limit` bytes, dropping the files written
	/// longest ago first.
	nonisolated static func trimDisk(to limit: Int = 200 * 1024 * 1024) {
		let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .contentModificationDateKey]
		guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
		else { return }
		let entries = files.compactMap { file -> (file: URL, size: Int, written: Date)? in
			guard let values = try? file.resourceValues(forKeys: Set(keys)) else { return nil }
			return (file, values.totalFileAllocatedSize ?? 0, values.contentModificationDate ?? .distantPast)
		}
		var total = entries.reduce(0) { $0 + $1.size }
		for entry in entries.sorted(by: { $0.written < $1.written }) where total > limit {
			try? FileManager.default.removeItem(at: entry.file)
			total -= entry.size
		}
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

	@State private var phase: AsyncImagePhase
	/// The URL `phase` holds an image for, so a view whose URL changes in
	/// place — artwork chosen from the gallery — loads the new one.
	@State private var loaded: URL?

	init(url: URL?, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
		self.url = url
		self.content = content
		// Art already in memory shows at once, without a placeholder frame first.
		let cached = url.flatMap { ImageCache.shared.cached($0) }
		_phase = State(initialValue: cached.map { AsyncImagePhase.success(Image(uiImage: $0)) } ?? .empty)
		_loaded = State(initialValue: cached == nil ? nil : url)
	}

	var body: some View {
		content(phase)
			.task(id: url) { await load() }
	}

	private func load() async {
		guard let url else {
			phase = .empty
			loaded = nil
			return
		}
		// Keep an already-resolved image when the view re-renders — but not when
		// it's of another URL than the one being asked for now.
		if case .success = phase, loaded == url { return }
		if let image = await ImageCache.shared.image(for: url) {
			phase = .success(Image(uiImage: image))
			loaded = url
		} else {
			phase = .failure(URLError(.cannotDecodeContentData))
			loaded = nil
		}
	}
}
