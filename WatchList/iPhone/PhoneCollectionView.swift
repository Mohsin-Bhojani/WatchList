//
//  PhoneCollectionView.swift
//  WatchList
//
//  One collection opened — a by-verdict one or one of your own — after the
//  "Collection opened" design:
//    - the bar, in one row: back, the collection's name and count, a list /
//      carousel switch, and the "…" menu — Share, and in your own collections
//      Add Titles, Rename and Delete (Top 4, which is always there, only Add
//      Titles). An iPad shares its bar with the floating tab bar, so there the
//      name and switch sit at the top of the page.
//    - List: a fan of its first posters, then a row per title — its poster,
//      kind line, stars and verdict — each opening the title's page; in your own
//      collections a long press removes it
//    - Carousel: a poster at a time, its neighbours peeking in, with "4 of 18",
//      the title, its verdict and its synopsis under it; the page takes the
//      poster's colour. Top 4 opens in it; the rest open as a list
//    - Share sends the collection as a plain list
//  Reordering and sharing with friends aren't built, so those menu items are
//  placeholders.
//

import SwiftUI
import SwiftData

/// Which collection a page shows.
enum CollectionSource: Hashable {
	case verdict(Rating)
	case mine(UUID)
}

struct PhoneCollectionView: View {
	let source: CollectionSource

	@Environment(\.dismiss) private var dismiss
	@Query(sort: \Show.dateAdded, order: .reverse) private var shows: [Show]
	@Query(sort: \Film.dateAdded, order: .reverse) private var films: [Film]
	@Query(sort: \TitleCollection.created) private var collections: [TitleCollection]
	@Environment(\.modelContext) private var ctx

	@State private var mode: Mode
	@State private var compactBar = false
	@State private var carouselID: UUID?
	@State private var carouselTone: UIColor?
	@State private var firstPosterTone: UIColor?
	@State private var pageWidth: CGFloat = 402
	@State private var addingTitles = false
	@State private var renaming = false
	@State private var draftName = ""
	@State private var confirmingDelete = false
	@Namespace private var modeThumb

	private enum Mode { case list, carousel }

	/// Keyed on the device, like the app's shell: an iPad's bar has the floating
	/// tab bar in the middle of it.
	private let isPad = UIDevice.current.userInterfaceIdiom == .pad

	init(source: CollectionSource) {
		self.source = source
		// Four posters are made for going through one at a time.
		_mode = State(initialValue: source == .mine(TitleCollection.topFourID) ? .carousel : .list)
	}

	private var mine: TitleCollection? {
		if case .mine(let id) = source { return collections.first { $0.id == id } }
		return nil
	}

	private var isMine: Bool {
		if case .mine = source { return true }
		return false
	}

	private var name: String {
		switch source {
		case .verdict(let rating): return rating.rawValue
		case .mine:                return mine?.name ?? "Collection"
		}
	}

	private var items: [WatchedTitle] {
		switch source {
		case .verdict(let rating):
			return CollectionsFeed.byVerdict(shows: shows, films: films)
				.first { $0.rating == rating }?.items ?? []
		case .mine:
			return CollectionsFeed.items(in: mine, shows: shows, films: films)
		}
	}

	/// A verdict's colour, dimmed until white reads on it; your own collection
	/// takes its first poster's.
	private var baseTone: UIColor {
		switch source {
		case .verdict(let rating): return ArtworkBand.dimmedForWhiteText(UIColor(Glass.tint(rating)))
		case .mine:                return firstPosterTone ?? PageTheme.fallback
		}
	}

	/// The page's colour: the poster in view in the carousel, or else the base.
	private func pageTone(_ items: [WatchedTitle]) -> UIColor {
		mode == .carousel && !items.isEmpty ? (carouselTone ?? baseTone) : baseTone
	}

	/// "2 titles" — "2 of 4" in Top 4 — with "· private" on your own collections.
	private func countLine(_ items: [WatchedTitle]) -> String {
		CollectionsFeed.countLabel(items.count, in: mine) + (isMine ? " · private" : "")
	}

