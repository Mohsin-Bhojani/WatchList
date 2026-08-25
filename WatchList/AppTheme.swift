//
//  AppTheme.swift
//  WatchList
//
//  User-selectable accent color. The choice is stored in UserDefaults (and
//  surfaced in the iOS Settings app via Settings.bundle, key "accentColorID").
//  `Glass.accent` / `accent2` / `accent3` read from the current palette, so the
//  whole app re-tints when the selection changes.
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
		AccentPalette(id: "classicRed",  name: "Classic Red",  accent: Color(hex: "#B23A2F"), accent2: Color(hex: "#8C2C24"), accent3: Color(hex: "#8A6D4F")),
		AccentPalette(id: "cobaltBlue",  name: "Cobalt Blue",  accent: Color(hex: "#2D5BFF"), accent2: Color(hex: "#1E3FB0"), accent3: Color(hex: "#5E6E8C")),
		AccentPalette(id: "forestGreen", name: "Forest Green", accent: Color(hex: "#3E7D5A"), accent2: Color(hex: "#2C5C42"), accent3: Color(hex: "#6E7A5E")),
		AccentPalette(id: "plum",        name: "Plum",         accent: Color(hex: "#7A3E8C"), accent2: Color(hex: "#5C2C6B"), accent3: Color(hex: "#7C6A80")),
		AccentPalette(id: "amber",       name: "Amber",        accent: Color(hex: "#C0801C"), accent2: Color(hex: "#946012"), accent3: Color(hex: "#8A7558")),
		AccentPalette(id: "graphite",    name: "Graphite",     accent: Color(hex: "#454545"), accent2: Color(hex: "#262626"), accent3: Color(hex: "#7A7A7A")),
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
