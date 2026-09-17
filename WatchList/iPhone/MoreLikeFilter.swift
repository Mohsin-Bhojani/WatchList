//
//  MoreLikeFilter.swift
//  WatchList
//
//  More like, in Discover's filter: the one library title suggestions come
//  from, for "Because you rated Severance Perfection" and nothing else.
//    - MoreLikeFilter: the heading with See all, a row of posters — Any title
//      first, then the titles Discover can suggest from, best rated first —
//      and a line saying what the pick does. One title at a time; tapping the
//      picked one goes back to Any title.
//    - MoreLikePicker: See all — every one of those titles under its verdict,
//      then Added, searchable
//

import SwiftUI

struct MoreLikeFilter: View {
	/// The titles Discover can suggest from, in seed order.
	let seeds: [WatchedTitle]
	@Binding var picked: UUID?

	var body: some View {
		let seed = seeds.first { $0.id == picked }
		VStack(alignment: .leading, spacing: 4) {
			HStack(alignment: .firstTextBaseline, spacing: 8) {
				FilterHeading("More like", detail: seed?.title)
					.lineLimit(1)
				Spacer(minLength: 8)
				NavigationLink { MoreLikePicker(seeds: seeds, picked: $picked) } label: {
					Text("See all")
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(Glass.accent)
				}
			}
			ScrollViewReader { proxy in
				ScrollView(.horizontal) {
					LazyHStack(alignment: .top, spacing: 12) {
						anyTile
						ForEach(seeds) { tile($0) }
					}
					// Room for the ring and tick, which stand out past the poster.
					.padding(.vertical, 8)
				}
				.scrollIndicators(.hidden)
				.contentMargins(.horizontal, 20, for: .scrollContent)
				.padding(.horizontal, -20)
				// A title picked from See all, further along, is brought into view.
				.onAppear { if let picked { proxy.scrollTo(picked, anchor: .center) } }
				.onChange(of: picked) { _, id in
					guard let id else { return }
					withAnimation(Glass.smooth) { proxy.scrollTo(id, anchor: .center) }
				}
			}
			Text(DiscoverFeed.moreLikeCaption(for: seed))
				.font(.system(size: 13, weight: .medium))
				.foregroundStyle(.secondary)
				.fixedSize(horizontal: false, vertical: true)
				.animation(nil, value: picked)
		}
	}

	private func pick(_ id: UUID?) {
		Haptics.selection()
		withAnimation(Glass.smooth) { picked = id }
	}

