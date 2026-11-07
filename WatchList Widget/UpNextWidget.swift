//
//  UpNextWidget.swift
//  WatchList Widget
//
//  Up Next on the Home Screen and Lock Screen: the shows you're Watching and
//  the episode each is up to, from the snapshot the app writes
//  (WidgetShared/WidgetLink.swift). On the Home Screen, Mark Watched marks the
//  episode from the widget itself; the app applies it next time it's open.
//
//    small   the first show, its episode and Mark Watched
//    medium  the same, wider, with how far through it is
//    large   up to four shows, each with its own Mark Watched
//    Lock Screen  the first show's episode (rectangular, inline) or how far
//                 through it is (circular); tapping opens the app
//

import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Mark Watched

struct MarkEpisodeWatchedIntent: AppIntent {
	static let title: LocalizedStringResource = "Mark Episode Watched"
	static let description = IntentDescription("Marks the next episode of a show watched in WatchList.")
	/// Only ever run from the widget's button, never offered in Shortcuts.
	static let isDiscoverable = false

	@Parameter(title: "Episode") var episodeID: String

	init() {}
	init(episodeID: UUID) { self.episodeID = episodeID.uuidString }

	func perform() async throws -> some IntentResult {
		if let id = UUID(uuidString: episodeID) { WidgetStore.shared?.mark(episode: id) }
		return .result()
	}
}

// MARK: - Timeline

struct UpNextEntry: TimelineEntry {
	let date: Date
	let snapshot: WidgetSnapshot
}

struct UpNextProvider: TimelineProvider {
	func placeholder(in context: Context) -> UpNextEntry {
		UpNextEntry(date: .now, snapshot: .preview)
	}

	func getSnapshot(in context: Context, completion: @escaping (UpNextEntry) -> Void) {
		let saved = WidgetStore.shared?.snapshot() ?? .empty
		completion(UpNextEntry(date: .now, snapshot: context.isPreview && saved.shows.isEmpty ? .preview : saved))
	}

	/// The app reloads the widget whenever the library changes; past that,
	/// once a day, so a caught-up line's "tomorrow" moves on.
	func getTimeline(in context: Context, completion: @escaping (Timeline<UpNextEntry>) -> Void) {
		let entry = UpNextEntry(date: .now, snapshot: WidgetStore.shared?.snapshot() ?? .empty)
		let tomorrow = Calendar.current.startOfDay(for: .now.addingTimeInterval(24 * 60 * 60))
		completion(Timeline(entries: [entry], policy: .after(tomorrow)))
	}
}

// MARK: - The widget

struct UpNextWidget: Widget {
	var body: some WidgetConfiguration {
		StaticConfiguration(kind: WidgetLink.kind, provider: UpNextProvider()) { entry in
			UpNextWidgetView(entry: entry)
		}
		.configurationDisplayName("Up Next")
		.description("The episode each show you're watching is up to, with Mark Watched.")
		.supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
		                    .accessoryRectangular, .accessoryInline, .accessoryCircular])
		.contentMarginsDisabled()
	}
}

struct UpNextWidgetView: View {
	let entry: UpNextEntry
	@Environment(\.widgetFamily) private var family

	private var shows: [WidgetShow] { entry.snapshot.shows }

	var body: some View {
		switch family {
		case .accessoryInline: inline
		case .accessoryCircular: circular
		case .accessoryRectangular: rectangular
		case .systemLarge: large
		default: single
		}
	}

	// MARK: Home Screen

