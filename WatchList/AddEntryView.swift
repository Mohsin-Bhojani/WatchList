//
//  AddEntryView.swift
//  WatchList
//
//  Two ways to add an entry:
//    1) Paste an IMDb link  -> everything is pulled automatically (TMDb)
//    2) Manual entry        -> the classic form, like the old app
//

import SwiftUI
import SwiftData
import PhotosUI

struct AddEntryView: View {
	@Environment(\.modelContext) private var ctx
	@Environment(\.dismiss) private var dismiss

	enum Mode: String, CaseIterable, Identifiable {
		case search = "Search"
		case link = "IMDb Link"
		case manual = "Manual"
		var id: String { rawValue }
	}

	@State private var mode: Mode = .search
	/// Titles added while this sheet has been open. Once anything has landed in
	/// the library there is nothing left to cancel, so the button says "Done".
	@State private var addedCount = 0

	var body: some View {
		NavigationStack {
			ZStack {
				GlassBackground()
				ScrollView {
					VStack(spacing: 18) {
						modePicker
						switch mode {
						case .search: TMDbSearchSection(addedCount: $addedCount)
						case .link:   LinkImportSection()
						case .manual: ManualEntrySection()
						}
					}
					.padding(18)
				}
			}
			.navigationTitle("Add to WatchList")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button(addedCount > 0 ? "Done" : "Cancel") { dismiss() }
				}
			}
		}
	}

	private var modePicker: some View {
		Picker("Mode", selection: $mode) {
			ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
		}
		.pickerStyle(.segmented)
	}
}

// MARK: - Link import

private struct LinkImportSection: View {
	@Environment(\.modelContext) private var ctx
	@Environment(\.dismiss) private var dismiss
	@StateObject private var importer = ImportCoordinator()

	@State private var link = ""