	private var anyTile: some View {
		let chosen = picked == nil
		return Button { pick(nil) } label: {
			VStack(alignment: .leading, spacing: 6) {
				RoundedRectangle(cornerRadius: 10, style: .continuous)
					.fill(Color.primary.opacity(0.04))
					.strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
					.frame(width: 72, height: 108)
					.overlay {
						Image(systemName: "sparkles")
							.font(.system(size: 24, weight: .medium))
							.foregroundStyle(Glass.accent)
					}
					.overlay { SeedRing(chosen: chosen) }
				caption("Any title", "Whole library", rating: nil)
			}
			.frame(width: 72, alignment: .leading)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("Any title, your whole library")
		.accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
	}

	private func tile(_ item: WatchedTitle) -> some View {
		let chosen = item.id == picked
		return Button { pick(chosen ? nil : item.id) } label: {
			VStack(alignment: .leading, spacing: 6) {
				PosterImage(urlString: item.posterURL, systemPlaceholder: item.placeholder)
					.frame(width: 72, height: 108)
					.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
					.overlay { SeedRing(chosen: chosen) }
				caption(item.title, item.rating?.rawValue ?? "Added", rating: item.rating)
			}
			.frame(width: 72, alignment: .leading)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.id(item.id)
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("\(item.title), \(item.rating.map { "rated \($0.rawValue)" } ?? "added")")
		.accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
	}

	/// A tile's name, and its verdict with the verdict's dot or "Added".
	private func caption(_ title: String, _ detail: String, rating: Rating?) -> some View {
		VStack(alignment: .leading, spacing: 1) {
			Text(title)
				.font(.system(size: 12, weight: .semibold))
				.foregroundStyle(Color.primary)
				.lineLimit(1)
			HStack(spacing: 4) {
				if let rating {
					Circle()
						.fill(Glass.tint(rating))
						.frame(width: 6, height: 6)
				}
				Text(detail)
					.lineLimit(1)
			}
			.font(.system(size: 11, weight: .medium))
			.foregroundStyle(.secondary)
		}
	}
}

/// The picked tile's mark: an accent ring just outside the poster, and a tick
/// on its corner.
private struct SeedRing: View {
	let chosen: Bool

	var body: some View {
		if chosen {
			RoundedRectangle(cornerRadius: 14, style: .continuous)
				.strokeBorder(Glass.accent, lineWidth: 2.5)
				.padding(-5)
				.overlay(alignment: .topTrailing) {
					Image(systemName: "checkmark")
						.font(.system(size: 10, weight: .heavy))
						.foregroundStyle(.white)
						.frame(width: 22, height: 22)
						.background(Circle().fill(Glass.accent))
						.offset(x: 9, y: -9)
				}
				.transition(.opacity)
		}
	}
}

// MARK: - See all

struct MoreLikePicker: View {
	let seeds: [WatchedTitle]
	@Binding var picked: UUID?

	@State private var search = ""

	var body: some View {
		let groups = DiscoverFeed.seedGroups(seeds, matching: search)
		List {
			if search.trimmingCharacters(in: .whitespaces).isEmpty {
				Section {
					anyRow
				}
			} else if groups.isEmpty {
				Text("No titles match \u{201C}\(search)\u{201D}.")
					.font(.system(size: 14, weight: .medium))
					.foregroundStyle(.secondary)
			}
			ForEach(groups) { group in
				Section {
					ForEach(group.titles) { row($0) }
				} header: {
					HStack(spacing: 6) {
						if let rating = group.rating {
							Circle()
								.fill(Glass.tint(rating))
								.frame(width: 7, height: 7)
						}
						Text(group.name)
					}
					.textCase(nil)
				} footer: {
					if group.id == groups.last?.id {
						Text("Titles rated Skip, and ones added by hand, can\u{2019}t be suggested from.")
					}
				}
			}
		}
		.searchable(text: $search, prompt: "Search your library")
		.navigationTitle("More like")
		.navigationBarTitleDisplayMode(.inline)
	}

	private func select(_ id: UUID?) {
		Haptics.selection()
		picked = id
	}

	private var anyRow: some View {
		Button { select(nil) } label: {
			HStack(spacing: 12) {
				RoundedRectangle(cornerRadius: 6, style: .continuous)
					.strokeBorder(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
					.frame(width: 36, height: 54)
					.overlay {
						Image(systemName: "sparkles")
							.font(.system(size: 15, weight: .medium))
							.foregroundStyle(Glass.accent)
					}
				VStack(alignment: .leading, spacing: 2) {
					Text("Any title")
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(Color.primary)
					Text("Your whole library, best rated first")
						.font(.system(size: 12, weight: .medium))
						.foregroundStyle(.secondary)
				}
				Spacer(minLength: 8)
				tick(picked == nil)
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityAddTraits(picked == nil ? .isSelected : [])
	}

	private func row(_ item: WatchedTitle) -> some View {
		let chosen = item.id == picked
		return Button { select(item.id) } label: {
			HStack(spacing: 12) {
				PosterImage(urlString: item.posterURL, systemPlaceholder: item.placeholder)
					.frame(width: 36, height: 54)
					.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
				VStack(alignment: .leading, spacing: 2) {
					Text(item.title)
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(Color.primary)
						.lineLimit(2)
					Text(CollectionsFeed.kindLine(item))
						.font(.system(size: 12, weight: .medium))
						.foregroundStyle(.secondary)
				}
				Spacer(minLength: 8)
				tick(chosen)
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityAddTraits(chosen ? .isSelected : [])
	}

	private func tick(_ chosen: Bool) -> some View {
		Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
			.font(.system(size: 22, weight: .semibold))
			.foregroundStyle(chosen ? Glass.accent : Color.secondary)
			.accessibilityHidden(true)
	}
}
