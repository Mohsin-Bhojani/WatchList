//
//  WidgetSync.swift
//  WatchList
//
//  The iPhone app's end of the Up Next widget (WidgetShared/WidgetLink.swift):
//    - writes the widget's snapshot shortly after each save, and as the app
//      leaves the front, with a small picture of each show
//    - applies the widget's Mark Watched taps when the app opens, the way the
//      watch's are applied — marked watched with no rating, starting the
//      season and show — then rewrites the snapshot from the library
//

import Foundation
import SwiftData
import UIKit
import WidgetKit

@MainActor
final class WidgetSync {
	static let shared = WidgetSync()

	/// Episodes listed for each show, so the widget can move on by itself.
	nonisolated static let upcomingCount = 4
	/// Pictures are drawn at most this wide on the largest widget.
	private static let artWidth: CGFloat = 600

	private var context: ModelContext?
	private var saveObserver: NSObjectProtocol?
	private var debounce: Task<Void, Never>?

	func attach(_ context: ModelContext) {
		guard self.context == nil else { return }
		self.context = context
		saveObserver = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil,
		                                                      queue: .main) { _ in
			Task { @MainActor in WidgetSync.shared.scheduleWrite() }
		}
		applyMarks()
		scheduleWrite()
	}

	// MARK: The widget's marks

	/// Applies what the widget marked since the app was last open.
	func applyMarks() {
		guard let context, let store = WidgetStore.shared else { return }
		let marks = store.outbox()
		guard !marks.isEmpty else { return }
		for mark in marks {
			WatchActionApplier.apply(WatchAction(id: mark.id, madeAt: mark.madeAt,
			                                     change: .markWatched(episode: mark.episodeID, tier: nil)),
			                         in: context)
		}
		try? context.save()
		store.removeFromOutbox(Set(marks.map(\.id)))
		scheduleWrite()
	}

	// MARK: Writing

	func scheduleWrite() {
		guard context != nil else { return }
		debounce?.cancel()
		debounce = Task {
			try? await Task.sleep(for: .milliseconds(800))
			guard !Task.isCancelled else { return }
			await write()
		}
	}

	func write() async {
		guard let context, let store = WidgetStore.shared else { return }
		let shows = (try? context.fetch(FetchDescriptor<Show>(sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]))) ?? []
		var snapshot = Self.snapshot(of: shows)
		let art = await writeArt(for: HomeFeed.watching(shows), in: store)
		for index in snapshot.shows.indices { snapshot.shows[index].artFile = art[snapshot.shows[index].id] }
		store.write(snapshot)
		WidgetCenter.shared.reloadTimelines(ofKind: WidgetLink.kind)
	}

	/// The shows set to Watching, each with its next episodes out and how far
	/// through it is — or, caught up, when the next one airs.
	static func snapshot(of shows: [Show], upcoming limit: Int = upcomingCount, asOf now: Date = .now) -> WidgetSnapshot {
		let rows = HomeFeed.watching(shows).map { show -> WidgetShow in
			let order = HomeFeed.runningOrder(of: show)
			let pairs = zip(order, HomeFeed.aired(order, asOf: now)).filter { $0.0.status != .watched }
			let out = pairs.filter(\.1).map(\.0)
			let waiting = pairs.first { !$0.1 }?.0
			return WidgetShow(id: show.id, title: show.title, artFile: nil,
			                  upcoming: out.prefix(limit).map {
			                  	WidgetEpisode(id: $0.id, code: UpNextEpisode.code(season: $0.seasonNumber, episode: $0.episodeNumber),
			                  	              title: $0.displayTitle)
			                  },
			                  watched: show.watchedEpisodeCount, total: show.episodeCount,
			                  caughtUpLine: out.isEmpty ? waiting.map { AirDate.caughtUpLine(nextAirDate: $0.airDate, short: true, now: now) } : nil)
		}
		return WidgetSnapshot(shows: rows, writtenAt: now)
	}

	/// A small JPEG of each show's backdrop (or poster), in the shared folder,
	/// by show id. Pictures of shows no longer listed are removed.
	private func writeArt(for shows: [Show], in store: WidgetStore) async -> [UUID: String] {
		let folder = store.artDirectory
		try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		var written: [UUID: String] = [:]
		for show in shows {
			let source = show.backdropURL.isEmpty ? show.posterURL : show.backdropURL
			guard let url = URL(string: source), let image = await ImageCache.shared.image(for: url),
			      let jpeg = Self.scaled(image, toWidth: Self.artWidth).jpegData(compressionQuality: 0.75) else { continue }
			let name = "\(show.id.uuidString).jpg"
			try? jpeg.write(to: folder.appendingPathComponent(name), options: .atomic)
			written[show.id] = name
		}
		let keep = Set(written.values)
		for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
		where !keep.contains(file.lastPathComponent) {
			try? FileManager.default.removeItem(at: file)
		}
		return written
	}

	private static func scaled(_ image: UIImage, toWidth width: CGFloat) -> UIImage {
		guard image.size.width > width else { return image }
		let size = CGSize(width: width, height: (image.size.height * width / image.size.width).rounded())
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
	}
}
