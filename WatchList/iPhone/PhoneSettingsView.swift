//
//  PhoneSettingsView.swift
//  WatchList
//
//  Settings on iPhone, in the app's paper theme — following light and dark and
//  your accent colour, like the tabs: accent colour, the watched cascade,
//  new-episode checks, the Where to watch country, your Jellyfin server and
//  put.io (JellyfinSettings, PutioSettings), exporting your library as JSON,
//  and About. The same settings, under the same keys, as the shared
//  SettingsView, so either screen shows a change made on the other — except
//  the Where to watch country, Jellyfin and put.io, which only the iPhone
//  pages use.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct PhoneSettingsView: View {
	@ObservedObject private var theme = AppTheme.shared
	@AppStorage("autoMarkEpisodesWatched") private var autoMarkEpisodes = true
	@AppStorage("autoCheckNewEpisodes") private var autoCheckEpisodes = true
	@AppStorage(WatchRegion.key) private var watchRegion = ""
	/// TMDb's countries with watch data, by name; empty until loaded.
	@State private var watchRegions: [(code: String, name: String)] = []

	@Environment(\.modelContext) private var ctx
	@Query private var shows: [Show]
	@State private var checking = false
	@State private var checkResult: String?

	@Query private var films: [Film]
	@Query(sort: \TitleCollection.created) private var collections: [TitleCollection]
	@State private var exportDocument: ExportDocument?
	@State private var exporting = false
	@State private var exportResult: String?

	private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

	/// No Done button: like Stats, the sheet closes with a swipe down, and its
	/// name sits where Stats puts its own.
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 26) {
					SheetTitle("Settings")
						.padding(.bottom, -4)
					accentSection
					episodesSection
					newEpisodesSection
					whereToWatchSection
					JellyfinSettingsSection()
					PutioSettingsSection()
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
		}
	}

	// MARK: Accent

	private var accentSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "Accent Color", systemImage: "paintpalette.fill")
			LazyVGrid(columns: columns, spacing: 12) {
				ForEach(AccentCatalog.all) { swatch($0) }
			}
		}
	}

	/// The chosen swatch is ringed in its own colour.
	private func swatch(_ palette: AccentPalette) -> some View {
		let selected = theme.accentID == palette.id
		let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
		return Button {
			Haptics.selection()
			withAnimation(Glass.pop) { theme.setAccent(palette.id) }
		} label: {
			VStack(spacing: 8) {
				ZStack {
					Circle()
						.fill(palette.accent)
						.frame(width: 34, height: 34)
					if selected {
						Image(systemName: "checkmark")
							.font(.system(size: 14, weight: .bold))
							.foregroundStyle(.white)
					}
				}
				Text(palette.name)
					.font(.system(size: 11, weight: .semibold))
					.foregroundStyle(selected ? Glass.ink : .secondary)
					.lineLimit(1)
			}
			.frame(maxWidth: .infinity)
			.padding(.vertical, 13)
			.glass(cornerRadius: 18)
			.overlay(shape.strokeBorder(palette.accent.opacity(selected ? 1 : 0), lineWidth: 2))
		}
		.buttonStyle(.pressable)
		.accessibilityLabel(palette.name)
		.accessibilityAddTraits(selected ? .isSelected : [])
	}

	// MARK: Episodes

	private var episodesSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "Episodes", systemImage: "list.and.film")
			VStack(alignment: .leading, spacing: 8) {
				Toggle(isOn: $autoMarkEpisodes) {
					Text("Mark all episodes watched")
						.font(.system(size: 16, weight: .semibold))
						.foregroundStyle(Glass.ink)
				}
				.tint(Glass.accent)
				Text("When you set a show or season to Watched, mark every episode watched too.")
					.font(.system(size: 13, weight: .medium))
					.foregroundStyle(.secondary)
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
				Toggle(isOn: $autoCheckEpisodes) {
					Text("Check automatically")
						.font(.system(size: 16, weight: .semibold))
						.foregroundStyle(Glass.ink)
				}
				.tint(Glass.accent)
				Text("Looks for new seasons and episodes once a day. Only ever adds — your watched marks and ratings are never changed.")
					.font(.system(size: 13, weight: .medium))
					.foregroundStyle(.secondary)

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
				} else if let last = LibraryRefresher.lastChecked {
					Text("Last checked \(last.formatted(.relative(presentation: .named))).")
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

	// MARK: Where to watch

	private var whereToWatchSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "Where to Watch", systemImage: "tv")
			VStack(alignment: .leading, spacing: 8) {
				HStack {
					Text("Country")
						.font(.system(size: 16, weight: .semibold))
						.foregroundStyle(Glass.ink)
					Spacer()
					Picker("Country", selection: $watchRegion) {
						Text("This iPhone's region (\(WatchRegion.name(WatchRegion.phone)))").tag("")
						// The chosen country, even before TMDb's list arrives.
						if !watchRegion.isEmpty, !watchRegions.contains(where: { $0.code == watchRegion }) {
							Text(WatchRegion.name(watchRegion)).tag(watchRegion)
						}
						ForEach(watchRegions, id: \.code) { Text($0.name).tag($0.code) }
					}
					.pickerStyle(.menu)
					.tint(Glass.accent)
				}
				Text("Show and film pages list the services that stream, rent or sell a title in this country.")
					.font(.system(size: 13, weight: .medium))
					.foregroundStyle(.secondary)
			}
			.padding(16)
			.glass(cornerRadius: 22)
		}
		.task {
			guard watchRegions.isEmpty, let regions = try? await TMDbService.shared.watchRegions() else { return }
			watchRegions = regions.map { ($0.iso_3166_1, WatchRegion.name($0.iso_3166_1)) }
				.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		}
	}

	// MARK: Your data

	private var dataSection: some View {
		let empty = shows.isEmpty && films.isEmpty
		return VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "Your Data", systemImage: "square.and.arrow.up")
			VStack(alignment: .leading, spacing: 10) {
				Text("Export library")
					.font(.system(size: 16, weight: .semibold))
					.foregroundStyle(Glass.ink)
				Text("Saves your shows, seasons, episodes and films — statuses, verdicts, stars, episode ratings, notes and watched dates — and your collections as one JSON file. Nothing in the app changes.")
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
			}
			.padding(16)
			.glass(cornerRadius: 22)
		}
	}

	/// Builds the file from what's in the library now, then asks where to save
	/// it. Reading only — nothing in the library is touched.
	private func prepareExport() {
		let export = LibraryExport(shows: shows, films: films, collections: collections)
		do {
			exportDocument = ExportDocument(data: try export.encoded())
			exportResult = nil
			exporting = true
		} catch {
			exportResult = "Couldn't build the export: \(error.localizedDescription)"
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
