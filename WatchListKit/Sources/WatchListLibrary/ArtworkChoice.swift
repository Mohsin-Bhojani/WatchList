//
//  ArtworkChoice.swift
//  WatchListLibrary
//
//  Which titles have artwork chosen by hand, by slot. The Artwork sheet
//  (ArtworkPicker.swift, in the app) remembers a pick here; Home's hero and the
//  daily refresh read it, so a picture you chose isn't replaced.
//

import Foundation
import WatchListCore

/// Which of a title's two pictures: the portrait poster or the landscape one.
/// The gallery side of it — which TMDb images suit each — is in the app.
public enum ArtworkSlot: String, CaseIterable {
	case poster, landscape
}

/// Which titles have artwork chosen by hand. Kept out of the models — and so
/// out of the store's schema — since it only decides which picture wins where
/// the app would otherwise pick for itself.
public enum ArtworkChoice {
	public static func chosen(_ slot: ArtworkSlot, for id: UUID) -> Bool {
		ids(slot).contains(id.uuidString)
	}

	public static func remember(_ slot: ArtworkSlot, for id: UUID) {
		var chosen = ids(slot)
		chosen.insert(id.uuidString)
		UserDefaults.standard.set(Array(chosen), forKey: key(slot))
	}

	public static func forget(_ slot: ArtworkSlot, for id: UUID) {
		var chosen = ids(slot)
		chosen.remove(id.uuidString)
		UserDefaults.standard.set(Array(chosen), forKey: key(slot))
	}

	private static func key(_ slot: ArtworkSlot) -> String { "artworkChosen-\(slot.rawValue)" }

	private static func ids(_ slot: ArtworkSlot) -> Set<String> {
		Set(UserDefaults.standard.stringArray(forKey: key(slot)) ?? [])
	}
}
