//
//  TitlePageKit.swift
//  WatchList
//
//  The pieces the iPhone show, season and episode pages share, after the
//  "Show view" design: a colour taken from the artwork, the page's gradient and
//  bar, the status switch, verdict chips, section headings, the synopsis card
//  (the trailer card is TrailerCard.swift), the cast row and the compact bar's title — and the actions
//  their menus share: the status and rating sections, sharing, the artwork
//  sheet, details rows and removing a record.
//

import SwiftUI
import SwiftData

// MARK: - Colour

/// Colours sampled from artwork, by URL, so going back into a page doesn't
/// flash the fallback before its own colour.
@MainActor
enum PageTheme {
	/// The design's slate, until the artwork is in or when there is none.
	static let fallback = UIColor(resource: .pageFallback)

	private static var sampled: [String: UIColor] = [:]

	static func cached(_ url: String) -> UIColor? { sampled[url] }

	/// A title page's ground: its colour running down to a deeper shade.
	static func backdrop(_ color: UIColor?) -> LinearGradient {
		let base = color ?? fallback
		return LinearGradient(colors: [Color(uiColor: base), Color(uiColor: ArtworkBand.deeper(base))],
		                      startPoint: .top, endPoint: .bottom)
	}

	static func load(_ url: String) async -> UIColor? {
		if let hit = sampled[url] { return hit }
		guard !url.isEmpty, let link = URL(string: url),
		      let image = await ImageCache.shared.image(for: link),
		      let color = await ArtworkBand.sampledThemeColor(for: image) else { return nil }
		sampled[url] = color
		return color
	}
}

enum TitlePageLayout {
	/// The widest a title page's content runs in one column: all of an iPhone,
	/// and a readable column centred on an iPad upright. Wider, TitlePageColumns
	/// makes two.
	static let maxColumnWidth: CGFloat = 720
}

/// A title page's content. One column on a phone, and centred in a readable
/// width on an iPad upright; on an iPad wide enough — held sideways, say — two:
/// the title's own part (the poster, status and your verdict) on the leading
/// side and the rest beside it. `lead` then `rest` is the one column's order.
struct TitlePageColumns<Lead: View, Rest: View>: View {
	@ViewBuilder let lead: Lead
	@ViewBuilder let rest: Rest

	@State private var width: CGFloat = 0

	/// Keyed on the device, like the app's shell.
	private static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

	var body: some View {
		Group {
			if Self.isPad && width >= 960 {
				HStack(alignment: .top, spacing: 28) {
					VStack(spacing: 16) { lead }
						.frame(width: min(width * 0.38, 420))
					VStack(spacing: 16) { rest }
						.frame(maxWidth: .infinity)
				}
				.padding(.horizontal, 28)
				.padding(.bottom, 32)
				.frame(maxWidth: 1240)
				.frame(maxWidth: .infinity)
			} else {
				VStack(spacing: 16) {
					lead
					rest
				}
				.padding(.horizontal, 18)
				.padding(.bottom, 32)
				.readableColumn()
			}
		}
		.onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
	}
}

extension View {
	/// Centres a page's content in a readable column on a wide screen.
	func readableColumn() -> some View {
		frame(maxWidth: TitlePageLayout.maxColumnWidth)
			.frame(maxWidth: .infinity)
	}

	/// A title page's ground: its colour running down to a deeper shade, the
	/// dark scheme, and a bar that turns solid once the title scrolls away.
	func titlePage(color: UIColor?, compactBar: Bool) -> some View {
		let base = color ?? PageTheme.fallback
		return background(PageTheme.backdrop(base).ignoresSafeArea())
			.environment(\.colorScheme, .dark)
			.navigationBarTitleDisplayMode(.inline)
			.toolbarColorScheme(.dark, for: .navigationBar)
			.toolbarBackground(Color(uiColor: base), for: .navigationBar)
			.toolbarBackgroundVisibility(compactBar ? .visible : .hidden, for: .navigationBar)
	}

	/// The page's glass capsule buttons: Open in…, Share.
	func titlePageCapsule() -> some View {
		font(.system(size: 13, weight: .semibold))
			.foregroundStyle(.white)
			.frame(maxWidth: .infinity, minHeight: GlassControl.height)
			.glassEffect(.regular, in: Capsule())
	}
}

// MARK: - Status switch

struct PageSwitchOption: Identifiable {
	let title: String
	var systemImage: String? = nil
	let selected: Bool
	let fill: Color
	let action: () -> Void

