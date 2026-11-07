//
//  UpNextWidget.swift
//  WatchList Widget
//
//  Up Next on the Home Screen and Lock Screen: the shows you're Watching and
//  the episode each is up to, from the snapshot the app writes
//  (WatchListCore/WidgetLink.swift). On the Home Screen, Mark Watched marks the
//  episode from the widget itself; the app applies it next time it's open.
//
//  Edit Widget sets three things:
//    Show     one show, or All — your Watching shows, which the arrows on the
//             widget page through
//    Art      the show's landscape picture or its poster
//    Layout   one show, or a shelf of posters (medium and large), each with
//             its own Mark Watched
//
//    small    one show
//    medium   one show, wider; or a shelf of four posters
//    large    a list of four shows; or a shelf of six posters
//    Lock Screen  the chosen show's episode (rectangular, inline) or how far
//                 through it is (circular); tapping opens the app
//

import AppIntents
import SwiftUI
import WidgetKit
import WatchListCore

// MARK: - Configuration

/// A show the widget can be set to: one of those on the snapshot.
struct ShowEntity: AppEntity {
	static let typeDisplayRepresentation: TypeDisplayRepresentation = "Show"
	static let defaultQuery = ShowEntityQuery()

	let id: String
	let title: String

	var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct ShowEntityQuery: EntityQuery {
	private var shows: [ShowEntity] {
		(WidgetStore.shared?.snapshot().shows ?? []).map { ShowEntity(id: $0.id.uuidString, title: $0.title) }
	}

	func entities(for identifiers: [String]) async throws -> [ShowEntity] {
		shows.filter { identifiers.contains($0.id) }
	}

	func suggestedEntities() async throws -> [ShowEntity] { shows }
}

enum WidgetArt: String, AppEnum {
	case landscape, poster

	static let typeDisplayRepresentation: TypeDisplayRepresentation = "Art"
	static let caseDisplayRepresentations: [WidgetArt: DisplayRepresentation] = [
		.landscape: "Landscape",
		.poster: "Poster",
	]
}

enum WidgetLayout: String, AppEnum {
	case single, shelf

	static let typeDisplayRepresentation: TypeDisplayRepresentation = "Layout"
	static let caseDisplayRepresentations: [WidgetLayout: DisplayRepresentation] = [
		.single: "One show",
		.shelf: "Poster shelf",
	]
}

struct UpNextConfiguration: WidgetConfigurationIntent {
	static let title: LocalizedStringResource = "Up Next"
	static let description = IntentDescription("Choose the show, its art and the layout.")

	/// Nil for all of them, paged with the arrows.
	@Parameter(title: "Show") var show: ShowEntity?
	@Parameter(title: "Art", default: .landscape) var art: WidgetArt
	@Parameter(title: "Layout", default: .single) var layout: WidgetLayout

	init() {}
}

// MARK: - Buttons

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

/// The widget's arrows: the next or previous of your Watching shows.
struct TurnUpNextPageIntent: AppIntent {
	static let title: LocalizedStringResource = "Show Another Show"
	static let isDiscoverable = false

	@Parameter(title: "Step") var step: Int

	init() {}
	init(step: Int) { self.step = step }

	func perform() async throws -> some IntentResult {
		if let store = WidgetStore.shared {
			store.turnPage(by: step, of: store.snapshot().shows.count)
		}
		return .result()
	}
}

// MARK: - Timeline

struct UpNextEntry: TimelineEntry {
	let date: Date
	let snapshot: WidgetSnapshot
	let configuration: UpNextConfiguration
	let page: Int

	/// The show this widget is on: the one it's set to, or the paged one.
	var show: WidgetShow? {
		WidgetStore.show(in: snapshot, chosen: configuration.show.flatMap { UUID(uuidString: $0.id) }, page: page)
	}

	/// Set to all shows, with more than one to page through.
	var pages: Bool { configuration.show == nil && snapshot.shows.count > 1 }

	/// The shelf's shows: the one it's on first, then the rest.
	var shelf: [WidgetShow] {
		guard let first = show else { return [] }
		return [first] + snapshot.shows.filter { $0.id != first.id }
	}
}

struct UpNextProvider: AppIntentTimelineProvider {
	func placeholder(in context: Context) -> UpNextEntry {
		UpNextEntry(date: .now, snapshot: .preview, configuration: UpNextConfiguration(), page: 0)
	}

	func snapshot(for configuration: UpNextConfiguration, in context: Context) async -> UpNextEntry {
		let saved = WidgetStore.shared?.snapshot() ?? .empty
		return UpNextEntry(date: .now, snapshot: context.isPreview && saved.shows.isEmpty ? .preview : saved,
		                   configuration: configuration, page: WidgetStore.shared?.page() ?? 0)
	}