	var body: some View {
		let items = items
		ScrollView {
			VStack(alignment: .leading, spacing: 18) {
				if isPad {
					HStack(alignment: .center, spacing: 12) {
						titleLabel(items, inBar: false)
						Spacer()
						if !items.isEmpty { modeSwitch }
					}
					.padding(.horizontal, 18)
					.padding(.top, 6)
				}
				if mode == .list || items.isEmpty {
					FannedPosters(urls: items.prefix(4).map(\.posterURL), posterWidth: 76)
						.frame(maxWidth: .infinity)
						.padding(.top, 8)
						.transition(.opacity)
				}
				if items.isEmpty {
					emptyState
				} else if mode == .list {
					list(items)
				} else {
					carousel(items)
				}
			}
			.padding(.bottom, 32)
			.frame(maxWidth: TitlePageLayout.maxColumnWidth)
			// The column's own width, which the carousel centres its posters in.
			.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
			.frame(maxWidth: .infinity)
		}
		// The bar turns solid once anything has scrolled up under it.
		.onScrollGeometryChange(for: Bool.self) { geometry in
			geometry.contentOffset.y + geometry.contentInsets.top > 8
		} action: { _, scrolled in
			withAnimation(.easeInOut(duration: 0.2)) { compactBar = scrolled }
		}
		.titlePage(color: pageTone(items), compactBar: compactBar)
		// Kept for the back button's history on a title opened from here, but
		// not shown: the name has its own place, in the row or on the page, and
		// the middle of the bar left free lets that row use the whole width.
		.navigationTitle(name)
		.toolbar(removing: .title)
		.toolbar {
			if !isPad {
				ToolbarItem(placement: .topBarLeading) { titleLabel(items, inBar: true) }
					.sharedBackgroundVisibility(.hidden)
				if !items.isEmpty {
					ToolbarItem(placement: .topBarTrailing) { modeSwitch }
						.sharedBackgroundVisibility(.hidden)
					ToolbarSpacer(.fixed, placement: .topBarTrailing)
				}
			}
			ToolbarItem(placement: .topBarTrailing) { moreMenu(items) }
		}
		.sheet(isPresented: $addingTitles) {
			if case .mine(let id) = source { CollectionTitlePicker(collectionID: id, tone: pageTone(items)) }
		}
		.alert("Rename Collection", isPresented: $renaming) {
			TextField("Name", text: $draftName)
			Button("Cancel", role: .cancel) {}
			Button("Save") {
				mine?.rename(to: draftName)
			}
		}
		.confirmationDialog("Delete \u{201C}\(name)\u{201D}?", isPresented: $confirmingDelete,
		                    titleVisibility: .visible) {
			Button("Delete Collection", role: .destructive, action: deleteCollection)
		} message: {
			Text("Only the collection goes. Its titles stay in your library.")
		}
		.task(id: items.first?.posterURL ?? "") {
			guard isMine, let url = items.first?.posterURL,
			      let sampled = await PageTheme.load(url), !Task.isCancelled else { return }
			withAnimation(.easeOut(duration: 0.4)) { firstPosterTone = sampled }
		}
	}

	// MARK: Bar

	/// The collection's name with its count under it: in the bar beside the back
	/// button on a phone, larger at the top of the page on an iPad.
	@ViewBuilder private func titleLabel(_ items: [WatchedTitle], inBar: Bool) -> some View {
		let label = VStack(alignment: .leading, spacing: inBar ? 1 : 2) {
			Text(name)
				.font(.system(size: inBar ? 17 : 26, weight: .bold))
				.foregroundStyle(.white)
				.lineLimit(inBar ? 1 : 2)
			HStack(spacing: 4) {
				if isMine {
					Image(systemName: "lock.fill")
						.font(.system(size: inBar ? 9 : 10, weight: .semibold))
				}
				Text(countLine(items))
			}
			.font(.system(size: inBar ? 11 : 13, weight: .medium))
			.foregroundStyle(.white.opacity(0.65))
			.lineLimit(1)
		}
		.accessibilityElement(children: .combine)
		.accessibilityAddTraits(.isHeader)

		if inBar {
			// A set width, or the bar squeezes it down to a few letters.
			label.frame(width: barTitleWidth(items), alignment: .leading)
		} else {
			label
		}
	}

	/// What the name and count need in the bar, measured — up to about half the
	/// bar, which is what a side of it gets before the switch has to go.
	private func barTitleWidth(_ items: [WatchedTitle]) -> CGFloat {
		func width(_ text: String, _ font: UIFont) -> CGFloat {
			(text as NSString).size(withAttributes: [.font: font]).width
		}
		let nameWidth = width(name, .systemFont(ofSize: 17, weight: .bold))
		let countWidth = width(countLine(items), .systemFont(ofSize: 11, weight: .medium)) + (isMine ? 13 : 0)
		return min(ceil(max(nameWidth, countWidth)) + 2, max(pageWidth / 2 - 70, 90))
	}