	@ViewBuilder private var single: some View {
		if let show = shows.first {
			ZStack(alignment: .bottomLeading) {
				ShowDetails(show: show, wide: family == .systemMedium)
					.padding(14)
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
			.containerBackground(for: .widget) { ShowArt(show: show) }
		} else {
			EmptyUpNext().containerBackground(.fill.tertiary, for: .widget)
		}
	}

	@ViewBuilder private var large: some View {
		if shows.isEmpty {
			EmptyUpNext().containerBackground(.fill.tertiary, for: .widget)
		} else {
			VStack(alignment: .leading, spacing: 10) {
				Text("Up Next")
					.font(.system(size: 13, weight: .bold))
					.foregroundStyle(.secondary)
				ForEach(shows.prefix(4)) { show in
					ShowRow(show: show)
					if show.id != shows.prefix(4).last?.id { Divider() }
				}
				Spacer(minLength: 0)
			}
			.padding(16)
			.containerBackground(.fill.tertiary, for: .widget)
		}
	}

	// MARK: Lock Screen

	@ViewBuilder private var inline: some View {
		if let show = shows.first {
			Text("\(show.title) · \(show.next?.code ?? show.caughtUpLine ?? "All watched")")
		} else {
			Text("Nothing on Up Next")
		}
	}

	@ViewBuilder private var circular: some View {
		if let show = shows.first {
			Gauge(value: show.fraction) {
				Image(systemName: "tv")
			} currentValueLabel: {
				Text("\(Int((show.fraction * 100).rounded()))")
			}
			.gaugeStyle(.accessoryCircularCapacity)
			.containerBackground(.clear, for: .widget)
		} else {
			Image(systemName: "tv").containerBackground(.clear, for: .widget)
		}
	}

	@ViewBuilder private var rectangular: some View {
		VStack(alignment: .leading, spacing: 1) {
			if let show = shows.first {
				Text(show.title).font(.headline).lineLimit(1)
				Text(show.next.map { "\($0.code) · \($0.title)" } ?? show.caughtUpLine ?? "All watched")
					.lineLimit(2)
			} else {
				Text("Up Next").font(.headline)
				Text("Shows you're watching appear here.").lineLimit(2)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.containerBackground(.clear, for: .widget)
	}
}

// MARK: - Pieces

/// The show's picture, darkened toward the bottom so the words read on it.
private struct ShowArt: View {
	let show: WidgetShow

	var body: some View {
		ZStack {
			Color.black
			if let file = show.artFile, let folder = WidgetStore.shared?.artDirectory,
			   let image = UIImage(contentsOfFile: folder.appendingPathComponent(file).path) {
				Image(uiImage: image).resizable().scaledToFill()
			}
			LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
		}
	}
}

private struct ShowDetails: View {
	let show: WidgetShow
	let wide: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: 3) {
			Text(show.next?.code ?? show.caughtUpLine ?? "All watched")
				.font(.system(size: 12, weight: .semibold))
				.foregroundStyle(.white.opacity(0.85))
				.lineLimit(1)
			Text(show.title)
				.font(.system(size: wide ? 18 : 15, weight: .bold))
				.foregroundStyle(.white)
				.lineLimit(2)
			if wide, let next = show.next {
				Text(next.title)
					.font(.system(size: 13, weight: .medium))
					.foregroundStyle(.white.opacity(0.85))
					.lineLimit(1)
			}
			HStack(spacing: 10) {
				if let next = show.next {
					MarkButton(episode: next, compact: !wide)
				}
				if wide { Progress(show: show).frame(maxWidth: 120) }
			}
			.padding(.top, 4)
		}
	}
}

private struct ShowRow: View {
	let show: WidgetShow

	var body: some View {
		HStack(spacing: 10) {
			ShowArt(show: show)
				.frame(width: 64, height: 40)
				.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
			VStack(alignment: .leading, spacing: 2) {
				Text(show.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
				Text(show.next.map { "\($0.code) · \($0.title)" } ?? show.caughtUpLine ?? "All watched")
					.font(.system(size: 12))
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			Spacer(minLength: 0)
			if let next = show.next { MarkButton(episode: next, compact: true) }
		}
	}
}

private struct MarkButton: View {
	let episode: WidgetEpisode
	let compact: Bool

	var body: some View {
		Button(intent: MarkEpisodeWatchedIntent(episodeID: episode.id)) {
			if compact {
				Image(systemName: "checkmark")
					.font(.system(size: 13, weight: .bold))
			} else {
				Label("Mark Watched", systemImage: "checkmark")
					.font(.system(size: 12, weight: .semibold))
			}
		}
		.buttonStyle(.bordered)
		.buttonBorderShape(.capsule)
		.tint(.white)
		.accessibilityLabel("Mark \(episode.code) watched")
	}
}

private struct Progress: View {
	let show: WidgetShow

	var body: some View {
		VStack(alignment: .leading, spacing: 3) {
			Text("\(show.watched) of \(show.total)")
				.font(.system(size: 11, weight: .medium))
				.foregroundStyle(.white.opacity(0.8))
			ProgressView(value: show.fraction).tint(.white)
		}
	}
}

private struct EmptyUpNext: View {
	var body: some View {
		VStack(spacing: 6) {
			Image(systemName: "tv").font(.title2).foregroundStyle(.secondary)
			Text("Shows you're watching appear here.")
				.font(.system(size: 13, weight: .medium))
				.multilineTextAlignment(.center)
				.foregroundStyle(.secondary)
		}
		.padding()
	}
}

// MARK: - Preview data

extension WidgetSnapshot {
	static let preview = WidgetSnapshot(shows: [
		WidgetShow(id: UUID(), title: "The Long Road", artFile: nil,
		           upcoming: [WidgetEpisode(id: UUID(), code: "S2 · E5", title: "Low Water")],
		           watched: 12, total: 18, caughtUpLine: nil),
		WidgetShow(id: UUID(), title: "Harbour Lights", artFile: nil, upcoming: [],
		           watched: 8, total: 10, caughtUpLine: "Caught up · Next Friday"),
	], writtenAt: .now)
}

@main
struct WatchListWidgetBundle: WidgetBundle {
	var body: some Widget {
		UpNextWidget()
	}
}
