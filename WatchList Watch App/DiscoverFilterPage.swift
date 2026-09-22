//
//  DiscoverFilterPage.swift
//  WatchList Watch App
//
//  Discover's Filter, a Crown turn below Discover, as the iPhone has it: TV
//  shows, films or both; any of TMDb's genres for that type; and More like, the
//  one library title suggestions come from. Changes apply as they're made,
//  and Reset shows while any are. It all fits on the one screen, so the Crown
//  only ever turns the page here — Genres and More like push their lists, and
//  it scrolls those.
//

import SwiftUI

/// Filter's lists, pushed onto the app's one NavigationStack.
enum FilterRoute: Hashable {
	case genres, moreLike
}

struct DiscoverFilterPage: View {
	@Environment(WatchStore.self) private var store
	/// Discover's colour, which this page carries on deepening from.
	let tone: Color?

	var body: some View {
		@Bindable var store = store
		// Just the filters, should a watch ever be too small for the heading too.
		ViewThatFits(in: .vertical) {
			VStack(alignment: .leading, spacing: 5) {
				header
				filters
			}
			filters
		}
		.padding(.horizontal, 8)
		.padding(.bottom, 2)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.ignoresSafeArea(edges: .bottom)
		.background { backdrop.ignoresSafeArea() }
		.navigationDestination(for: FilterRoute.self) { route in
			switch route {
			case .genres:   GenrePicker(options: store.genreOptions, picked: $store.filter.genres)
			case .moreLike: MoreLikePicker(seeds: store.moreLikeOptions, picked: $store.filter.seed)
			}
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

	/// "Filter", and Reset while anything's set.
	private var header: some View {
		HStack(spacing: 4) {
			Text("Filter")
				.font(.system(size: 18, weight: .bold))
				.foregroundStyle(.white)
				.accessibilityAddTraits(.isHeader)
			Spacer(minLength: 4)
			if !store.filter.isDefault {
				Button {
					Haptics.click()
					withAnimation(.smooth) { store.filter = DiscoverFilter() }
				} label: {
					Text("Reset")
						.font(.system(size: 13, weight: .semibold))
						.foregroundStyle(.white)
						.padding(.horizontal, 11)
						.padding(.vertical, 4)
						.glassEffect(.regular.interactive(), in: Capsule())
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Reset Filter")
				.transition(.opacity)
			}
		}
		// The same with Reset or without, so it can't tip the page over.
		.frame(height: 24)
	}

	/// The type, and Genres and More like to open.
	private var filters: some View {
		@Bindable var store = store
		return VStack(alignment: .leading, spacing: 5) {
			KindSegments(selection: $store.filter.kind)

			NavigationLink(value: FilterRoute.genres) {
				FilterRow(title: "Genres", value: genreSummary)
			}
			.buttonStyle(.plain)
			.disabled(store.genreOptions.isEmpty)

			if !store.moreLikeOptions.isEmpty {
				NavigationLink(value: FilterRoute.moreLike) {
					FilterRow(title: "More like", value: seedTitle ?? "Any title")
				}
				.buttonStyle(.plain)
			}
		}
	}

	/// Discover's gradient carried on down to black.
	private var backdrop: some View {
		LinearGradient(colors: [tone.map { Artwork.deeper($0) } ?? .black, .black],
		               startPoint: .top, endPoint: .bottom)
	}

	private var genreSummary: String {
		switch store.filter.genres.count {
		case 0:    return "Any"
		case 1:    return store.filter.genres.first ?? ""
		default:   return "\(store.filter.genres.count) genres"
		}
	}

	private var seedTitle: String? {
		store.moreLikeOptions.first { $0.id == store.filter.seed }?.title
	}
}

/// TV shows, films or both, as the iPhone's segmented control has them.
private struct KindSegments: View {
	@Binding var selection: BrowseKind

	@Namespace private var thumb

	var body: some View {
		HStack(spacing: 0) {
			ForEach(BrowseKind.allCases) { kind in
				segment(kind)
			}
		}
		.padding(3)
		.background(.white.opacity(0.12), in: Capsule())
	}

	private func segment(_ kind: BrowseKind) -> some View {
		let chosen = selection == kind
		return Button {
			guard !chosen else { return }
			Haptics.click()
			withAnimation(.snappy(duration: 0.25)) { selection = kind }
		} label: {
			// "TV" for the iPhone's "TV Shows", which a third of a watch can't fit.
			Text(kind == .shows ? "TV" : kind.label)
				.font(.system(size: 13, weight: chosen ? .semibold : .medium))
				.foregroundStyle(.white.opacity(chosen ? 1 : 0.75))
				.lineLimit(1)
				.padding(.horizontal, 3)
				.frame(maxWidth: .infinity)
				.frame(height: 26)
				.background {
					if chosen {
						Capsule()
							.fill(.white.opacity(0.28))
							.matchedGeometryEffect(id: "thumb", in: thumb)
					}
				}
				.contentShape(Capsule())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(kind.label)
		.accessibilityAddTraits(chosen ? .isSelected : [])
	}
}

/// A filter that opens its list: its name, what's picked, and a chevron, on glass.
private struct FilterRow: View {
	let title: String
	let value: String

	@Environment(\.isEnabled) private var isEnabled

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
		HStack(spacing: 6) {
			VStack(alignment: .leading, spacing: 1) {
				Text(title)
					.font(.system(size: 15, weight: .semibold))
					.foregroundStyle(.white)
				Text(value)
					.font(.system(size: 13))
					.foregroundStyle(.white.opacity(0.65))
					.lineLimit(1)
			}
			Spacer(minLength: 4)
			Image(systemName: "chevron.forward")
				.font(.system(size: 12, weight: .semibold))
				.foregroundStyle(.white.opacity(0.5))
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 5)
		.frame(maxWidth: .infinity, alignment: .leading)
		.glassEffect(.regular.interactive(), in: shape)
		.contentShape(shape)
		.opacity(isEnabled ? 1 : 0.5)
		.accessibilityElement(children: .combine)
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
