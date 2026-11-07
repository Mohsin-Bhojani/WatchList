//
//  ImageFiles.swift
//  WatchListCore
//
//  Artwork kept on disk, the same way on the iPhone and the watch: one file
//  per image URL in a folder under Caches, named by a SHA-256 of the URL, so a
//  poster downloads once and still shows without a connection. Reading a file
//  re-dates it, and trimming drops the files used longest ago — Caches can be
//  emptied by the system at any time, so anything dropped just downloads again.
//
//  Only bytes live here. Decoding is each device's own: the iPhone decodes at
//  full size (ImageCache), the watch shrinks as it decodes and takes a colour
//  from the picture (Artwork).
//

import CryptoKit
import Foundation

public nonisolated struct ImageFiles: Sendable {
	public let directory: URL

	public init(directory: URL) {
		self.directory = directory
	}

	/// A folder of its own under Caches.
	public static func named(_ folder: String) -> ImageFiles {
		ImageFiles(directory: URL.cachesDirectory.appendingPathComponent(folder, isDirectory: true))
	}

	public func file(for url: URL) -> URL {
		let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
		return directory.appendingPathComponent(digest.map { String(format: "%02x", $0) }.joined())
	}

	/// The bytes kept for `url`, re-dated as just used; nil when there are none.
	public func cached(_ url: URL) -> Data? {
		let file = file(for: url)
		guard let data = try? Data(contentsOf: file) else { return nil }
		try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
		return data
	}

	/// Downloads `url` and keeps it; nil when it didn't come back whole.
	public func download(_ url: URL) async -> Data? {
		guard let (data, response) = try? await URLSession.shared.data(from: url),
		      (response as? HTTPURLResponse)?.statusCode ?? 200 == 200, !data.isEmpty else { return nil }
		try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		try? data.write(to: file(for: url), options: .atomic)
		return data
	}

	/// Keeps the folder under `limit` bytes, dropping the files used longest ago.
	public func trim(to limit: Int) {
		let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .contentModificationDateKey]
		guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)
		else { return }
		let entries = files.compactMap { file -> (file: URL, size: Int, used: Date)? in
			guard let values = try? file.resourceValues(forKeys: Set(keys)) else { return nil }
			return (file, values.totalFileAllocatedSize ?? 0, values.contentModificationDate ?? .distantPast)
		}
		var total = entries.reduce(0) { $0 + $1.size }
		for entry in entries.sorted(by: { $0.used < $1.used }) where total > limit {
			try? FileManager.default.removeItem(at: entry.file)
			total -= entry.size
		}
	}
}
