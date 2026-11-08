//
//  TabReselect.swift
//  WatchList
//
//  What the tab bar needs beyond the system's own:
//    - scrollsToTopOnReselect: the tab you're on, tapped again away from the
//      top of its page, takes the page back up
//

import SwiftUI
import WatchListCore
import WatchListLibrary

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
