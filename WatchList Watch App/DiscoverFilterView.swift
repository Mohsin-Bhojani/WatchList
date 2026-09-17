//
//  DiscoverFilterView.swift
//  WatchList Watch App
//
//  Discover's Filter, as the iPhone has it: TV shows, films or both; any of
//  TMDb's genres for that type; and More like, the one library title
//  suggestions come from. Changes apply as they're made.
//

import SwiftUI

struct DiscoverFilterView: View {
	@Environment(WatchStore.self) private var store

	var body: some View {
		@Bindable var store = store
		NavigationStack {
			List {
				Picker("Type", selection: $store.filter.kind) {
					ForEach(BrowseKind.allCases) { kind in
						Text(kind.label).tag(kind)
					}
				}

				NavigationLink {
					GenrePicker(options: store.genreOptions, picked: $store.filter.genres)
				} label: {
					row("Genres", value: genreSummary)
				}
				.disabled(store.genreOptions.isEmpty)

				if !store.moreLikeOptions.isEmpty {
					NavigationLink {
						MoreLikePicker(seeds: store.moreLikeOptions, picked: $store.filter.seed)
					} label: {
						row("More like", value: store.moreLikeOptions.first { $0.id == store.filter.seed }?.title ?? "Any title")
					}
				}

				if !store.filter.isDefault {
					Button("Reset Filter", role: .destructive) {
						store.filter = DiscoverFilter()
					}
				}
			}
			.navigationTitle("Filter")
		}
		.task { await store.loader.loadGenres() }
		// A new type keeps only the genres and More like title it still has.
		.onChange(of: store.filter.kind) {
			let options = store.genreOptions
			if !options.isEmpty { store.filter.genres.formIntersection(options) }
			if let seed = store.filter.seed, !store.moreLikeOptions.contains(where: { $0.id == seed }) {
				store.filter.seed = nil
			}
		}
	}

	private var genreSummary: String {
		switch store.filter.genres.count {
		case 0:    return "Any"
		case 1:    return store.filter.genres.first ?? ""
		default:   return "\(store.filter.genres.count) genres"
		}
	}

	private func row(_ title: String, value: String) -> some View {
		VStack(alignment: .leading, spacing: 1) {
			Text(title)
			Text(value)
				.font(.footnote)
				.foregroundStyle(.secondary)
				.lineLimit(1)
		}
	}
}

/// Any number of genres; none picked is all of them.
private struct GenrePicker: View {
	let options: [String]
	@Binding var picked: Set<String>

	var body: some View {
		List(options, id: \.self) { genre in
			let on = picked.contains(genre)
			Button {
				if on { picked.remove(genre) } else { picked.insert(genre) }
			} label: {
				HStack {
					Text(genre)
					Spacer(minLength: 4)
					if on {
						Image(systemName: "checkmark")
							.foregroundStyle(.tint)
					}
				}
			}
			.accessibilityAddTraits(on ? .isSelected : [])
		}
		.navigationTitle("Genres")
	}
}

/// One library title for suggestions to come from, or any.
private struct MoreLikePicker: View {
	let seeds: [DiscoverSeed]
	@Binding var picked: UUID?
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		List {
			row("Any title", id: nil)
			ForEach(seeds) { seed in
				row(seed.title, id: seed.id)
			}
		}
		.navigationTitle("More like")
	}

	private func row(_ title: String, id: UUID?) -> some View {
		Button {
			picked = id
			dismiss()
		} label: {
			HStack {
				Text(title)
					.lineLimit(2)
				Spacer(minLength: 4)
				if picked == id {
					Image(systemName: "checkmark")
						.foregroundStyle(.tint)
				}
			}
		}
		.accessibilityAddTraits(picked == id ? .isSelected : [])
	}
}
