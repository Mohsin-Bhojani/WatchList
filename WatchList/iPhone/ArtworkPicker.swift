//
//  ArtworkPicker.swift
//  WatchList
//
//  Choosing a title's artwork from TMDb's gallery. Every title is drawn from
//  two pictures: a portrait poster (grids, cards, the tab bar's Collections)
//  and a landscape one (Home's hero, the page headers, the watch). The Artwork
//  sheet shows both as they stand, then the gallery to pick from:
//    - a show or a film takes both
//    - a season takes a poster; an episode takes a landscape still
//  A pick is written to the title's own posterURL / backdropURL / stillURL, so
//  every screen that draws it follows — nothing new is stored on the models.
//  ArtworkChoice only remembers that the picture was chosen by hand, so Home's
//  hero keeps it instead of going back to TMDb's textless pick.
//

import SwiftUI

/// Which of a title's two pictures a gallery image is for.
enum ArtworkSlot: String, CaseIterable {
	case poster, landscape

	var title: String { self == .poster ? "Poster" : "Landscape" }

	/// What it's called where there's room to say it.
	var action: String { self == .poster ? "Use as Poster" : "Use as Landscape" }

	var systemImage: String { self == .poster ? "rectangle.portrait" : "rectangle" }

	/// Portrait or 16:9, for the tiles that show what's chosen.
	var aspect: CGFloat { self == .poster ? 2.0 / 3.0 : 16.0 / 9.0 }

	/// The gallery kinds that suit it: posters for the portrait slot, backdrops
	/// and stills for the landscape one. Logos suit neither.
	func fits(_ kind: ImageEntry.Kind) -> Bool {
		switch kind {
		case .poster:           return self == .poster
		case .backdrop, .still: return self == .landscape
		case .logo:             return false
		}
	}

	/// A picked image at the size that slot is saved at, matching an import.
	func url(for entry: ImageEntry) -> String {
		self == .poster ? TMDbConfig.poster(entry.id) : TMDbConfig.backdrop(entry.id)
	}
}

/// The title the Artwork sheet is picking for: what it shows now, and what to
/// do with a pick. A slot with no setter isn't offered.
struct ArtworkTarget {
	let id: UUID
	/// What's drawn now, by slot, for the tiles at the top of the sheet.
	var current: [ArtworkSlot: String] = [:]
	/// Applies a pick. Slots without one — a season has no landscape — are left out.
	var apply: [ArtworkSlot: (String) -> Void] = [:]

	var slots: [ArtworkSlot] { ArtworkSlot.allCases.filter { apply[$0] != nil } }

	func choose(_ entry: ImageEntry, as slot: ArtworkSlot) {
		guard let apply = apply[slot] else { return }
		apply(slot.url(for: entry))
		ArtworkChoice.remember(slot, for: id)
	}
}

/// Which titles have artwork chosen by hand. Kept out of the models — and so
/// out of the store's schema — since it only decides which picture wins where
/// the app would otherwise pick for itself.
enum ArtworkChoice {
	static func chosen(_ slot: ArtworkSlot, for id: UUID) -> Bool {
		ids(slot).contains(id.uuidString)
	}

	static func remember(_ slot: ArtworkSlot, for id: UUID) {
		var chosen = ids(slot)
		chosen.insert(id.uuidString)
		UserDefaults.standard.set(Array(chosen), forKey: key(slot))
	}

	static func forget(_ slot: ArtworkSlot, for id: UUID) {
		var chosen = ids(slot)
		chosen.remove(id.uuidString)
		UserDefaults.standard.set(Array(chosen), forKey: key(slot))
	}

	private static func key(_ slot: ArtworkSlot) -> String { "artworkChosen-\(slot.rawValue)" }

	private static func ids(_ slot: ArtworkSlot) -> Set<String> {
		Set(UserDefaults.standard.stringArray(forKey: key(slot)) ?? [])
	}
}

// MARK: - The sheet

/// The Artwork sheet the title pages open from their menus: what the title is
/// drawn from now, and TMDb's gallery to choose from.
struct ArtworkSheet: View {
	let source: ImageSource
	/// Nil while nothing can be picked — the gallery is then just a gallery.
	var target: ArtworkTarget?

	@Environment(\.dismiss) private var dismiss
	/// What the tiles show — the target's artwork, and a pick as it's made.
	@State private var shown: [ArtworkSlot: String] = [:]
	/// The last pick, named under the tiles for a moment.
	@State private var picked: ArtworkSlot?

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 18) {
					if let target, !target.slots.isEmpty {
						chosen(target)
					}
					ImagesTabView(source: source, picking: target?.slots ?? []) { entry, slot in
						choose(entry, as: slot)
					}
				}
				.padding(18)
			}
			.background(GlassBackground())
			.onAppear { if shown.isEmpty { shown = target?.current ?? [:] } }
			.navigationTitle("Artwork")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") { dismiss() }
				}
			}
		}
	}

	/// What the title is drawn from now: one tile per slot it has.
	private func chosen(_ target: ArtworkTarget) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			SectionLabel(text: "Drawn from", systemImage: "photo.artframe")
			HStack(alignment: .top, spacing: 12) {
				ForEach(target.slots, id: \.self) { slot in
					VStack(spacing: 6) {
						PosterImage(urlString: shown[slot] ?? "", systemPlaceholder: slot.systemImage)
							.aspectRatio(slot.aspect, contentMode: .fit)
							.frame(maxHeight: 120)
							.clipShape(RoundedRectangle(cornerRadius: Glass.cornerSmall, style: .continuous))
							.overlay(RoundedRectangle(cornerRadius: Glass.cornerSmall, style: .continuous)
								.strokeBorder(Glass.hairline.opacity(0.16), lineWidth: 1))
						Text(picked == slot ? "\(slot.title) · Updated" : slot.title)
							.font(.system(size: 12, weight: .semibold, design: .rounded))
							.foregroundStyle(picked == slot ? Glass.accent : .secondary)
							.lineLimit(1)
					}
					.accessibilityElement(children: .combine)
					.accessibilityLabel("\(slot.title), as it is now")
				}
			}
			Text("Hold an image below, or open it, to use it.")
				.font(.system(size: 12, weight: .medium, design: .rounded))
				.foregroundStyle(.tertiary)
		}
	}

	private func choose(_ entry: ImageEntry, as slot: ArtworkSlot) {
		target?.choose(entry, as: slot)
		shown[slot] = slot.url(for: entry)
		Haptics.success()
		withAnimation(Glass.smooth) { picked = slot }
		Task {
			try? await Task.sleep(for: .seconds(2))
			withAnimation(Glass.smooth) { if picked == slot { picked = nil } }
		}
	}
}