	/// List and carousel together, drawn as a switch, and all of it one button: a
	/// tap anywhere on it swaps to the other.
	private var modeSwitch: some View {
		Button {
			Haptics.selection()
			withAnimation(Glass.smooth) { mode = mode == .list ? .carousel : .list }
		} label: {
			HStack(spacing: 2) {
				modeIcon(.list, systemImage: "list.bullet")
				modeIcon(.carousel, systemImage: "rectangle.split.3x1")
			}
			.padding(4)
			.contentShape(Capsule())
		}
		.buttonStyle(.plain)
		.glassEffect(.regular.tint(.white.opacity(0.06)).interactive(), in: Capsule())
		.accessibilityLabel("View")
		.accessibilityValue(mode == .list ? "List" : "Carousel")
		.accessibilityHint("Switches between list and carousel")
	}

	private func modeIcon(_ option: Mode, systemImage: String) -> some View {
		let selected = mode == option
		return Image(systemName: systemImage)
			.font(.system(size: 14, weight: .semibold))
			.foregroundStyle(selected ? Color.black.opacity(0.8) : .white.opacity(0.8))
			.frame(width: 40, height: 32)
			.background {
				if selected {
					Capsule()
						.fill(.white.opacity(0.9))
						.matchedGeometryEffect(id: "thumb", in: modeThumb)
				}
			}
	}

	private func moreMenu(_ items: [WatchedTitle]) -> some View {
		Menu {
			ShareLink(item: shareText(items)) {
				Label("Share", systemImage: "square.and.arrow.up")
			}
			if isMine {
				Button { addingTitles = true } label: {
					Label("Add Titles", systemImage: "plus")
				}
				// Top 4 stays put: filled and emptied, never renamed or deleted.
				if mine?.isPinned != true {
					Button {
						draftName = name
						renaming = true
					} label: {
						Label("Rename", systemImage: "pencil")
					}
				}
				Section("Placeholder") {
					Button {} label: { Label("Reorder", systemImage: "arrow.up.arrow.down") }
						.disabled(true)
					Button {} label: { Label("Share with friends", systemImage: "person.2") }
						.disabled(true)
				}
				if mine?.isPinned != true {
					Button(role: .destructive) { confirmingDelete = true } label: {
						Label("Delete Collection", systemImage: "trash")
					}
				}
			} else {
				Section("Made from your verdicts") {
					Button {} label: { Label("Share with friends", systemImage: "person.2") }
						.disabled(true)
				}
			}
		} label: {
			Image(systemName: "ellipsis")
		}
		.tint(.white)
		.accessibilityLabel("More")
	}

	// MARK: Empty