	/// The app reloads the widget whenever the library changes; past that,
	/// once a day, so a caught-up line's "tomorrow" moves on.
	func timeline(for configuration: UpNextConfiguration, in context: Context) async -> Timeline<UpNextEntry> {
		let entry = UpNextEntry(date: .now, snapshot: WidgetStore.shared?.snapshot() ?? .empty,
		                        configuration: configuration, page: WidgetStore.shared?.page() ?? 0)
		let tomorrow = Calendar.current.startOfDay(for: .now.addingTimeInterval(24 * 60 * 60))
		return Timeline(entries: [entry], policy: .after(tomorrow))
	}
}

// MARK: - The widget

struct UpNextWidget: Widget {
	var body: some WidgetConfiguration {
		AppIntentConfiguration(kind: WidgetLink.kind, intent: UpNextConfiguration.self, provider: UpNextProvider()) { entry in
			UpNextWidgetView(entry: entry)
		}
		.configurationDisplayName("Up Next")
		.description("The episode a show you're watching is up to, with Mark Watched. Edit the widget to pick the show, poster art or a shelf of posters.")
		.supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
		                    .accessoryRectangular, .accessoryInline, .accessoryCircular])
		.contentMarginsDisabled()
	}
}

struct UpNextWidgetView: View {
	let entry: UpNextEntry
	@Environment(\.widgetFamily) private var family

	private var poster: Bool { entry.configuration.art == .poster }

	var body: some View {
		switch family {
		case .accessoryInline: inline
		case .accessoryCircular: circular
		case .accessoryRectangular: rectangular
		case .systemLarge:
			if entry.configuration.layout == .shelf { shelf(columns: 3, rows: 2) } else { list }
		case .systemMedium:
			if entry.configuration.layout == .shelf { shelf(columns: 4, rows: 1) } else { single }
		default:
			single
		}
	}

	// MARK: One show

	@ViewBuilder private var single: some View {
		if let show = entry.show {
			Group {
				if poster && family == .systemMedium {
					// The poster down the side, the words beside it.
					HStack(spacing: 12) {
						Art(show: show, poster: true)
							.aspectRatio(2 / 3, contentMode: .fit)
							.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
						ShowDetails(show: show, wide: true, onArt: false)
						Spacer(minLength: 0)
					}
					.padding(12)
					.containerBackground(for: .widget) { Backdrop(show: show) }
				} else {
					ShowDetails(show: show, wide: family == .systemMedium, onArt: true)
						.padding(14)
						.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
						.containerBackground(for: .widget) { Art(show: show, poster: poster, shaded: true) }
				}
			}
			.overlay(alignment: .topTrailing) {
				if entry.pages { PageArrows(shows: entry.snapshot.shows, current: show) }
			}
		} else {
			EmptyUpNext().containerBackground(.fill.tertiary, for: .widget)
		}
	}

	// MARK: Large list

	@ViewBuilder private var list: some View {
		if entry.snapshot.shows.isEmpty {
			EmptyUpNext().containerBackground(.fill.tertiary, for: .widget)
		} else {
			VStack(alignment: .leading, spacing: 10) {
				Text("Up Next")
					.font(.system(size: 13, weight: .bold))
					.foregroundStyle(.white.opacity(0.7))
				ForEach(Array(entry.shelf.prefix(4).enumerated()), id: \.element.id) { index, show in
					if index > 0 { Divider().overlay(.white.opacity(0.2)) }
					ShowRow(show: show, poster: poster)
				}
				Spacer(minLength: 0)
			}
			.padding(16)
			.containerBackground(for: .widget) { Backdrop(show: entry.show) }
		}
	}

	// MARK: Poster shelf

	@ViewBuilder private func shelf(columns: Int, rows: Int) -> some View {
		if entry.snapshot.shows.isEmpty {
			EmptyUpNext().containerBackground(.fill.tertiary, for: .widget)
		} else {
			let shows = Array(entry.shelf.prefix(columns * rows))
			Grid(horizontalSpacing: 8, verticalSpacing: 8) {
				ForEach(0..<rows, id: \.self) { row in
					GridRow {
						ForEach(0..<columns, id: \.self) { column in
							let index = row * columns + column
							if index < shows.count {
								ShelfPoster(show: shows[index], showsTitle: rows > 1)
							} else {
								Color.clear
							}
						}
					}
				}
			}
			.padding(12)
			.containerBackground(for: .widget) { Backdrop(show: entry.show) }
		}
	}

	// MARK: Lock Screen

	@ViewBuilder private var inline: some View {
		if let show = entry.show {
			Text("\(show.title) · \(show.next?.code ?? show.caughtUpLine ?? "All watched")")
		} else {
			Text("Nothing on Up Next")
		}
	}

