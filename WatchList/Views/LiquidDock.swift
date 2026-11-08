//
//  LiquidDock.swift
//  WatchList
//
//  The iPhone's tab bar: the system's look — one glass capsule, each tab its
//  icon over its name, the one you're on lit in a bubble — with Search moved
//  to the middle as its own round button, lifted above the bar: a plus in a
//  magnifying glass, for adding a title. iPad keeps the system's floating tab
//  bar and sidebar.
//
//  Tapping the tab you're on again: at the top of its page, Shows, Discover
//  and Collections open their filters (PhoneRootView); anywhere else, the page
//  scrolls back to its top (scrollsToTopOnReselect).
//

import SwiftUI
import WatchListCore
import WatchListLibrary

/// Overlays drawn inside a page (the rating sheet) sit under the dock, which
/// the root draws above every page. While one is up it counts itself here and
/// the dock steps aside, so it never covers the overlay's buttons.
@Observable final class DockCover {
	static let shared = DockCover()
	var count = 0
	var isCovered: Bool { count > 0 }
}

extension View {
	/// Hides the iPhone dock for as long as this view is on screen.
	func coversDock() -> some View {
		onAppear { DockCover.shared.count += 1 }
			.onDisappear { DockCover.shared.count = max(0, DockCover.shared.count - 1) }
	}
}

struct LiquidDock: View {
	let selection: PhoneTab
	let onSelect: (PhoneTab) -> Void

	/// One highlight that slides between the tabs, like the system bar's.
	@Namespace private var highlight
	/// The tab under a finger, swelling slightly before it's let go.
	@GestureState private var pressed: PhoneTab?

	private static let slide = Animation.spring(response: 0.38, dampingFraction: 0.78)

	private struct Item: Identifiable {
		let tab: PhoneTab
		let title: String
		let symbol: String
		var id: String { title }
	}

	private static let barHeight: CGFloat = 62
	private static let searchSize: CGFloat = 60
	/// How far the search button rises above the bar's top edge.
	private static let lift: CGFloat = 14

	/// How much a page's scroll content needs at its end to clear the dock,
	/// the lifted search button included.
	static let clearance: CGFloat = barHeight + 2 + lift + 12

	private let leading = [
		Item(tab: .home, title: "Home", symbol: "house"),
		Item(tab: .shows, title: "Shows", symbol: "popcorn"),
	]
	private let trailing = [
		Item(tab: .discover, title: "Discover", symbol: "sparkles"),
		Item(tab: .collections, title: "Collections", symbol: "square.grid.2x2"),
	]

	var body: some View {
		HStack(spacing: 0) {
			ForEach(leading) { tabButton($0) }
			// Room in the middle for the search button standing over it.
			Color.clear.frame(width: Self.searchSize + 8)
			ForEach(trailing) { tabButton($0) }
		}
		.padding(.horizontal, 6)
		.frame(height: Self.barHeight)
		.animation(Self.slide, value: selection)
		.glassEffect(.regular.interactive(), in: Capsule())
		.overlay(alignment: .top) { searchButton.offset(y: -Self.lift) }
		.padding(.horizontal, 16)
		.padding(.bottom, 2)
	}

	private var searchButton: some View {
		let chosen = selection == .search
		return Button { onSelect(.search) } label: {
			Image(systemName: "plus.magnifyingglass")
				.font(.system(size: 24, weight: .semibold))
				.foregroundStyle(.white)
				.frame(width: Self.searchSize, height: Self.searchSize)
				.contentShape(Circle())
		}
		.buttonStyle(.plain)
		.glassEffect(.regular.tint(Glass.accent.opacity(chosen ? 1 : 0.85)).interactive(), in: Circle())
		.shadow(color: Glass.accent.opacity(0.35), radius: 10, y: 4)
		.accessibilityLabel("Search, add a title")
		.accessibilityAddTraits(chosen ? .isSelected : [])
	}

	private func tabButton(_ item: Item) -> some View {
		let chosen = selection == item.tab
		return Button { onSelect(item.tab) } label: {
			VStack(spacing: 2) {
				Image(systemName: item.symbol)
					.font(.system(size: 19, weight: chosen ? .semibold : .regular))
					.symbolVariant(chosen ? .fill : .none)
					.frame(height: 24)
				Text(item.title)
					.font(.system(size: 10, weight: .semibold))
					.lineLimit(1)
					.minimumScaleFactor(0.75)
			}
			.foregroundStyle(chosen ? Glass.accent : Glass.ink.opacity(0.8))
			.frame(maxWidth: .infinity, minHeight: 50)
			.background {
				if chosen {
					Capsule().fill(Glass.ink.opacity(0.12))
						.matchedGeometryEffect(id: "highlight", in: highlight)
				}
			}
			.contentShape(Capsule())
			.scaleEffect(pressed == item.tab ? 1.08 : 1)
			.animation(.spring(response: 0.25, dampingFraction: 0.6), value: pressed)
		}
		.buttonStyle(.plain)
		.simultaneousGesture(DragGesture(minimumDistance: 0).updating($pressed) { _, state, _ in state = item.tab })
		.accessibilityLabel(item.title)
		.accessibilityAddTraits(chosen ? .isSelected : [])
	}
}

// MARK: - Back to the top

extension Notification.Name {
	/// The tab you're on, tapped again away from the top of its page.
	static let tabReselected = Notification.Name("WatchListTabReselected")
}

extension View {
	/// Scrolls this tab's page back to its top when its tab is tapped again.
	func scrollsToTopOnReselect(_ tab: PhoneTab) -> some View {
		modifier(ScrollToTopOnReselect(tab: tab))
	}
}

private struct ScrollToTopOnReselect: ViewModifier {
	let tab: PhoneTab
	@State private var position = ScrollPosition(edge: .top)

	func body(content: Content) -> some View {
		content
			.scrollPosition($position)
			.onReceive(NotificationCenter.default.publisher(for: .tabReselected)) { note in
				guard (note.object as? PhoneTab) == tab else { return }
				withAnimation(Glass.smooth) { position.scrollTo(edge: .top) }
			}
	}
}