	private var emptyState: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text(isMine ? "Nothing in this collection yet." : "Nothing here yet.")
				.font(.system(size: 14, weight: .medium))
				.foregroundStyle(.white.opacity(0.75))
			if isMine {
				Button { addingTitles = true } label: {
					Label("Add titles", systemImage: "plus")
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(.white)
						.padding(.horizontal, 18)
						.frame(height: GlassControl.height)
						.glassEffect(.regular.tint(.white.opacity(0.1)), in: Capsule())
				}
				.buttonStyle(.pressable)
			}
		}
		.padding(.horizontal, 18)
	}

	// MARK: List

	private func list(_ items: [WatchedTitle]) -> some View {
		VStack(spacing: 0) {
			ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
				if index > 0 {
					Rectangle()
						.fill(.white.opacity(0.08))
						.frame(height: 1)
				}
				removable(row(item), item)
			}
		}
		.padding(.horizontal, 18)
	}

	private func row(_ item: WatchedTitle) -> some View {
		NavigationLink { item.destination } label: {
			HStack(spacing: 12) {
				PosterImage(urlString: item.posterURL, systemPlaceholder: item.placeholder)
					.frame(width: 48, height: 72)
					.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
				VStack(alignment: .leading, spacing: 4) {
					Text(item.title)
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(.white)
						.lineLimit(2)
					Text(CollectionsFeed.kindLine(item))
						.font(.system(size: 12, weight: .medium))
						.foregroundStyle(.white.opacity(0.6))
						.lineLimit(1)
					verdictLine(item)
				}
				Spacer(minLength: 0)
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.padding(.vertical, 12)
	}

	/// In your own collections a long press takes a title out.
	@ViewBuilder private func removable<Content: View>(_ content: Content, _ item: WatchedTitle) -> some View {
		if let mine {
			content.contextMenu {
				Button(role: .destructive) {
					withAnimation(Glass.smooth) { mine.set(item.id, included: false) }
				} label: {
					Label("Remove from Collection", systemImage: "minus.circle")
				}
			}
		} else {
			content
		}
	}

	/// The title's stars and verdict — or, not rated yet, its status.
	@ViewBuilder private func verdictLine(_ item: WatchedTitle) -> some View {
		if let rating = item.rating {
			HStack(spacing: 8) {
				if let stars = item.stars {
					StarsLabel(value: stars, size: 9, showsValue: false)
				}
				capsLabel(rating.rawValue, tint: Glass.tint(rating))
			}
		} else {
			capsLabel(item.status.rawValue, tint: Glass.tint(item.status))
		}
	}

	private func capsLabel(_ text: String, tint: Color) -> some View {
		Text(text.uppercased())
			.font(.system(size: 10, weight: .bold))
			.kerning(1)
			.foregroundStyle(.white)
			.padding(.horizontal, 8)
			.padding(.vertical, 3)
			.background(tint.opacity(0.4), in: Capsule())
			.overlay(Capsule().strokeBorder(tint.opacity(0.9), lineWidth: 1))
	}

	// MARK: Carousel

	private func carousel(_ items: [WatchedTitle]) -> some View {
		let current = items.first { $0.id == carouselID } ?? items[0]
		let index = items.firstIndex { $0.id == current.id } ?? 0
		// Two-thirds of the width, capped so a wide screen doesn't push the
		// title under it off the bottom.
		let posterWidth = min(pageWidth * 0.66, 300)
		return VStack(spacing: 16) {
			ScrollView(.horizontal) {
				LazyHStack(spacing: 14) {
					ForEach(items) { item in
						NavigationLink { item.destination } label: {
							PosterImage(urlString: item.posterURL, systemPlaceholder: item.placeholder)
								.frame(width: posterWidth, height: posterWidth * 1.5)
								.clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
								.shadow(color: .black.opacity(0.45), radius: 20, y: 12)
						}
						.buttonStyle(.plain)
						.scrollTransition(axis: .horizontal) { content, phase in
							content
								.scaleEffect(phase.isIdentity ? 1 : 0.86)
								.opacity(phase.isIdentity ? 1 : 0.5)
						}
						.id(item.id)
					}
				}
				.scrollTargetLayout()
			}
			// Centres a poster, with its neighbours peeking in either side.
			.contentMargins(.horizontal, (pageWidth - posterWidth) / 2, for: .scrollContent)
			.scrollTargetBehavior(.viewAligned)
			.scrollIndicators(.hidden)
			.scrollPosition(id: $carouselID)
			.frame(height: posterWidth * 1.5 + 30)

			VStack(spacing: 6) {
				Text("\(index + 1) of \(items.count)")
					.font(.system(size: 13, weight: .semibold))
					.foregroundStyle(.white.opacity(0.6))
				Text(current.title)
					.font(.system(size: 26, weight: .bold))
					.foregroundStyle(.white)
					.multilineTextAlignment(.center)
					.lineLimit(2)
				Text(CollectionsFeed.kindLine(current))
					.font(.system(size: 14, weight: .medium))
					.foregroundStyle(.white.opacity(0.7))
				verdictLine(current)
					.padding(.top, 4)
				if !current.synopsis.isEmpty {
					Text(current.synopsis)
						.font(.system(size: 15))
						.foregroundStyle(.white.opacity(0.8))
						.multilineTextAlignment(.center)
						.lineLimit(6)
						.padding(.top, 10)
				}
			}
			.frame(maxWidth: .infinity)
			.padding(.horizontal, 24)
		}
		.padding(.top, 8)
		.task(id: current.posterURL) {
			guard let sampled = await PageTheme.load(current.posterURL), !Task.isCancelled else { return }
			withAnimation(.easeOut(duration: 0.4)) { carouselTone = sampled }
		}
	}

	/// Leaves the page before deleting, so nothing on screen reads a collection
	/// that's gone.
	private func deleteCollection() {
		guard let mine else { return }
		ctx.delete(mine, afterLeaving: dismiss)
	}

	/// The collection as plain text: its name, then a line per title.
	private func shareText(_ items: [WatchedTitle]) -> String {
		(["\(name) on WatchList"] + items.map { "• \($0.title) (\(CollectionsFeed.kindLine($0)))" })
			.joined(separator: "\n")
	}
}
