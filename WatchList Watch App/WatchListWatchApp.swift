//
//  WatchListWatchApp.swift
//  WatchList Watch App
//
//  The watch app's entry point. It runs on its own — it installs and opens
//  without the iPhone app — and syncs with the iPhone app when both are there
//  (PhoneSync). What it shows is kept on the watch (WatchStore).
//
//  Three pages, a Crown turn apart: Up Next on top, Discover below it, and
//  Discover's Filter below that. Only the Crown moves between them.
//

import SwiftUI
import WatchKit

@main
struct WatchListWatchApp: App {
	@State private var store: WatchStore
	private let sync: PhoneSync

	@Environment(\.scenePhase) private var scenePhase

	init() {
		let store = WatchStore.launching()
		_store = State(initialValue: store)
		sync = PhoneSync(store: store)
		sync.start()
	}

	var body: some Scene {
		WindowGroup {
			WatchRootView()
				.environment(store)
		}
		.onChange(of: scenePhase) { _, phase in
			guard phase == .active else { return }
			// Anything that failed to go, and whatever's changed on the iPhone.
			sync.flush()
			sync.refresh()
		}
	}
}

enum WatchPage: Int, CaseIterable {
	case upNext, discover, filter
}

/// Up Next, Discover and Filter, stacked: turning the Crown slides between
/// them, and nothing else does. A vertical page view would change page on a
/// swipe too, and Discover's swipes are for deciding on its poster — up is
/// Later — so a swipe must never be taken for a page turn. The one
/// NavigationStack holds all three, and Filter's lists push onto it.
struct WatchRootView: View {
	/// The page the Crown last came to rest on.
	@State private var page: WatchPage = .upNext
	/// Where the pages are, in pages: following the Crown as it turns, whole
	/// once it rests.
	@State private var position: Double = 0
	/// The Crown's resting place, as its detents count it.
	@State private var detent: Double = 0
	@State private var turning = false
	@State private var path: [FilterRoute] = []
	/// A page has a sheet up.
	@State private var sheetUp = false
	/// Discover's colour, for Filter's page to carry on from.
	@State private var discoverTone: Color?
	@FocusState private var crownFocused: Bool
	@Environment(\.scenePhase) private var scenePhase

	private static let last = Double(WatchPage.allCases.count - 1)
	private static let screen = WKInterfaceDevice.current().screenBounds.size

	var body: some View {
		NavigationStack(path: $path) {
			GeometryReader { proxy in
				// Each page is the whole screen, behind the time too, and a screen
				// from the next, so one page's colour meets the next. The safe area
				// goes back in as padding, so a page lays out as it would on its
				// own, and the size is set, as Discover's would run past the screen.
				let insets = proxy.safeAreaInsets
				ZStack {
					ForEach(WatchPage.allCases, id: \.self) { each in
						pageView(each)
							.safeAreaPadding(insets)
							.frame(width: Self.screen.width, height: Self.screen.height)
							.environment(\.isPageInView, each == page)
							.offset(y: (Double(each.rawValue) - position) * Self.screen.height)
							.allowsHitTesting(each == page)
							.accessibilityHidden(each != page)
					}
				}
				.frame(width: Self.screen.width, height: Self.screen.height)
				.ignoresSafeArea()
			}
			// While a list pushed from Filter or a page's sheet is up, the Crown
			// scrolls that instead, and it's back to the pages once it's gone.
			.focusable(uncovered)
			.focused($crownFocused)
			.focusEffectDisabled()
			.digitalCrownRotation(detent: $detent, from: 0, through: Self.last, by: 1,
			                      sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true,
			                      onChange: { event in follow(event.offset) }, onIdle: rest)
			.onChange(of: detent) {
				page = WatchPage(rawValue: Int(detent.rounded())) ?? .upNext
				if !turning { settle() }
			}
			.onPreferenceChange(PageSheetKey.self) { sheetUp = $0 }
			.onChange(of: uncovered, initial: true) { _, uncovered in
				if uncovered { reclaimCrown() }
			}
			.onChange(of: scenePhase) { _, phase in
				if phase == .active { reclaimCrown() }
			}
			.accessibilityScrollAction { edge in
				switch edge {
				case .top:    turn(to: detent - 1)
				case .bottom: turn(to: detent + 1)
				default:      break
				}
			}
		}
	}

	@ViewBuilder
	private func pageView(_ which: WatchPage) -> some View {
		switch which {
		case .upNext:   UpNextPage()
		case .discover: DiscoverPage(backdropTone: $discoverTone)
		case .filter:   DiscoverFilterPage(tone: discoverTone)
		}
	}

	// MARK: The Crown

	private var uncovered: Bool { path.isEmpty && !sheetUp }

	/// Gives the Crown back to the pages once whatever was over them has gone.
	/// Asked for while it's still going, focus doesn't take, so this waits a
	/// moment, and asks again if it has to.
	private func reclaimCrown() {
		Task {
			for _ in 0..<3 {
				try? await Task.sleep(for: .milliseconds(300))
				guard uncovered, !crownFocused else { return }
				crownFocused = true
			}
		}
	}

	/// Keeps up with the Crown as it turns, a little way past either end —
	/// springing, as the Crown's value can leap as it settles on a page.
	private func follow(_ offset: Double) {
		turning = true
		withAnimation(.interactiveSpring(duration: 0.2)) {
			position = min(max(offset, -0.12), Self.last + 0.12)
		}
	}

	/// The Crown's stopped: onto the page it rests on.
	private func rest() {
		turning = false
		settle()
	}

	private func settle() {
		withAnimation(.snappy(duration: 0.25)) { position = detent.rounded() }
	}

	/// For VoiceOver's scroll: a page up or down, as a Crown turn would.
	private func turn(to target: Double) {
		let clamped = min(max(target.rounded(), 0), Self.last)
		guard clamped != detent else { return }
		detent = clamped
	}
}

/// Whether a page has a sheet up, which the Crown should scroll, not the pages.
struct PageSheetKey: PreferenceKey {
	static let defaultValue = false
	static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension EnvironmentValues {
	/// Whether this page is the one on screen. The others stay put off screen,
	/// so this keeps Double Tap to the page in view.
	@Entry var isPageInView = true
}

extension WatchStore {
	/// The store the app runs on. In a Debug build, -WatchListSample swaps in a
	/// made-up library that's never saved, to try the app with no iPhone.
	static func launching() -> WatchStore {
		#if DEBUG
		if ProcessInfo.processInfo.arguments.contains("-WatchListSample") {
			return WatchStore(preview: .sample)
		}
		#endif
		return WatchStore()
	}
}
