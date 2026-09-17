//
//  RootView.swift
//  WatchList
//
//  Top-level shell. Sets the Editorial Paper chrome (refined serif navigation
//  titles over the paper canvas), then hosts PhoneRootView on every device: the
//  Liquid Glass tab bar on iPhone, the floating tab bar and sidebar on iPad. Also
//  re-applies the user's accent color when the app returns to the foreground
//  (e.g. after changing it in the iOS Settings app).
//

import SwiftUI
import SwiftData
import UIKit

struct RootView: View {
	@ObservedObject private var theme = AppTheme.shared
	@Environment(\.scenePhase) private var scenePhase

	init() {
		// Serif, ink-colored navigation titles for the editorial feel.
		let ink = UIColor(resource: .ink)
		func serif(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
			let base = UIFont.systemFont(ofSize: size, weight: weight)
			if let d = base.fontDescriptor.withDesign(.serif) {
				return UIFont(descriptor: d, size: size)
			}
			return base
		}
		let nav = UINavigationBarAppearance()
		nav.configureWithTransparentBackground()
		nav.largeTitleTextAttributes = [.font: serif(34, .bold), .foregroundColor: ink]
		nav.titleTextAttributes = [.font: serif(17, .semibold), .foregroundColor: ink]
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
