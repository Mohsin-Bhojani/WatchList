//
//  Components.swift
//  WatchList
//
//  Shared Liquid Glass building blocks: stat chips, poster cards, list rows,
//  spec sections.
//

import SwiftUI

// MARK: - Stat chip

struct StatChip: View {
	let label: String
	let value: String
	let systemImage: String
	let tint: Color

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 5) {
				Image(systemName: systemImage).font(.system(size: 12, weight: .bold))
				Text(label).font(.system(size: 12, weight: .semibold, design: .rounded))
			}
			.foregroundStyle(tint)
			Text(value)
				.font(.system(size: 26, weight: .bold, design: .serif))
				.foregroundStyle(.primary)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.vertical, 14)
		.padding(.horizontal, 16)
		.glass(cornerRadius: 18)
	}
}

// MARK: - Poster grid card

struct PosterCard: View {
	let title: String
	let subtitle: String
	let posterURL: String
	let status: WatchStatus
	var rating: Rating? = nil
	var placeholder: String = "film"

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			PosterImage(urlString: posterURL, systemPlaceholder: placeholder)
				.aspectRatio(2.0/3.0, contentMode: .fit)
				.clipShape(RoundedRectangle(cornerRadius: Glass.corner, style: .continuous))
				.overlay(alignment: .topTrailing) {
					StatusBadge(status: status, compact: true)
						.padding(8)
				}
				.overlay(alignment: .topLeading) {
					if let rating {
						RatingBadge(rating: rating, compact: true)
							.padding(8)
					}
				}

			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(.system(size: 15, weight: .bold, design: .serif))
					.foregroundStyle(.primary)
					.lineLimit(1)
				Text(subtitle)
					.font(.system(size: 12, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(.horizontal, 10)
			.padding(.top, 9)
			.padding(.bottom, 11)
		}
		.glass(cornerRadius: Glass.corner)
	}
}

// MARK: - Generic glass list row (seasons, episodes, search)

struct GlassRow: View {
	let title: String
	let subtitle: String
	var thumbURL: String = ""
	var thumbPlaceholder: String = "film"
	var status: WatchStatus? = nil
	var rating: Rating? = nil
	var episodeTier: EpisodeTier? = nil
	var leadingNumber: Int? = nil
	var showsChevron: Bool = true