	var id: String { title }
}

/// The design's To watch / Watched switch; a show in progress adds a third,
/// Watching side.
struct PageSwitch: View {
	let options: [PageSwitchOption]
	/// The chosen side's text: the page's deep shade.
	let selectedText: Color

	@Environment(\.horizontalSizeClass) private var sizeClass

	var body: some View {
		// A size up on an iPad, beside the bigger poster above it.
		let large = sizeClass == .regular
		HStack(spacing: 4) {
			ForEach(options) { option in
				Button {
					Haptics.selection()
					option.action()
				} label: {
					HStack(spacing: 5) {
						if let systemImage = option.systemImage {
							Image(systemName: systemImage)
								.font(.system(size: large ? 13 : 11, weight: .bold))
						}
						Text(option.title)
							.font(.system(size: large ? 16 : 14, weight: .semibold))
							.lineLimit(1)
					}
					.foregroundStyle(option.selected ? selectedText : .white.opacity(0.75))
					.padding(.horizontal, large ? 20 : 16)
					// Inside the switch's 4pt rim, so the whole switch is a glass control's height.
					.frame(height: GlassControl.height - (large ? 0 : 8))
					.background {
						if option.selected { Capsule().fill(option.fill) }
					}
					.contentShape(Capsule())
				}
				.buttonStyle(.plain)
				.accessibilityAddTraits(option.selected ? .isSelected : [])
			}
		}
		.padding(4)
		.glassEffect(.regular.tint(.white.opacity(0.06)), in: Capsule())
	}
}

// MARK: - Chips and labels

/// A verdict as a small capsule with its colour dot; "Rate" when there's none.
struct VerdictChip: View {
	let rating: Rating?
	var emptyLabel = "Not rated"

	var body: some View {
		HStack(spacing: 5) {
			if let rating {
				Circle()
					.fill(Glass.tint(rating))
					.frame(width: 7, height: 7)
			}
			Text(rating?.rawValue ?? emptyLabel)
				.font(.system(size: 12, weight: .semibold))
				.lineLimit(1)
		}
		.foregroundStyle(.white.opacity(rating == nil ? 0.75 : 1))
		.padding(.horizontal, 9)
		.padding(.vertical, 5)
		.background(.white.opacity(rating == nil ? 0.1 : 0.12), in: Capsule())
	}
}

/// An episode's rating as a small capsule; "Rate" when there's none.
struct TierChip: View {
	let tier: EpisodeTier?

	var body: some View {
		HStack(spacing: 4) {
			if let tier {
				Image(systemName: tier.systemImage)
					.font(.system(size: 9, weight: .bold))
					.foregroundStyle(Glass.tint(tier))
			}
			Text(tier?.rawValue ?? "Rate")
				.font(.system(size: 11, weight: .semibold))
		}
		.foregroundStyle(.white.opacity(tier == nil ? 0.7 : 1))
		.padding(.horizontal, 8)
		.padding(.vertical, 4)
		.background(.white.opacity(tier == nil ? 0.08 : 0.14), in: Capsule())
	}
}

/// The status menu's label: the verdict once rated and watched, otherwise the
/// status.
struct PageStatusLabel: View {
	let status: WatchStatus
	let rating: Rating?

	var body: some View {
		HStack(spacing: 6) {
			if status == .watched, let rating {
				Circle()
					.fill(Glass.tint(rating))
					.frame(width: 8, height: 8)
				Text(rating.rawValue)
			} else {
				Image(systemName: status.systemImage)
					.font(.system(size: 12, weight: .semibold))
				Text(status.rawValue)
			}
			Image(systemName: "chevron.down")
				.font(.system(size: 11, weight: .bold))
		}
		.font(.system(size: 14, weight: .semibold))
		.foregroundStyle(.white)
	}
}

/// The compact bar's poster, title and one line under it.
struct PageCompactTitle: View {
	let posterURL: String
	let placeholder: String
	let title: String
	let subtitle: String

	var body: some View {
		HStack(spacing: 8) {
			PosterImage(urlString: posterURL, systemPlaceholder: placeholder)
				.frame(width: 24, height: 36)
				.clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
			VStack(alignment: .leading, spacing: 0) {
				Text(title)
					.font(.system(size: 14, weight: .bold))
					.lineLimit(1)
				Text(subtitle)
					.font(.system(size: 11, weight: .medium))
					.foregroundStyle(.white.opacity(0.65))
					.lineLimit(1)
			}
		}
		.foregroundStyle(.white)
	}
}

