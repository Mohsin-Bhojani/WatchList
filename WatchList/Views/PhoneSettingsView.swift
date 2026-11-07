//
//  PhoneSettingsView.swift
//  WatchList
//
//  Settings on iPhone, in the app's paper theme — following light and dark and
//  your accent colour, like the tabs: accent colour, the watched cascade,
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

	private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

	/// No Done button: like Stats, the sheet closes with a swipe down, and its
	/// name sits where Stats puts its own.
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
			ScrollView {
				VStack(alignment: .leading, spacing: 26) {
					SheetTitle("Settings")
						.padding(.bottom, -4)
					accentSection
					episodesSection
					newEpisodesSection
					servicesSection
					dataSection
					aboutSection
				}
				.padding(18)
			}
			.background(GlassBackground())
			.toolbar(.hidden, for: .navigationBar)
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
		return VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "Accent Color", systemImage: "paintpalette.fill")
			VStack(spacing: 14) {
				ZStack(alignment: .bottomLeading) {
					Glass.paper
					RadialGradient(colors: [chosen.accent.opacity(0.75), .clear], center: UnitPoint(x: 0.15, y: 0.1),
					               startRadius: 0, endRadius: 200)
					RadialGradient(colors: [chosen.accent3.opacity(0.6), .clear], center: UnitPoint(x: 0.95, y: 0.6),
					               startRadius: 0, endRadius: 170)
					Text(BackdropLight.shared.tone == nil ? "How your screens will glow"
					     : "Your show lights the page; this stays in your controls")
						.font(.system(size: 13, weight: .semibold))
						.foregroundStyle(Glass.ink)
						.padding(.horizontal, 12)
						.padding(.vertical, 8)
						.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
						.padding(12)
				}
				.frame(height: 140)
				.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
				.animation(Glass.smooth, value: theme.accentID)
				.accessibilityHidden(true)
				HStack {
					ForEach(AccentCatalog.all) { swatch($0) }
				}
				Text(chosen.name)
					.font(.system(size: 15, weight: .semibold))
					.foregroundStyle(Glass.ink)
			}
			.padding(14)
			.glass(cornerRadius: 22)
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
		.buttonStyle(.pressable)
		.accessibilityLabel(palette.name)
		.accessibilityAddTraits(selected ? .isSelected : [])
	}

	// MARK: Episodes

	private var episodesSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "Episodes", systemImage: "list.and.film")
			VStack(alignment: .leading, spacing: 12) {
				SettingToggle(title: "Mark all episodes watched", isOn: $autoMarkEpisodes,
				              on: "On · a Watched show or season marks its episodes too",
				              off: "Off · episodes are marked one by one")
			}
			.padding(16)
			.glass(cornerRadius: 22)
		}
	}

	// MARK: New episodes

	private var newEpisodesSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "New Episodes", systemImage: "arrow.triangle.2.circlepath")
			VStack(alignment: .leading, spacing: 10) {
				SettingToggle(title: "Check for new episodes", isOn: $autoCheckEpisodes,
				              on: LibraryRefresher.lastChecked.map {
				              	"On · checked \($0.formatted(.relative(presentation: .named)))"
				              } ?? "On · once a day",
				              off: "Off · only when you tap Check now")

				divider

				SettingToggle(title: "Notify when episodes air", isOn: $notifyNewEpisodes,
				              on: "On · \(watchingPhrase)",
				              off: notifyNote ?? "Off · \(watchingPhrase)")
				.onChange(of: notifyNewEpisodes) { _, on in
					guard on else { notifyNote = nil; return }
					Task {
						if await EpisodeAlerts.requestPermission() {
							notifyNote = nil
						} else {
							notifyNewEpisodes = false
							notifyNote = "Off · notifications are off for WatchList in the Settings app"
						}
					}
				}

				DisclosureGroup("How these work") {
					Text("Once a day the iPhone adds new seasons and fills in details of episodes that just aired; your watched marks and ratings are never changed. It checks in the background a few times a day, so a notification can come a few hours after an episode airs.")
						.font(.system(size: 13, weight: .medium))
						.foregroundStyle(.secondary)
						.padding(.top, 6)
				}
				.font(.system(size: 13, weight: .semibold))
				.tint(.secondary)

				divider

				HStack(spacing: 10) {
					Button {
						Haptics.tap()
						checkNow()
					} label: {
						Text(checking ? "Checking…" : "Check now")
							.font(.system(size: 15, weight: .semibold))
							.foregroundStyle(Glass.accent)
					}
					.buttonStyle(.pressable)
					.disabled(checking || shows.isEmpty)
					.opacity(checking || shows.isEmpty ? 0.45 : 1)

					if checking { ProgressView().controlSize(.small) }
					Spacer()
				}

				if let checkResult {
					Text(checkResult)
						.font(.system(size: 13, weight: .medium))
						.foregroundStyle(.secondary)
				}
			}
			.padding(16)
			.glass(cornerRadius: 22)
		}
	}

	private func checkNow() {
		checking = true
		checkResult = nil
		Task {
			let report = await LibraryRefresher.refreshAll(shows: shows, into: ctx)
			checking = false
			checkResult = report.summary
			report.foundSomething ? Haptics.success() : Haptics.tap()
		}
	}

	// MARK: Your data

	// MARK: Streaming services

	/// The services you use, in your order: Where to watch puts the first of
	/// them that has a title on top.
	private var servicesSection: some View {
		let saved = StreamingServices.saved
		return VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "Streaming", systemImage: "play.tv")
			NavigationLink { StreamingServicesView() } label: {
				HStack(spacing: 12) {
					VStack(alignment: .leading, spacing: 3) {
						Text("Your services")
							.font(.system(size: 16, weight: .semibold))
							.foregroundStyle(Glass.ink)
						Text(saved.isEmpty ? "None yet · Where to watch uses TMDb's order"
						                   : saved.map(\.name).joined(separator: ", "))
							.font(.system(size: 13, weight: .medium))
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
					Spacer()
					Image(systemName: "chevron.right")
						.font(.system(size: 13, weight: .bold))
						.foregroundStyle(.secondary)
				}
				.padding(16)
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.glass(cornerRadius: 22)
		}
	}

	private var dataSection: some View {
		let empty = shows.isEmpty && films.isEmpty
		return VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "Your Data", systemImage: "square.and.arrow.up")
			VStack(alignment: .leading, spacing: 10) {
				Text("Export library")
					.font(.system(size: 16, weight: .semibold))
					.foregroundStyle(Glass.ink)
				Text("Saves your shows, seasons, episodes and films — statuses, verdicts, stars, episode ratings, notes and watched dates — your collections and Discover choices as one JSON file. Nothing in the app changes.")
					.font(.system(size: 13, weight: .medium))
					.foregroundStyle(.secondary)

				divider

				Button {
					Haptics.tap()
					prepareExport()
				} label: {
					Label("Export JSON…", systemImage: "square.and.arrow.up")
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(Glass.accent)
				}
				.buttonStyle(.pressable)
				.disabled(empty)
				.opacity(empty ? 0.45 : 1)

				if let exportResult {
					Text(exportResult)
						.font(.system(size: 13, weight: .medium))
						.foregroundStyle(.secondary)
				}

				divider

				Text("Restore library")
					.font(.system(size: 16, weight: .semibold))
					.foregroundStyle(Glass.ink)
				Text("Adds back the titles, collections and Discover choices in an export. Anything already in your library is left as it is.")
					.font(.system(size: 13, weight: .medium))
					.foregroundStyle(.secondary)

				Button {
					Haptics.tap()
					restoreResult = nil
					importing = true
				} label: {
					Label("Restore from JSON…", systemImage: "square.and.arrow.down")
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(Glass.accent)
				}
				.buttonStyle(.pressable)

				if let restoreResult {
					Text(restoreResult)
						.font(.system(size: 13, weight: .medium))
						.foregroundStyle(.secondary)
				}
			}
			.padding(16)
			.glass(cornerRadius: 22)
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
			report.addedSomething ? Haptics.success() : Haptics.tap()
			if report.addedSomething { WatchSync.shared.scheduleSend() }
		} catch {
			restoreResult = error.localizedDescription
		}
	}

	// MARK: About

	private var aboutSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "About", systemImage: "info.circle.fill")
			VStack(alignment: .leading, spacing: 10) {
				HStack {
					Text("Version")
						.font(.system(size: 16, weight: .semibold))
						.foregroundStyle(Glass.ink)
					Spacer()
					Text(appVersion)
						.font(.system(size: 16, weight: .medium))
						.foregroundStyle(.secondary)
				}
				divider
				Text("Titles, posters and details are from TMDb. This product uses the TMDb API but is not endorsed or certified by TMDb.")
					.font(.system(size: 13, weight: .medium))
					.foregroundStyle(.secondary)
			}
			.padding(16)
			.glass(cornerRadius: 22)
		}
	}

	private var divider: some View {
		Rectangle()
			.fill(Glass.hairline.opacity(0.12))
			.frame(height: 1)
	}

	private var appVersion: String {
		let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
		let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
		return "\(version) (\(build))"
	}
}

/// A switch, after design B of the alternatives: its name, and under it what
/// it's doing right now, a green dot while on.
struct SettingToggle: View {
	let title: String
	@Binding var isOn: Bool
	let on: String
	let off: String

	var body: some View {
		Toggle(isOn: $isOn) {
			VStack(alignment: .leading, spacing: 3) {
				Text(title)
					.font(.system(size: 16, weight: .semibold))
					.foregroundStyle(Glass.ink)
				HStack(spacing: 6) {
					Circle()
						.fill(isOn ? Glass.watched : Glass.ink.opacity(0.3))
						.frame(width: 7, height: 7)
					Text(isOn ? on : off)
						.font(.system(size: 13, weight: .medium))
						.foregroundStyle(.secondary)
						.contentTransition(.opacity)
				}
			}
		}
		.tint(Glass.accent)
	}
}