	@ViewBuilder private var circular: some View {
		if let show = entry.show {
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
			if let show = entry.show {
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

/// A picture from the shared folder, by file name.
private func picture(_ file: String?) -> UIImage? {
	guard let file, let folder = WidgetStore.shared?.artDirectory else { return nil }
	return UIImage(contentsOfFile: folder.appendingPathComponent(file).path)
}

/// The show's landscape picture or its poster, filling its frame — darkened
/// toward the bottom when words sit on it.
private struct Art: View {
	let show: WidgetShow
	let poster: Bool
	var shaded = false

	var body: some View {
		ZStack {
			Color.black
			if let image = picture(poster ? (show.posterFile ?? show.artFile) : (show.artFile ?? show.posterFile)) {
				Image(uiImage: image).resizable().scaledToFill()
			} else {
				Image(systemName: "tv").font(.title2).foregroundStyle(.white.opacity(0.4))
			}
			if shaded {
				LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
			}
		}
	}
}

/// The ground behind a list or a shelf: the show's picture blurred into a wash
/// of its colour under a dark veil, as the app's backdrop is a colour blur.
private struct Backdrop: View {
	let show: WidgetShow?

	var body: some View {
		ZStack {
			Color.black
			if let image = picture(show?.artFile ?? show?.posterFile) {
				Image(uiImage: image).resizable().scaledToFill().blur(radius: 30).opacity(0.85)
			}
			Color.black.opacity(0.45)
		}
	}
}

private struct ShowDetails: View {
	let show: WidgetShow
	let wide: Bool
	/// On the picture itself, or beside a poster over the blurred backdrop.
	let onArt: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: 3) {
			if !onArt { Spacer(minLength: 0) }
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
					.lineLimit(onArt ? 1 : 2)
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
	let poster: Bool

	var body: some View {
		HStack(spacing: 10) {
			Art(show: show, poster: poster)
				.frame(width: poster ? 30 : 64, height: poster ? 45 : 40)
				.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
			VStack(alignment: .leading, spacing: 2) {
				Text(show.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
				Text(show.next.map { "\($0.code) · \($0.title)" } ?? show.caughtUpLine ?? "All watched")
					.font(.system(size: 12))
					.foregroundStyle(.white.opacity(0.7))
					.lineLimit(1)
			}
			Spacer(minLength: 0)
			if let next = show.next { MarkButton(episode: next, compact: true) }
		}
	}
}

/// One poster on the shelf: the episode it's up to on it, and its own Mark
/// Watched in the corner.
private struct ShelfPoster: View {
	let show: WidgetShow
	let showsTitle: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Art(show: show, poster: true, shaded: true)
				.aspectRatio(2 / 3, contentMode: .fit)
				.overlay(alignment: .bottomLeading) {
					Text(show.next?.code ?? (show.caughtUpLine == nil ? "Done" : "Caught up"))
						.font(.system(size: 10, weight: .bold))
						.foregroundStyle(.white)
						.lineLimit(1)
						.padding(6)
				}
				.overlay(alignment: .topTrailing) {
					if let next = show.next {
						Button(intent: MarkEpisodeWatchedIntent(episodeID: next.id)) {
							Image(systemName: "checkmark")
								.font(.system(size: 10, weight: .bold))
								.foregroundStyle(.white)
								.frame(width: 24, height: 24)
								.background(.black.opacity(0.45), in: Circle())
								.overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
						}
						.buttonStyle(.plain)
						.padding(4)
						.accessibilityLabel("Mark \(show.title) \(next.code) watched")
					}
				}
				.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
			if showsTitle {
				Text(show.title)
					.font(.system(size: 11, weight: .semibold))
					.foregroundStyle(.white)
					.lineLimit(1)
			}
		}
	}
}

/// The arrows on a widget set to all shows: back, where it's up to, on.
private struct PageArrows: View {
	let shows: [WidgetShow]
	let current: WidgetShow

	var body: some View {
		HStack(spacing: 2) {
			arrow("chevron.left", step: -1, label: "Previous show")
			Text("\((shows.firstIndex { $0.id == current.id } ?? 0) + 1)/\(shows.count)")
				.font(.system(size: 10, weight: .semibold).monospacedDigit())
				.foregroundStyle(.white.opacity(0.85))
			arrow("chevron.right", step: 1, label: "Next show")
		}
		.padding(.horizontal, 2)
		.background(.black.opacity(0.35), in: Capsule())
		.padding(8)
	}

	private func arrow(_ symbol: String, step: Int, label: String) -> some View {
		Button(intent: TurnUpNextPageIntent(step: step)) {
			Image(systemName: symbol)
				.font(.system(size: 10, weight: .bold))
				.foregroundStyle(.white)
				.frame(width: 22, height: 22)
		}
		.buttonStyle(.plain)
		.accessibilityLabel(label)
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
		WidgetShow(id: UUID(), title: "The Long Road", upcoming: [WidgetEpisode(id: UUID(), code: "S2 E5", title: "Low Water")],
		           watched: 12, total: 18),
		WidgetShow(id: UUID(), title: "Harbour Lights", upcoming: [],
		           watched: 8, total: 10, caughtUpLine: "Caught up · Next Friday"),
	], writtenAt: .now)
}

@main
struct WatchListWidgetBundle: WidgetBundle {
	var body: some Widget {
		UpNextWidget()
	}
}