/// TMDb's stars out of ten as five, with the rest of the meta line after them.
struct PageMetaLine: View {
	let voteAverage: Double?
	let parts: [String]

	@Environment(\.horizontalSizeClass) private var sizeClass

	var body: some View {
		let average = voteAverage ?? 0
		let large = sizeClass == .regular
		HStack(spacing: 6) {
			if average > 0 {
				HStack(spacing: 1) {
					ForEach(Array(FilmFacts.stars(outOf10: average).enumerated()), id: \.offset) { _, star in
						Image(systemName: StarRatingPicker.symbol(star))
					}
				}
				.font(.system(size: large ? 12 : 10))
				.accessibilityElement(children: .ignore)
				.accessibilityLabel(String(format: "TMDb rating %.1f out of 10", average))
			}
			if !parts.isEmpty {
				Text(parts.joined(separator: " · "))
			}
		}
		.font(.system(size: large ? 15 : 13, weight: .medium))
		.foregroundStyle(.white.opacity(0.75))
		.multilineTextAlignment(.center)
	}
}

// MARK: - Sections and cards

struct PageSection<Content: View>: View {
	let title: String
	@ViewBuilder let content: Content

	@Environment(\.horizontalSizeClass) private var sizeClass

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text(title)
				.font(.system(size: sizeClass == .regular ? 22 : 20, weight: .bold))
				.foregroundStyle(.white)
				.accessibilityAddTraits(.isHeader)
			content
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(.top, 8)
	}
}

struct PageSmallCaps: View {
	let text: String

	var body: some View {
		Text(text.uppercased())
			.font(.system(size: 10, weight: .semibold, design: .monospaced))
			.kerning(1.2)
			.foregroundStyle(.white.opacity(0.55))
	}
}

/// A synopsis in a glass card; long ones fold to four lines with "more".
struct PageSynopsisCard: View {
	let text: String
	@State private var expanded = false

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			PageSmallCaps(text: "Synopsis")
			Text(text)
				.font(.system(size: 14))
				.foregroundStyle(.white.opacity(0.9))
				.lineLimit(expanded ? nil : 4)
				.fixedSize(horizontal: false, vertical: true)
			if text.count > 180 {
				Button(expanded ? "less" : "more") {
					withAnimation(Glass.smooth) { expanded.toggle() }
				}
				.font(.system(size: 13, weight: .semibold))
				.foregroundStyle(.white)
			}
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(14)
		.liquidCard(cornerRadius: 20)
	}
}

/// People in a row that runs out to the screen's edges.
struct PageCastRow: View {
	let cast: [CastEntry]

	var body: some View {
		ScrollView(.horizontal) {
			HStack(alignment: .top, spacing: 14) {
				ForEach(cast) { person in
					VStack(spacing: 6) {
						PersonAvatar(urlString: person.profileURL, name: person.name)
							.frame(width: 60, height: 60)
							.overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
						Text(person.name)
							.font(.system(size: 11, weight: .semibold))
							.foregroundStyle(.white)
							.multilineTextAlignment(.center)
							.lineLimit(2)
						if !person.character.isEmpty {
							Text(person.character)
								.font(.system(size: 10, weight: .medium))
								.foregroundStyle(.white.opacity(0.55))
								.lineLimit(1)
						}
					}
					.frame(width: 76)
					.accessibilityElement(children: .combine)
				}
			}
			.padding(.horizontal, 18)
		}
		.scrollIndicators(.hidden)
		.padding(.horizontal, -18)
	}
}

// MARK: - Header and your rating

/// A title page's header: the poster, the title — with a line under it when
/// there is one — and the meta line.
struct PagePosterHeader: View {
	let posterURL: String
	let placeholder: String
	let title: String
	var subtitle: String? = nil
	let voteAverage: Double?
	let metaParts: [String]

	@Environment(\.horizontalSizeClass) private var sizeClass

