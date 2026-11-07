//
//  LiquidDock.swift
//  WatchList
//
//  The iPhone's tab bar, after design B of the alternatives: the four tabs
//  together in one glass capsule on the leading side — the one you're on in a
//  bubble with its name under its icon, the others icon only — and beside
//  them, filling the rest, a wide glass capsule that opens Search: "Add a
//  title". iPad keeps the system's floating tab bar and sidebar.
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

	private struct Item: Identifiable {
		let tab: PhoneTab
		let title: String
		let symbol: String
		var id: String { title }
	}

	/// How much a page's scroll content needs at its end to clear the dock.
	static let clearance: CGFloat = 58 + 2 + 12

	private let items = [
		Item(tab: .home, title: "Home", symbol: "house"),
		Item(tab: .shows, title: "Shows", symbol: "popcorn"),
		Item(tab: .discover, title: "Discover", symbol: "sparkles"),
		Item(tab: .collections, title: "Collections", symbol: "square.grid.2x2"),
	]

	var body: some View {
		GlassEffectContainer(spacing: 8) {
			HStack(spacing: 8) {
				HStack(spacing: 2) {
					ForEach(items) { item in tabButton(item) }
				}
				.padding(.horizontal, 6)
				.frame(height: 58)
				.glassEffect(.regular.interactive(), in: Capsule())

				Button { onSelect(.search) } label: {
					HStack(spacing: 8) {
						Image(systemName: "magnifyingglass")
							.font(.system(size: 17, weight: .semibold))
						Text("Add a title")
							.font(.system(size: 15, weight: .medium))
							.lineLimit(1)
						Spacer(minLength: 0)
					}
					.foregroundStyle(selection == .search ? Glass.ink : Glass.ink.opacity(0.72))
					.padding(.horizontal, 16)
					.frame(maxWidth: .infinity, minHeight: 58)
					.contentShape(Capsule())
				}
				.buttonStyle(.plain)
				.glassEffect(selection == .search ? .regular.tint(Glass.ink.opacity(0.12)).interactive() : .regular.interactive(),
				             in: Capsule())
				.accessibilityLabel("Search, add a title")
				.accessibilityAddTraits(selection == .search ? .isSelected : [])
			}
		}
		.padding(.horizontal, 16)
		.padding(.bottom, 2)
	}

	private func tabButton(_ item: Item) -> some View {
		let chosen = selection == item.tab
		return Button { onSelect(item.tab) } label: {
			VStack(spacing: 1) {
				Image(systemName: item.symbol)
					.font(.system(size: 18, weight: chosen ? .bold : .medium))
					.symbolVariant(chosen ? .fill : .none)
				if chosen {
					Text(item.title)
						.font(.system(size: 9, weight: .bold))
						.lineLimit(1)
						.minimumScaleFactor(0.8)
				}
			}
			.foregroundStyle(chosen ? Glass.ink : Glass.ink.opacity(0.75))
			.frame(width: chosen ? 58 : 46, height: 46)
			.background {
				if chosen { Capsule().fill(Glass.ink.opacity(0.14)) }
			}
			.contentShape(Capsule())
		}
		.buttonStyle(.plain)
		.animation(Glass.pop, value: chosen)
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