	private var statusText: String {
		switch importer.phase {
		case .idle: return ""
		case .resolving: return "Looking up the title…"
		case .fetchingDetails: return "Fetching details…"
		case .fetchingEpisodes(let done, let total): return "Fetching seasons & episodes (\(done)/\(total))…"
		case .done: return "Added to your library!"
		case .failed(let m): return m
		}
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			VStack(alignment: .leading, spacing: 10) {
				SectionLabel(text: "Paste IMDb link", systemImage: "link")
				TextField("https://www.imdb.com/title/tt0468569/", text: $link)
					.font(.system(size: 15, weight: .medium, design: .rounded))
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
					.keyboardType(.URL)
					.padding(15)
					.glass(cornerRadius: 16)
				Text("Works for films and TV shows. For shows, every season and episode is imported automatically. Trivia is pulled from IMDb when you open a title.")
					.font(.system(size: 12, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
			}

			if !TMDbConfig.isConfigured {
				Label("Add your free TMDb API key in TMDbService.swift to enable automatic import.",
				      systemImage: "exclamationmark.triangle.fill")
					.font(.system(size: 13, weight: .semibold, design: .rounded))
					.foregroundStyle(.orange)
					.padding(14)
					.glass(cornerRadius: 16)
			}

			Button {
				Haptics.tap(.medium)
				Task {
					let result = await importer.importFromIMDb(link, into: ctx)
					if result != nil {
						Haptics.success()
						try? await Task.sleep(nanoseconds: 450_000_000)
						dismiss()
					} else {
						Haptics.warning()
					}
				}
			} label: {
				HStack(spacing: 8) {
					if importer.isWorking { ProgressView().tint(.white) }
					Image(systemName: "arrow.down.circle.fill")
					Text(importer.isWorking ? "Importing…" : "Pull from IMDb")
				}
				.font(.system(size: 16, weight: .bold, design: .rounded))
				.foregroundStyle(.white)
				.frame(maxWidth: .infinity)
				.padding(.vertical, 15)
				.background(
					Capsule().fill(LinearGradient(colors: [Glass.accent, Glass.accent2],
					                              startPoint: .leading, endPoint: .trailing))
				)
			}
			.buttonStyle(.pressable)
			.disabled(importer.isWorking || link.trimmingCharacters(in: .whitespaces).isEmpty)
			.opacity(link.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)

			if !statusText.isEmpty {
				HStack(spacing: 8) {
					if case .failed = importer.phase {
						Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
					} else if case .done = importer.phase {
						Image(systemName: "checkmark.circle.fill").foregroundStyle(Glass.watched)
					}
					Text(statusText)
						.font(.system(size: 13, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(14)
				.glass(cornerRadius: 16)
			}
		}
	}
}

// MARK: - TMDb title search

private struct TMDbSearchSection: View {
	@Environment(\.modelContext) private var ctx
	@StateObject private var importer = ImportCoordinator()

	@Binding var addedCount: Int

	@Query private var libraryShows: [Show]
	@Query private var libraryFilms: [Film]

	@State private var query = ""
	@State private var results: [TMDbSearchItem] = []
	@State private var searching = false
	@State private var searchError: String?
	/// Rows are keyed by kind + id: TMDb numbers films and shows separately,
	/// so the same id can arrive as both.
	@State private var addingKey: String?
	@State private var addedKeys: Set<String> = []
	@State private var lastAddedTitle: String?
	@State private var importError: String?

	private func kind(of item: TMDbSearchItem) -> MediaKind {
		item.media_type == "tv" ? .show : .film
	}

	private func key(_ kind: MediaKind, _ id: Int) -> String { "\(kind.rawValue)-\(id)" }
	private func key(_ item: TMDbSearchItem) -> String { key(kind(of: item), item.id) }

	/// Everything already imported, by the same key the rows use. Titles added
	/// by hand have no `tmdbID` and so cannot be matched — they are skipped.
	private var libraryKeys: Set<String> {
		var keys = Set(libraryShows.compactMap { $0.tmdbID.map { key(.show, $0) } })
		keys.formUnion(libraryFilms.compactMap { $0.tmdbID.map { key(.film, $0) } })
		return keys
	}

	private var addedText: String? {
		guard let lastAddedTitle else { return nil }
		return addedKeys.count > 1
			? "Added \u{201C}\(lastAddedTitle)\u{201D} · \(addedKeys.count) titles so far. Search again to add more."
			: "Added \u{201C}\(lastAddedTitle)\u{201D}. Search again to add more, or tap Done."
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			VStack(alignment: .leading, spacing: 10) {
				SectionLabel(text: "Search by title", systemImage: "magnifyingglass")
				HStack(spacing: 10) {
					Image(systemName: "magnifyingglass")
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(.secondary)
					TextField("e.g. The Dark Knight", text: $query)
						.font(.system(size: 15, weight: .medium, design: .rounded))
						.autocorrectionDisabled()
						.submitLabel(.search)
					if searching {
						ProgressView()
					} else if !query.isEmpty {
						Button { query = "" } label: {
							Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
						}
						.buttonStyle(.plain)
					}
				}
				.padding(15)
				.glass(cornerRadius: 16)
				Text("Searches The Movie Database. Pick a result to import it — for shows, every season and episode comes with it. This stays open so you can add several in a row.")
					.font(.system(size: 12, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
			}

			if !TMDbConfig.isConfigured {
				Label("Add your free TMDb API key in TMDbService.swift to enable search.",
				      systemImage: "exclamationmark.triangle.fill")
					.font(.system(size: 13, weight: .semibold, design: .rounded))
					.foregroundStyle(.orange)
					.padding(14)
					.glass(cornerRadius: 16)
			}

			if let addedText {
				statusRow(icon: "checkmark.circle.fill", tint: Glass.watched, text: addedText)
			}
			if let importError {
				statusRow(icon: "xmark.octagon.fill", tint: .red, text: importError)
			}
			if let searchError {
				statusRow(icon: "xmark.octagon.fill", tint: .red, text: searchError)
			}

			if !results.isEmpty {
				resultList
			} else if !query.trimmingCharacters(in: .whitespaces).isEmpty,
			          !searching, searchError == nil {
				Text("No matches for \u{201C}\(query)\u{201D}.")
					.font(.system(size: 13, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(14).glass(cornerRadius: 16)
			}
		}
		.task(id: query) { await runSearch() }
	}

	private func runSearch() async {
		let trimmed = query.trimmingCharacters(in: .whitespaces)
		// The "added" tally deliberately survives a new query — it is the running
		// record of this session. A stale import failure does not.
		importError = nil
		guard trimmed.count >= 2 else {
			results = []; searchError = nil; searching = false
			return
		}
		// Debounce rapid typing; a new keystroke cancels this task first.
		try? await Task.sleep(nanoseconds: 350_000_000)
		if Task.isCancelled { return }
		searching = true; searchError = nil
		do {
			let items = try await TMDbService.shared.multiSearch(query: trimmed)
			if Task.isCancelled { return }
			results = items
		} catch {
			if Task.isCancelled { return }
			searchError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
			results = []
		}
		searching = false
	}

	/// Built once per pass, not once per row: `libraryKeys` walks the whole library.
	private var resultList: some View {
		let inLibrary = libraryKeys
		return VStack(spacing: 10) {
			ForEach(results) { resultRow($0, alreadyInLibrary: inLibrary.contains(key($0))) }
		}
	}

	private func add(_ item: TMDbSearchItem) {
		addingKey = key(item)
		importError = nil
		Haptics.tap(.medium)
		Task {
			let result = await importer.importFromTMDb(id: item.id, kind: kind(of: item), into: ctx)
			addingKey = nil
			if result != nil {
				Haptics.success()
				addedKeys.insert(key(item))
				lastAddedTitle = item.displayTitle
				addedCount += 1
			} else {
				Haptics.warning()
				if case .failed(let message) = importer.phase { importError = message }
			}
		}
	}

	private func resultRow(_ item: TMDbSearchItem, alreadyInLibrary: Bool) -> some View {
		let isShow = kind(of: item) == .show
		let year = String((item.release_date ?? item.first_air_date ?? "").prefix(4))
		// Added just now reads differently from "you already had this".
		let addedNow = addedKeys.contains(key(item))
		let owned = addedNow || alreadyInLibrary
		let tag = addedNow ? "Added" : (alreadyInLibrary ? "In your library" : "")
		let subtitle = [isShow ? "TV Series" : "Film", year, tag]
			.filter { !$0.isEmpty }.joined(separator: " · ")
		return Button { add(item) } label: {
			HStack(spacing: 12) {
				PosterImage(urlString: TMDbConfig.poster(item.poster_path),
				            systemPlaceholder: isShow ? "tv" : "film")
					.frame(width: 46, height: 69)
					.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
				VStack(alignment: .leading, spacing: 3) {
					Text(item.displayTitle)
						.font(.system(size: 15, weight: .bold, design: .serif))
						.foregroundStyle(.primary)
						.lineLimit(2)
					Text(subtitle)
						.font(.system(size: 12, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
				}
				Spacer(minLength: 0)
				if addingKey == key(item) {
					ProgressView()
				} else {
					Image(systemName: owned ? "checkmark.circle.fill" : "plus.circle.fill")
						.font(.system(size: 22, weight: .semibold))
						.foregroundStyle(owned ? Glass.watched : Glass.accent)
				}
			}
			.padding(10)
			.glass(cornerRadius: 16)
		}
		.buttonStyle(.pressable)
		.disabled(importer.isWorking || owned)
		.opacity(owned ? 0.6 : 1)
	}

	private func statusRow(icon: String, tint: Color, text: String) -> some View {
		HStack(spacing: 8) {
			Image(systemName: icon).foregroundStyle(tint)
			Text(text)
				.font(.system(size: 13, weight: .medium, design: .rounded))
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(14)
		.glass(cornerRadius: 16)
	}
}

// MARK: - Manual entry

private struct ManualEntrySection: View {
	@Environment(\.modelContext) private var ctx
	@Environment(\.dismiss) private var dismiss

	@State private var kind: MediaKind = .show
	@State private var title = ""
	@State private var genre = ""
	@State private var year = ""
	@State private var synopsis = ""
	@State private var imdb = ""
	@State private var status: WatchStatus = .toWatch
	@State private var rating: Rating? = nil
	@State private var notes = ""
	@State private var posterItem: PhotosPickerItem?
	@State private var posterData: Data?

	private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

	var body: some View {
		VStack(alignment: .leading, spacing: 18) {
			field("Poster (optional)") { posterPicker }

			field("Type") {
				HStack(spacing: 8) {
					ForEach(MediaKind.allCases) { k in
						let selected = kind == k
						Button {
							Haptics.selection(); withAnimation(Glass.pop) { kind = k }
						} label: {
							HStack(spacing: 6) {
								Image(systemName: k.systemImage).font(.system(size: 13, weight: .bold))
								Text(k.rawValue).font(.system(size: 14, weight: .semibold, design: .rounded))
							}
							.foregroundStyle(selected ? .white : Color.primary)
							.frame(maxWidth: .infinity)
							.padding(.vertical, 12)
							.background { if selected { Capsule().fill(Glass.accent) } }
						}
						.buttonStyle(.pressable)
					}
				}
				.padding(5)
				.glass(cornerRadius: 26)
			}

			field("Title") { textField("e.g. The Dark Knight", $title) }
			field("Genre (optional)") { textField("e.g. Action, Drama", $genre) }
			field(kind == .show ? "First air year (optional)" : "Year (optional)") {
				textField("e.g. 2008", $year).keyboardType(.numberPad)
			}
			field("IMDb link or id (optional)") {
				textField("tt0468569", $imdb).textInputAutocapitalization(.never).autocorrectionDisabled()
			}
			field("Synopsis (optional)") {
				TextField("What's it about?", text: $synopsis, axis: .vertical)
					.lineLimit(3...6)
					.font(.system(size: 15, weight: .medium, design: .rounded))
					.padding(15).glass(cornerRadius: 16)
			}
			field("Status") { StatusPicker(status: $status) }
			field("Rating (optional)") { RatingPicker(rating: $rating) }
			field("Notes (optional)") {
				TextField("Any thoughts…", text: $notes, axis: .vertical)
					.lineLimit(2...4)
					.font(.system(size: 15, weight: .medium, design: .rounded))
					.padding(15).glass(cornerRadius: 16)
			}

			if kind == .show {
				Text("Tip: after saving, open the show to add seasons and episodes by hand.")
					.font(.system(size: 12, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
			}

			Button {
				save()
			} label: {
				Text("Add \(kind.rawValue)")
					.font(.system(size: 16, weight: .bold, design: .rounded))
					.foregroundStyle(.white)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 15)
					.background(Capsule().fill(LinearGradient(colors: [Glass.accent, Glass.accent2],
					                                         startPoint: .leading, endPoint: .trailing)))
			}
			.buttonStyle(.pressable)
			.disabled(!canSave)
			.opacity(canSave ? 1 : 0.5)
		}
	}

	private func save() {
		let imdbID = IMDb.id(from: imdb)
		let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
		let posterURL = posterData.flatMap { ManualPosterStore.save($0) } ?? ""
		switch kind {
		case .show:
			let show = Show(title: trimmedTitle, overview: synopsis, genre: genre,
			                firstAirYear: year, posterURL: posterURL, imdbID: imdbID,
			                status: status, rating: rating, notes: notes)
			ctx.insert(show)
		case .film:
			let film = Film(title: trimmedTitle, synopsis: synopsis, genre: genre, year: year,
			                posterURL: posterURL, imdbID: imdbID, status: status, rating: rating, notes: notes)
			ctx.insert(film)
		}
		Haptics.success()
		dismiss()
	}

	// Small helpers
	@ViewBuilder private func field(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			SectionLabel(text: label)
			content()
		}
	}

	private func textField(_ placeholder: String, _ text: Binding<String>) -> some View {
		TextField(placeholder, text: text)
			.font(.system(size: 15, weight: .medium, design: .rounded))
			.padding(15)
			.glass(cornerRadius: 16)
	}

	// MARK: Poster picker

	private var posterPicker: some View {
		PhotosPicker(selection: $posterItem, matching: .images) {
			HStack(spacing: 12) {
				posterThumbnail
				VStack(alignment: .leading, spacing: 2) {
					Text(posterData == nil ? "Choose a poster" : "Poster selected")
						.font(.system(size: 15, weight: .semibold, design: .rounded))
						.foregroundStyle(.primary)
					Text(posterData == nil ? "Optional — pick a photo from your library" : "Tap to change")
						.font(.system(size: 12, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
				}
				Spacer(minLength: 0)
				if posterData != nil {
					Button {
						posterItem = nil
						posterData = nil
					} label: {
						Image(systemName: "xmark.circle.fill")
							.foregroundStyle(.secondary)
					}
					.buttonStyle(.plain)
				}
			}
			.padding(12)
			.glass(cornerRadius: 16)
		}
		.buttonStyle(.pressable)
		.onChange(of: posterItem) { _, newItem in
			Task {
				if let newItem, let data = try? await newItem.loadTransferable(type: Data.self) {
					posterData = data
				}
			}
		}
	}

	@ViewBuilder private var posterThumbnail: some View {
		if let posterData, let uiImage = UIImage(data: posterData) {
			Image(uiImage: uiImage)
				.resizable()
				.aspectRatio(2.0 / 3.0, contentMode: .fill)
				.frame(width: 44, height: 66)
				.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
		} else {
			RoundedRectangle(cornerRadius: 8, style: .continuous)
				.fill(Glass.hairline.opacity(0.1))
				.frame(width: 44, height: 66)
				.overlay(
					Image(systemName: "photo")
						.font(.system(size: 16, weight: .medium))
						.foregroundStyle(.secondary)
				)
		}
	}
}
