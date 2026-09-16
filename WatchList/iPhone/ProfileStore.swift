//
//  ProfileStore.swift
//  WatchList
//
//  Your profile on this iPhone — a nickname and an optional avatar photo — and
//  the round avatar that shows them. Kept outside SwiftData: the nickname in
//  UserDefaults, the photo as a small JPEG in Documents/Profile, so saving a
//  profile never touches the library store.
//

import SwiftUI
import UIKit
import Combine

@MainActor
final class ProfileStore: ObservableObject {
	static let shared = ProfileStore()

	/// Long enough for any real name, short enough to fit the header.
	static let maxNicknameLength = 30
	/// Saved avatars are cropped square and scaled to this many pixels a side.
	static let avatarSide: CGFloat = 512

	@Published private(set) var nickname: String
	@Published private(set) var avatar: UIImage?

	private let defaults: UserDefaults
	private let avatarURL: URL
	private static let nicknameKey = "profileNickname"

	/// Nonisolated: it's only a path, and `init` uses it as a default argument.
	nonisolated static var defaultDirectory: URL {
		let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
		return documents.appendingPathComponent("Profile", isDirectory: true)
	}

	init(defaults: UserDefaults = .standard, directory: URL = ProfileStore.defaultDirectory) {
		self.defaults = defaults
		avatarURL = directory.appendingPathComponent("avatar.jpg")
		nickname = defaults.string(forKey: Self.nicknameKey) ?? ""
		avatar = (try? Data(contentsOf: avatarURL)).flatMap { UIImage(data: $0) }
	}

	/// Keeps an edited profile. The photo is written only when it's a new one;
	/// nil removes the saved photo.
	func save(nickname: String, avatar: UIImage?) {
		let cleaned = Self.cleaned(nickname)
		defaults.set(cleaned, forKey: Self.nicknameKey)
		self.nickname = cleaned

		guard let avatar else {
			try? FileManager.default.removeItem(at: avatarURL)
			self.avatar = nil
			return
		}
		guard avatar !== self.avatar else { return }
		let square = Self.squared(avatar, side: Self.avatarSide)
		do {
			try FileManager.default.createDirectory(at: avatarURL.deletingLastPathComponent(),
			                                        withIntermediateDirectories: true)
			guard let data = square.jpegData(compressionQuality: 0.85) else { return }
			try data.write(to: avatarURL, options: .atomic)
			self.avatar = square
		} catch {
			// Keep showing the previous photo rather than one that won't be there next launch.
		}
	}

	/// Trimmed and capped, so a pasted paragraph doesn't become a nickname.
	static func cleaned(_ raw: String) -> String {
		String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxNicknameLength))
	}

	/// The letter the avatar shows, or nil when there's no nickname to take it from.
	static func initial(of nickname: String) -> String? {
		cleaned(nickname).first.map { String($0).uppercased() }
	}

	/// A centre-cropped square at `side` pixels, so a saved avatar stays small.
	static func squared(_ image: UIImage, side: CGFloat) -> UIImage {
		let target = CGSize(width: side, height: side)
		if image.size == target && image.scale == 1 { return image }
		let scale = side / max(min(image.size.width, image.size.height), 1)
		let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
		let format = UIGraphicsImageRendererFormat()
		format.scale = 1
		return UIGraphicsImageRenderer(size: target, format: format).image { _ in
			image.draw(in: CGRect(x: (side - drawn.width) / 2, y: (side - drawn.height) / 2,
			                      width: drawn.width, height: drawn.height))
		}
	}
}

// MARK: - Avatar

/// A round avatar: the chosen photo, or the nickname's first letter on a
/// gradient in the accent colour — a person glyph until there's a nickname.
struct ProfileAvatar: View {
	let nickname: String
	let image: UIImage?
	let size: CGFloat

	var body: some View {
		ZStack {
			if let image {
				Image(uiImage: image)
					.resizable()
					.scaledToFill()
			} else {
				LinearGradient(colors: [Glass.accent.opacity(0.7), Glass.accent],
				               startPoint: .top, endPoint: .bottom)
				if let initial = ProfileStore.initial(of: nickname) {
					Text(initial)
						.font(.system(size: size * 0.46, weight: .heavy, design: .rounded))
						.foregroundStyle(.white)
				} else {
					Image(systemName: "person.fill")
						.font(.system(size: size * 0.42, weight: .semibold))
						.foregroundStyle(.white)
				}
			}
		}
		.frame(width: size, height: size)
		.clipShape(Circle())
		// A white ring keeps it apart from the accent-coloured header behind it.
		.overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: max(2, size * 0.028)))
		.shadow(color: .black.opacity(0.25), radius: 16, y: 8)
		.accessibilityHidden(true)
	}
}