	var body: some View {
		HStack(spacing: 12) {
			if let n = leadingNumber {
				Text("\(n)")
					.font(.system(size: 17, weight: .bold, design: .rounded))
					.foregroundStyle(Glass.accent)
					.frame(width: 34, height: 34)
					.background(Glass.accent.opacity(0.14), in: Circle())
			} else if !thumbURL.isEmpty {
				PosterImage(urlString: thumbURL, systemPlaceholder: thumbPlaceholder)
					.frame(width: 54, height: 76)
					.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
			}

			VStack(alignment: .leading, spacing: 3) {
				Text(title)
					.font(.system(size: 16, weight: .semibold, design: .rounded))
					.foregroundStyle(.primary)
					.lineLimit(2)
				if !subtitle.isEmpty {
					Text(subtitle)
						.font(.system(size: 13, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
						.lineLimit(2)
				}
			}
			Spacer(minLength: 6)

			if let episodeTier { EpisodeTierBadge(tier: episodeTier, compact: true) }
			if let rating { RatingBadge(rating: rating, compact: true) }
			if let status { StatusBadge(status: status, compact: true) }
			if showsChevron {
				Image(systemName: "chevron.right")
					.font(.system(size: 13, weight: .bold))
					.foregroundStyle(.tertiary)
			}
		}
		.padding(.vertical, 11)
		.padding(.horizontal, 14)
		.glass(cornerRadius: 18)
	}
}

// MARK: - Person avatar

/// A circular headshot, falling back to the person's initials on the muted
/// paper tone when TMDb has no profile image.
struct PersonAvatar: View {
	let urlString: String
	let name: String

	private var initials: String {
		let words = name.split(separator: " ").prefix(2)
		return words.compactMap { $0.first.map(String.init) }.joined().uppercased()
	}

	var body: some View {
		Group {
			if urlString.isEmpty {
				ZStack {
					Rectangle().fill(Glass.hairline.opacity(0.06))
					Text(initials)
						.font(.system(size: 15, weight: .semibold, design: .serif))
						.foregroundStyle(Glass.accent3)
				}
			} else {
				PosterImage(urlString: urlString, systemPlaceholder: "person.fill")
			}
		}
		.clipShape(Circle())
	}
}

// MARK: - Images tab

/// One tile in an Images grid. Posters, stills and backdrops fill their tile;
/// logos are transparent artwork of unpredictable shape, so they're fitted
/// inside one on a muted chip rather than cropped to it.
///
/// The language code sits in the corner, because a gallery holds every language
/// TMDb has and an untagged tile is the textless one you usually want.
struct ImageTile: View {
	let entry: ImageEntry

	var body: some View {
		Group {
			if entry.kind.fitsInsideTile {
				fitted
			} else {
				PosterImage(urlString: entry.thumbURL, systemPlaceholder: entry.kind.systemImage)
			}
		}
		.aspectRatio(CGFloat(entry.kind.nominalAspect), contentMode: .fit)
		.clipShape(RoundedRectangle(cornerRadius: Glass.cornerSmall, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: Glass.cornerSmall, style: .continuous)
			.strokeBorder(Glass.hairline.opacity(0.16), lineWidth: 1))
		.overlay(alignment: .bottomTrailing) {
			if let language = entry.language {
				Text(language.uppercased())
					.font(.system(size: 9, weight: .bold, design: .rounded))
					.foregroundStyle(.white)
					.padding(.horizontal, 5)
					.padding(.vertical, 2)
					.background(Capsule().fill(.black.opacity(0.45)))
					.padding(5)
			}
		}
		.accessibilityLabel("\(entry.kind.singular), \(entry.languageLabel)")
	}

	private var fitted: some View {
		ZStack {
			Rectangle().fill(Glass.hairline.opacity(0.06))
			CachedAsyncImage(url: URL(string: entry.thumbURL)) { phase in
				switch phase {
				case .success(let image):
					image.resizable().scaledToFit().padding(10)
				case .empty:
					ProgressView()
				default:
					Image(systemName: entry.kind.systemImage)
						.font(.system(size: 20, weight: .light))
						.foregroundStyle(Glass.accent3)
				}
			}
		}
	}
}

/// Full-screen viewer for an Images tab: the tapped image at full size, with
/// the rest of the gallery a swipe away and its details underneath.
struct ImageViewer: View {
	let entries: [ImageEntry]
	let start: ImageEntry

	@Environment(\.dismiss) private var dismiss
	@State private var selection = ""

	private var current: ImageEntry { entries.first { $0.id == selection } ?? start }

	var body: some View {
		ZStack {
			Color.black.ignoresSafeArea()

			TabView(selection: $selection) {
				ForEach(entries) { entry in
					page(entry).tag(entry.id)
				}
			}
			.tabViewStyle(.page(indexDisplayMode: .never))

			VStack(spacing: 0) {
				topBar
				Spacer()
				caption
			}
		}
		// Set here rather than in the initialiser so `selection` is a plain
		// @State the TabView can drive afterwards.
		.onAppear { selection = start.id }
		.statusBarHidden()
	}

	private func page(_ entry: ImageEntry) -> some View {
		CachedAsyncImage(url: URL(string: entry.fullURL)) { phase in
			switch phase {
			case .success(let image):
				image.resizable().scaledToFit()
			case .empty:
				ProgressView().tint(.white)
			default:
				VStack(spacing: 10) {
					Image(systemName: "exclamationmark.triangle")
						.font(.system(size: 30, weight: .light))
					Text("Couldn't load this image.")
						.font(.system(size: 14, weight: .medium, design: .rounded))
				}
				.foregroundStyle(.white.opacity(0.7))
			}
		}
		.padding(.horizontal, 10)
		.padding(.vertical, 60)
	}

	private var topBar: some View {
		HStack {
			circleButton("xmark", label: "Close") { dismiss() }
			Spacer()
			if entries.count > 1, let index = entries.firstIndex(of: current) {
				Text("\(index + 1) of \(entries.count)")
					.font(.system(size: 13, weight: .semibold, design: .rounded))
					.foregroundStyle(.white.opacity(0.85))
			}
			Spacer()
			if let url = URL(string: current.fullURL) {
				ShareLink(item: url) {
					Image(systemName: "square.and.arrow.up")
						.font(.system(size: 15, weight: .bold))
						.foregroundStyle(.white)
						.frame(width: 34, height: 34)
						.background(Circle().fill(.white.opacity(0.16)))
				}
			} else {
				Color.clear.frame(width: 34, height: 34)
			}
		}
		.padding(.horizontal, 16)
		.padding(.top, 10)
	}

	private var caption: some View {
		Text(captionParts.joined(separator: "  ·  "))
			.font(.system(size: 12, weight: .medium, design: .rounded))
			.foregroundStyle(.white.opacity(0.75))
			.padding(.horizontal, 16)
			.padding(.bottom, 22)
	}

	private var captionParts: [String] {
		var parts = [current.kind.singular]
		if !current.dimensions.isEmpty { parts.append(current.dimensions) }
		parts.append(current.languageLabel)
		if current.voteAverage > 0 { parts.append(String(format: "★ %.1f", current.voteAverage)) }
		return parts
	}

	private func circleButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Image(systemName: systemImage)
				.font(.system(size: 15, weight: .bold))
				.foregroundStyle(.white)
				.frame(width: 34, height: 34)
				.background(Circle().fill(.white.opacity(0.16)))
		}
		.accessibilityLabel(label)
	}
}

