//
//  PhoneSettingsView.swift
//  WatchList
//
//  Settings on iPhone: a system Form over the app's glass background — accent colour, the watched cascade,
//  new-episode checks, exporting your library as JSON, and About. The same settings, under the same keys, as the
//  shared SettingsView, so either screen shows a change made on the other.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import WatchListCore
import WatchListLibrary

struct PhoneSettingsView: View {
	@ObservedObject private var theme = AppTheme.shared
	@Environment(\.dismiss) private var dismiss
	@AppStorage("autoMarkEpisodesWatched") private var autoMarkEpisodes = true
	@AppStorage("autoCheckNewEpisodes") private var autoCheckEpisodes = true
	@AppStorage(EpisodeAlerts.enabledKey) private var notifyNewEpisodes = false
	@State private var notifyNote: String?

	@Environment(\.modelContext) private var ctx
	@Query private var shows: [Show]
	@State private var checking = false
	@State private var checkResult: String?

	@Query private var films: [Film]
	@Query(sort: \TitleCollection.created) private var collections: [TitleCollection]
	@State private var exportDocument: ExportDocument?
	@State private var exporting = false
	@State private var exportResult: String?
	@Query private var decisions: [SuggestionDecision]
	@State private var importing = false
	@State private var restoreResult: String?


	/// "for the 3 shows you're watching", "for the show you're watching".
	private var watchingPhrase: String {
		let count = HomeFeed.watching(shows).count
		switch count {
		case 0: return "for shows you're watching"
		case 1: return "for the show you're watching"
		default: return "for the \(count) shows you're watching"
		}
	}