	var body: some View {
		// An iPad's page has the room for a poster you can see.
		let large = sizeClass == .regular
		VStack(spacing: 10) {
			PosterImage(urlString: posterURL, systemPlaceholder: placeholder)
				.frame(width: large ? 208 : 132, height: large ? 312 : 198)
				.clipShape(RoundedRectangle(cornerRadius: large ? 18 : 14, style: .continuous))
				.shadow(color: .black.opacity(0.45), radius: 22, y: 12)
				.padding(.top, 6)
				.accessibilityHidden(true)
			VStack(spacing: 2) {
				Text(title)
					.font(.system(size: large ? 40 : 30, weight: .bold))
					.foregroundStyle(.white)
					.multilineTextAlignment(.center)
					.accessibilityAddTraits(.isHeader)
				if let subtitle {
					Text(subtitle)
						.font(.system(size: large ? 18 : 15, weight: .semibold))
						.foregroundStyle(.white.opacity(0.8))
				}
			}
			.padding(.top, 6)
			PageMetaLine(voteAverage: voteAverage, parts: metaParts)
		}
		.frame(maxWidth: .infinity)
	}
}

/// Your rating: the verdict, its stars and when, Edit, the private note, and
/// Share with friends — the title and your take as a WatchList link.
struct PageVerdictCard: View {
	let rating: Rating?
	let stars: Double?
	let dateLine: String?
	let note: String
	var noteLabel = "Private note"
	/// What Share with friends sends; nil leaves it out.
	var share: SharedTitle?
	let onEdit: () -> Void

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(spacing: 8) {
				VerdictChip(rating: rating)
				if let stars { StarsLabel(value: stars) }
				if let dateLine {
					Text(dateLine)
						.font(.system(size: 12, weight: .medium))
						.foregroundStyle(.white.opacity(0.6))
						.lineLimit(1)
						.minimumScaleFactor(0.85)
				}
				Spacer(minLength: 4)
				Button("Edit", action: onEdit)
					.font(.system(size: 13, weight: .semibold))
					.foregroundStyle(.white)
			}
			if !note.isEmpty {
				Text(note)
					.font(.system(size: 14))
					.foregroundStyle(.white.opacity(0.9))
					.fixedSize(horizontal: false, vertical: true)
			}
			HStack {
				Label(noteLabel, systemImage: "lock.fill")
					.font(.system(size: 11, weight: .medium))
					.foregroundStyle(.white.opacity(0.55))
				Spacer()
				if let share { ShareWithFriendsLink(title: share) }
			}
		}
		.padding(14)
		.liquidCard(cornerRadius: 20)
	}
}

/// Sends a title and your take on it as a watchlist:// link, with a line of
/// words for anyone reading it without the app.
struct ShareWithFriendsLink: View {
	let title: SharedTitle

	var body: some View {
		if let link = FriendShare.link(for: title, from: FriendShare.senderName) {
			ShareLink(item: FriendShare.message(for: title, link: link),
			          preview: SharePreview("\(title.title) on WatchList")) {
				Label("Share with friends", systemImage: "person.2")
					.font(.system(size: 12, weight: .semibold))
					.foregroundStyle(.white)
					.padding(.horizontal, 10)
					.frame(height: 28)
					.glassEffect(.regular, in: Capsule())
			}
			.accessibilityHint("Your verdict, stars and note go with it")
		}
	}
}

// MARK: - Details

/// A Details card row: an icon in a circle, a small-caps label and its value.
struct PageDetailRow<Value: View>: View {
	let label: String
	let icon: String
	@ViewBuilder let value: Value

	var body: some View {
		HStack(spacing: 12) {
			Image(systemName: icon)
				.font(.system(size: 13, weight: .semibold))
				.foregroundStyle(.white.opacity(0.7))
				.frame(width: 32, height: 32)
				.background(.white.opacity(0.08), in: Circle())
			VStack(alignment: .leading, spacing: 3) {
				PageSmallCaps(text: label)
				value
			}
			Spacer(minLength: 0)
		}
		.padding(.vertical, 8)
	}
}

extension PageDetailRow where Value == PageDetailValue {
	init(_ label: String, icon: String, text: String) {
		self.init(label: label, icon: icon) { PageDetailValue(text: text) }
	}
}

struct PageDetailValue: View {
	let text: String

	var body: some View {
		Text(text)
			.font(.system(size: 14, weight: .semibold))
			.foregroundStyle(.white)
	}
}

/// The hairline between rows, set in past a row's leading icon or artwork.
struct PageRowDivider: View {
	var inset: CGFloat = 44

	var body: some View {
		Rectangle()
			.fill(.white.opacity(0.08))
			.frame(height: 1)
			.padding(.leading, inset)
	}
}