// MARK: - Status picker (segmented glass)

struct StatusPicker: View {
	@Binding var status: WatchStatus
	var body: some View {
		HStack(spacing: 8) {
			ForEach(WatchStatus.allCases) { s in
				let selected = status == s
				Button {
					Haptics.selection()
					withAnimation(Glass.pop) { status = s }
				} label: {
					HStack(spacing: 5) {
						Image(systemName: s.systemImage).font(.system(size: 12, weight: .bold))
						Text(s.rawValue).font(.system(size: 13, weight: .semibold, design: .rounded))
					}
					.foregroundStyle(selected ? .white : Color.primary)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 11)
					.background {
						if selected {
							Capsule().fill(Glass.tint(s))
						} else {
							Capsule().fill(.ultraThinMaterial)
						}
					}
				}
				.buttonStyle(.pressable)
			}
		}
	}
}

// MARK: - Rating picker (2×2 glass grid, clearable)

struct RatingPicker: View {
	@Binding var rating: Rating?
	@Environment(\.horizontalSizeClass) private var horizontalSizeClass

	private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			if horizontalSizeClass == .regular {
				// iPad: a 2×2 grid fits the narrow two-column side column.
				LazyVGrid(columns: columns, spacing: 8) {
					ForEach(Rating.allCases) { chip($0, expands: true) }
				}
			} else {
				// iPhone: a single horizontal scrollable row.
				ScrollView(.horizontal, showsIndicators: false) {
					HStack(spacing: 8) {
						ForEach(Rating.allCases) { chip($0, expands: false) }
					}
					.padding(.vertical, 2)
				}
			}
			if rating != nil {
				Text("Tap the selected rating again to clear it.")
					.font(.system(size: 11, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
			}
		}
	}

	private func chip(_ r: Rating, expands: Bool) -> some View {
		let selected = rating == r
		return Button {
			Haptics.selection()
			withAnimation(Glass.pop) { rating = selected ? nil : r }
		} label: {
			HStack(spacing: 6) {
				Image(systemName: r.systemImage).font(.system(size: 12, weight: .bold))
				Text(r.rawValue).font(.system(size: 13, weight: .semibold, design: .rounded))
			}
			.foregroundStyle(selected ? .white : Color.primary)
			.frame(maxWidth: expands ? .infinity : nil)
			.padding(.horizontal, expands ? 0 : 16)
			.padding(.vertical, 11)
			.background {
				if selected {
					Capsule().fill(Glass.tint(r))
				} else {
					Capsule().fill(.ultraThinMaterial)
				}
			}
		}
		.buttonStyle(.pressable)
	}
}