	var body: some View {
		NavigationStack {
			Form {
				accentSection
				episodesSection
				newEpisodesSection
				servicesSection
				dataSection
				aboutSection
			}
			.scrollContentBackground(.hidden)
			.background(GlassBackground())
			.navigationTitle("Settings")
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Button(role: .close) { dismiss() }
				}
			}
			.tint(Glass.accent)
			.fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json,
			              defaultFilename: LibraryExport.defaultFilename(for: .now)) { result in
				switch result {
				case .success(let url):
					exportResult = "Saved \u{201C}\(url.lastPathComponent)\u{201D}."
					Haptics.success()
				case .failure(let error):
					exportResult = "Couldn't save the export: \(error.localizedDescription)"
				}
			}
			.fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
				switch result {
				case .success(let url): restore(from: url)
				case .failure(let error): restoreResult = "Couldn't open the file: \(error.localizedDescription)"
				}
			}
		}
	}

	// MARK: Accent

	/// After design A of the alternatives: how the chosen palette glows, live,
	/// over a row of swatches, the chosen one ringed, and its name.
	private var accentSection: some View {
		let chosen = AccentCatalog.all.first { $0.id == theme.accentID } ?? AccentCatalog.all[0]
		return Section {
			ZStack(alignment: .bottomLeading) {
				Glass.paper
				RadialGradient(colors: [chosen.accent.opacity(0.75), .clear], center: UnitPoint(x: 0.15, y: 0.1),
				               startRadius: 0, endRadius: 200)
				RadialGradient(colors: [chosen.accent3.opacity(0.6), .clear], center: UnitPoint(x: 0.95, y: 0.6),
				               startRadius: 0, endRadius: 170)
				Text(BackdropLight.shared.tone == nil ? "How your screens will glow"
				     : "Your show lights the page; this stays in your controls")
					.font(.footnote.weight(.semibold))
					.foregroundStyle(Glass.ink)
					.padding(.horizontal, 12)
					.padding(.vertical, 8)
					.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
					.padding(12)
			}
			.frame(minHeight: 140)
			.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
			.animation(Glass.smooth, value: theme.accentID)
			.accessibilityHidden(true)
			.listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
			HStack {
				ForEach(AccentCatalog.all) { swatch($0) }
			}
		} header: {
			Text("Accent Color")
		} footer: {
			Text(chosen.name)
		}
	}

	/// The chosen swatch is ringed in ink, apart from its own colour.
	private func swatch(_ palette: AccentPalette) -> some View {
		let selected = theme.accentID == palette.id
		return Button {
			Haptics.selection()
			withAnimation(Glass.pop) { theme.setAccent(palette.id) }
		} label: {
			Circle()
				.fill(palette.accent)
				.frame(width: 38, height: 38)
				.padding(3)
				.overlay(Circle().strokeBorder(Glass.ink.opacity(selected ? 0.9 : 0), lineWidth: 2))
				.frame(maxWidth: .infinity)
				.contentShape(Circle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(palette.name)
		.accessibilityAddTraits(selected ? .isSelected : [])
	}

	// MARK: Episodes

	private var episodesSection: some View {
		Section("Episodes") {
			SettingToggle(title: "Mark all episodes watched", isOn: $autoMarkEpisodes,
			              on: "A Watched show or season marks its episodes too",
			              off: "Episodes are marked one by one")
		}
	}

	// MARK: New episodes

	private var newEpisodesSection: some View {
		Section {
			SettingToggle(title: "Check for new episodes", isOn: $autoCheckEpisodes,
			              on: LibraryRefresher.lastChecked.map {
			              	"Checked \($0.formatted(.relative(presentation: .named)))"
			              } ?? "Once a day",
			              off: "Only when you tap Check Now")
			SettingToggle(title: "Notify when episodes air", isOn: $notifyNewEpisodes,
			              on: watchingPhrase.capitalizedFirst,
			              off: notifyNote ?? watchingPhrase.capitalizedFirst)
			.onChange(of: notifyNewEpisodes) { _, on in
				guard on else { notifyNote = nil; return }
				Task {
					if await EpisodeAlerts.requestPermission() {
						notifyNote = nil
					} else {
						notifyNewEpisodes = false
						notifyNote = "Notifications are off for WatchList in the Settings app"
					}
				}
			}
			Button {
				checkNow()
			} label: {
				HStack {
					Text(checking ? "Checking…" : "Check Now")
					Spacer()
					if checking { ProgressView() }
				}
			}
			.disabled(checking || shows.isEmpty)
		} header: {
			Text("New Episodes")
		} footer: {
			VStack(alignment: .leading, spacing: 6) {
				if let checkResult { Text(checkResult) }
				Text("Once a day the iPhone adds new seasons and fills in details of episodes that just aired; your watched marks and ratings are never changed. It checks in the background a few times a day, so a notification can come a few hours after an episode airs.")
			}
		}
	}

	private func checkNow() {
		checking = true
		checkResult = nil
		Task {
			let report = await LibraryRefresher.refreshAll(shows: shows, into: ctx)
			checking = false
			checkResult = report.summary
			if report.foundSomething { Haptics.success() }
		}
	}

	// MARK: Your data

	// MARK: Streaming services

	/// The services you use, in your order: Where to watch puts the first of
	/// them that has a title on top.
	private var servicesSection: some View {
		let saved = StreamingServices.saved
		return Section("Streaming") {
			NavigationLink { StreamingServicesView() } label: {
				VStack(alignment: .leading, spacing: 3) {
					Text("Your Services")
					Text(saved.isEmpty ? "None yet · Where to watch uses TMDb's order"
					                   : saved.map(\.name).joined(separator: ", "))
						.font(.footnote)
						.foregroundStyle(.secondary)
						.lineLimit(2)
				}
			}
		}
	}

	private var dataSection: some View {
		let empty = shows.isEmpty && films.isEmpty
		return Group {
			Section {
				Button("Export JSON…", systemImage: "square.and.arrow.up") { prepareExport() }
					.disabled(empty)
			} header: {
				Text("Your Data")
			} footer: {
				VStack(alignment: .leading, spacing: 6) {
					Text("Saves your shows, seasons, episodes and films — statuses, verdicts, stars, episode ratings, notes and watched dates — your collections and Discover choices as one JSON file. Nothing in the app changes.")
					if let exportResult { Text(exportResult) }
				}
			}
			Section {
				Button("Restore from JSON…", systemImage: "square.and.arrow.down") {
					restoreResult = nil
					importing = true
				}
			} footer: {
				VStack(alignment: .leading, spacing: 6) {
					Text("Adds back the titles, collections and Discover choices in an export. Anything already in your library is left as it is.")
					if let restoreResult { Text(restoreResult) }
				}
			}
		}
	}

	/// Builds the file from what's in the library now, then asks where to save
	/// it. Reading only — nothing in the library is touched.
	private func prepareExport() {
		let export = LibraryExport(shows: shows, films: films, collections: collections, decisions: decisions)
		do {
			exportDocument = ExportDocument(data: try export.encoded())
			exportResult = nil
			exporting = true
		} catch {
			exportResult = "Couldn't build the export: \(error.localizedDescription)"
		}
	}

	/// Reads the picked file and adds what it holds that the library doesn't.
	private func restore(from url: URL) {
		let scoped = url.startAccessingSecurityScopedResource()
		defer { if scoped { url.stopAccessingSecurityScopedResource() } }
		do {
			let export = try LibraryRestore.read(try Data(contentsOf: url))
			let report = try LibraryRestore.restore(export, into: ctx)
			restoreResult = report.summary
			if report.addedSomething { Haptics.success() }
			if report.addedSomething { WatchSync.shared.scheduleSend() }
		} catch {
			restoreResult = error.localizedDescription
		}
	}

	// MARK: About

	private var aboutSection: some View {
		Section {
			LabeledContent("Version", value: appVersion)
		} header: {
			Text("About")
		} footer: {
			Text("Titles, posters and details are from TMDb. This product uses the TMDb API but is not endorsed or certified by TMDb.")
		}
	}

	private var appVersion: String {
		let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
		let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
		return "\(version) (\(build))"
	}
}

/// A switch with what it's doing right now under its name.
struct SettingToggle: View {
	let title: String
	@Binding var isOn: Bool
	let on: String
	let off: String

	var body: some View {
		Toggle(isOn: $isOn) {
			Text(title)
			Text(isOn ? on : off)
				.contentTransition(.opacity)
		}
	}
}

private extension String {
	/// "for the show you're watching" → "For the show you're watching".
	var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
