//
//  AppTheme.swift
//  WatchList
//
//  User-selectable accent color. The choice is stored in UserDefaults (and
//  surfaced in the iOS Settings app via Settings.bundle, key "accentColorID").
//  `Glass.accent` / `accent2` / `accent3` read from the current palette, so the
//  whole app re-tints when the selection changes. Each palette's three colours
//  are colour sets in Assets.xcassets, under Colors/Themes.
//

import SwiftUI
import Combine

struct AccentPalette: Identifiable {
	let id: String
	let name: String
	let accent: Color
	let accent2: Color
	let accent3: Color
}

enum AccentCatalog {
	static let defaultID = "classicRed"

	static let all: [AccentPalette] = [
		AccentPalette(id: "classicRed",  name: "Classic Red",  accent: Color(.classicRedAccent), accent2: Color(.classicRedAccent2), accent3: Color(.classicRedAccent3)),
		AccentPalette(id: "cobaltBlue",  name: "Cobalt Blue",  accent: Color(.cobaltBlueAccent), accent2: Color(.cobaltBlueAccent2), accent3: Color(.cobaltBlueAccent3)),
		AccentPalette(id: "forestGreen", name: "Forest Green", accent: Color(.forestGreenAccent), accent2: Color(.forestGreenAccent2), accent3: Color(.forestGreenAccent3)),
		AccentPalette(id: "plum",        name: "Plum",         accent: Color(.plumAccent), accent2: Color(.plumAccent2), accent3: Color(.plumAccent3)),
		AccentPalette(id: "amber",       name: "Amber",        accent: Color(.amberAccent), accent2: Color(.amberAccent2), accent3: Color(.amberAccent3)),
		AccentPalette(id: "graphite",    name: "Graphite",     accent: Color(.graphiteAccent), accent2: Color(.graphiteAccent2), accent3: Color(.graphiteAccent3)),
	]

	static func palette(for id: String) -> AccentPalette {
		all.first { $0.id == id } ?? all[0]
	}
}

/// Observable accent selection. `RootView` observes this and refreshes it when
/// the app returns to the foreground, so changes made in the iOS Settings app
/// take effect immediately across the whole UI.
final class AppTheme: ObservableObject {
	//var objectWillChange: ObservableObjectPublisher
	
	static let shared = AppTheme()

	@Published private(set) var accentID: String

	private init() {
		accentID = UserDefaults.standard.string(forKey: "accentColorID") ?? AccentCatalog.defaultID
	}

	var palette: AccentPalette { AccentCatalog.palette(for: accentID) }

	func refreshFromDefaults() {
		let latest = UserDefaults.standard.string(forKey: "accentColorID") ?? AccentCatalog.defaultID
		if latest != accentID { accentID = latest }
	}

	/// Set from the in-app Settings screen; persists and re-tints immediately.
	func setAccent(_ id: String) {
		guard AccentCatalog.all.contains(where: { $0.id == id }), id != accentID else { return }
		UserDefaults.standard.set(id, forKey: "accentColorID")
		accentID = id
	}
}
