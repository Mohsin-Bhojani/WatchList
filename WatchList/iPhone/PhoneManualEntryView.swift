//
//  PhoneManualEntryView.swift
//  WatchList
//
//  The manual form, opened from the iPhone Search tab: from its start options,
//  under a result list, or in place of results when TMDb has nothing. It opens
//  with whatever was already typed, so the title rarely needs retyping.
//
//  Same fields as the Manual mode of the iPad Add sheet (AddEntryView.swift),
//  which is left as it is.
//

import SwiftUI
import SwiftData
import PhotosUI

struct PhoneManualEntryView: View {
	@Environment(\.modelContext) private var ctx
	@Environment(\.dismiss) private var dismiss

	/// Told the saved title, so the search screen can confirm it landed.
	private let onAdded: (String) -> Void

	@State private var kind: MediaKind = .show
	@State private var title: String
	@State private var genre = ""
	@State private var year = ""
	@State private var synopsis = ""
	@State private var imdb: String
	@State private var status: WatchStatus = .toWatch
	@State private var rating: Rating? = nil
	@State private var notes = ""
	@State private var posterItem: PhotosPickerItem?
	@State private var posterData: Data?

	init(title: String = "", imdb: String = "", onAdded: @escaping (String) -> Void = { _ in }) {
		_title = State(initialValue: title)
		_imdb = State(initialValue: imdb)
		self.onAdded = onAdded
	}

	private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

	var body: some View {
		NavigationStack {
			ZStack {
				GlassBackground()
				ScrollView {
					form.padding(18)
				}
				.scrollDismissesKeyboard(.interactively)
			}
			.navigationTitle("Add Manually")
			.navigationBarTitleDisplayMode(.inline)
			.toolbarBackground(.hidden, for: .navigationBar)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
			}
		}
	}

	private var form: some View {
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
		onAdded(trimmedTitle)
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
