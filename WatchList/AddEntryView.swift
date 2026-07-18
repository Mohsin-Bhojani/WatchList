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

	var body: some View {
		NavigationStack {
			ZStack {
				GlassBackground()
				ScrollView {
					VStack(spacing: 18) {
						modePicker
						switch mode {
						case .search: TMDbSearchSection()
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
					Button("Cancel") { dismiss() }
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
	@Environment(\.dismiss) private var dismiss
	@StateObject private var importer = ImportCoordinator()

	@State private var query = ""
	@State private var results: [TMDbSearchItem] = []
	@State private var searching = false
	@State private var searchError: String?
	@State private var addingID: Int?
	@State private var addedTitle: String?

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
				Text("Searches The Movie Database. Pick a result to import it — for shows, every season and episode comes with it.")
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

			if let addedTitle {
				statusRow(icon: "checkmark.circle.fill", tint: Glass.watched,
				          text: "Added \u{201C}\(addedTitle)\u{201D} to your library!")
			}
			if let searchError {
				statusRow(icon: "xmark.octagon.fill", tint: .red, text: searchError)
			}

			if !results.isEmpty {
				VStack(spacing: 10) {
					ForEach(results) { resultRow($0) }
				}
			} else if !query.trimmingCharacters(in: .whitespaces).isEmpty,
			          !searching, searchError == nil, addedTitle == nil {
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
		addedTitle = nil
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

	private func add(_ item: TMDbSearchItem) {
		let kind: MediaKind = item.media_type == "tv" ? .show : .film
		addingID = item.id
		Haptics.tap(.medium)
		Task {
			let result = await importer.importFromTMDb(id: item.id, kind: kind, into: ctx)
			addingID = nil
			if result != nil {
				Haptics.success()
				addedTitle = item.displayTitle
				try? await Task.sleep(nanoseconds: 500_000_000)
				dismiss()
			} else {
				Haptics.warning()
			}
		}
	}

	private func resultRow(_ item: TMDbSearchItem) -> some View {
		let isShow = item.media_type == "tv"
		let year = String((item.release_date ?? item.first_air_date ?? "").prefix(4))
		let subtitle = [isShow ? "TV Series" : "Film", year].filter { !$0.isEmpty }.joined(separator: " · ")
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
				if addingID == item.id {
					ProgressView()
				} else {
					Image(systemName: "plus.circle.fill")
						.font(.system(size: 22, weight: .semibold))
						.foregroundStyle(Glass.accent)
				}
			}
			.padding(10)
			.glass(cornerRadius: 16)
		}
		.buttonStyle(.pressable)
		.disabled(importer.isWorking)
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
			show.personalUpdatedAt = .now
			ctx.insert(show)
		case .film:
			let film = Film(title: trimmedTitle, synopsis: synopsis, genre: genre, year: year,
			                posterURL: posterURL, imdbID: imdbID, status: status, rating: rating, notes: notes)
			film.personalUpdatedAt = .now
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