// MARK: - Menus

/// A status menu's Status section: a tick against the current status. Choosing
/// the ticked one again does nothing — a title always has a status.
struct StatusMenuSection: View {
	let current: WatchStatus
	var statuses: [WatchStatus] = WatchStatus.allCases
	let choose: (WatchStatus) -> Void

	var body: some View {
		Section("Status") {
			ForEach(statuses) { status in
				Toggle(status.rawValue, isOn: Binding(get: { current == status }, set: { if $0 { choose(status) } }))
			}
		}
	}
}

/// A status menu's Rate section: a tick against the verdict; choosing the
/// ticked one again clears it. Toggles — not an inline picker — because a menu
/// drops a section's heading when an inline picker fills it.
struct VerdictMenuSection<Item: Rated>: View {
	let item: Item

	var body: some View {
		Section("Rate") {
			ForEach(Rating.allCases) { rating in
				Toggle(rating.rawValue, isOn: Binding(get: { item.rating == rating }, set: { isOn in
					Haptics.selection()
					withAnimation(Glass.smooth) { item.setVerdict(isOn ? rating : nil) }
				}))
			}
		}
	}
}

// MARK: - Sharing and artwork

enum TitleLinks {
	static func tmdbMovie(_ id: Int?) -> URL? {
		id.flatMap { URL(string: "https://www.themoviedb.org/movie/\($0)") }
	}

	static func tmdbTV(_ id: Int?, season: Int? = nil, episode: Int? = nil) -> URL? {
		guard let id else { return nil }
		var path = "https://www.themoviedb.org/tv/\(id)"
		if let season { path += "/season/\(season)" }
		if let season, let episode, season >= 0 { path += "/episode/\(episode)" }
		return URL(string: path)
	}
}

/// "Open in…": the title on every site there's a link for (TitleSites) —
/// IMDb and TMDb first, the rest under them.
struct OpenInMenu<Content: View>: View {
	let sites: [TitleSite]
	@ViewBuilder let label: () -> Content

	/// Whether there's anywhere to open it.
	var hasLinks: Bool { !sites.isEmpty }

	private static var databases: Set<String> { ["IMDb", "TMDb"] }

	var body: some View {
		Menu {
			Section {
				ForEach(sites.filter { Self.databases.contains($0.name) }) { link($0) }
			}
			Section {
				ForEach(sites.filter { !Self.databases.contains($0.name) }) { link($0) }
			}
		} label: {
			label()
		}
	}

	@ViewBuilder private func link(_ site: TitleSite) -> some View {
		switch site.destination {
		case .url(let url):
			Link(destination: url) { Label(site.name, systemImage: "arrow.up.right") }
		case .trakt(let lookup):
			TraktLink(lookup: lookup, name: site.name)
		}
	}
}

/// Trakt, looked up when tapped. A title Trakt doesn't have, or no
/// connection, leaves the page where it is with a warning buzz.
private struct TraktLink: View {
	let lookup: TraktLookup
	let name: String

	@Environment(\.openURL) private var openURL

	var body: some View {
		Button {
			Task {
				if let url = await Trakt.pageURL(lookup) {
					openURL(url)
				} else {
					Haptics.warning()
				}
			}
		} label: {
			Label(name, systemImage: "arrow.up.right")
		}
	}
}

/// The details card's "Open in…" capsule.
struct OpenInLabel: View {
	var body: some View {
		HStack(spacing: 5) {
			Text("Open in…")
			Image(systemName: "chevron.up.chevron.down")
				.font(.system(size: 10, weight: .bold))
		}
		.titlePageCapsule()
	}
}

/// Shares the first link there is — IMDb's before TMDb's — or just the name.
struct TitleShareLink<Label: View>: View {
	let title: String
	let links: [URL?]
	@ViewBuilder let label: () -> Label

	var body: some View {
		if let url = links.lazy.compactMap({ $0 }).first {
			ShareLink(item: url, subject: Text(title), label: label)
		} else {
			ShareLink(item: title, label: label)
		}
	}
}

// MARK: - Removing

extension ModelContext {
	/// Leaves the page before deleting, so nothing still on screen reads a
	/// record that's gone.
	func delete<Model: PersistentModel>(_ model: Model, afterLeaving dismiss: DismissAction) {
		dismiss()
		Task { @MainActor in
			try? await Task.sleep(for: .milliseconds(450))
			self.delete(model)
		}
	}
}
