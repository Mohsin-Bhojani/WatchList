//
//  RootView.swift
//  WatchList
//
//  Top-level shell. Sets the navigation chrome (serif titles in ink over the
//  colour-blur backdrop), then hosts PhoneRootView on every device: the
//  Liquid Glass tab bar on iPhone, the floating tab bar and sidebar on iPad. Also
//  re-applies the user's accent color when the app returns to the foreground
//  (e.g. after changing it in the iOS Settings app).
//

import SwiftUI
import SwiftData
import UIKit
import WatchListCore
import WatchListLibrary

struct RootView: View {
	@ObservedObject private var theme = AppTheme.shared
	@Environment(\.scenePhase) private var scenePhase

	init() {
		// Ink-coloured navigation titles over the app's own backgrounds.
		let ink = UIColor(resource: .ink)
		let nav = UINavigationBarAppearance()
		nav.configureWithTransparentBackground()
		nav.largeTitleTextAttributes = [.foregroundColor: ink]
		nav.titleTextAttributes = [.foregroundColor: ink]
		UINavigationBar.appearance().standardAppearance = nav
		UINavigationBar.appearance().scrollEdgeAppearance = nav
		UINavigationBar.appearance().compactAppearance = nav
	}

	var body: some View {
		shell
			.tint(Glass.accent)
			.environmentObject(theme)
			.onChange(of: scenePhase) { _, phase in
				if phase == .active { theme.refreshFromDefaults() }
			}
	}

	/// PhoneRootView tells iPad from iPhone itself, by device rather than size
	/// class, so an iPad in Split View or Slide Over keeps its sidebar.
	private var shell: some View {
		PhoneRootView()
	}
}
