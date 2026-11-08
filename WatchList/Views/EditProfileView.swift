//
//  EditProfileView.swift
//  WatchList
//
//  Editing the profile: name and picture.
//  Split out of ProfileView.swift.
//

import SwiftUI
import SwiftData
import PhotosUI
import WatchListCore
import WatchListLibrary

// MARK: - Edit

/// Customise Your Profile. Edits are a draft: ✓ keeps them, ✕ leaves the
/// profile as it was.
struct EditProfileView: View {
	@Environment(\.dismiss) private var dismiss
	@State private var nickname: String
	@State private var avatar: UIImage?
	@State private var photoItem: PhotosPickerItem?
	@State private var choosingPhoto = false

	init() {
		_nickname = State(initialValue: ProfileStore.shared.nickname)
		_avatar = State(initialValue: ProfileStore.shared.avatar)
	}

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 32) {
					VStack(alignment: .leading, spacing: 6) {
						Text("Customise Your Profile")
							.font(.system(.title, weight: .bold))
						Text("Set your identity with an avatar and a nickname.")
							.font(.callout)
							.foregroundStyle(.secondary)
					}

					ProfileAvatar(nickname: nickname, image: avatar, size: 156)
						.overlay(alignment: .bottomTrailing) {
							avatarMenu
								.offset(x: -2, y: -2)
						}
						.frame(maxWidth: .infinity)

					HStack(spacing: 14) {
						Text("Nickname")
							.foregroundStyle(.secondary)
						TextField("Add a nickname", text: $nickname)
							.textInputAutocapitalization(.words)
							.autocorrectionDisabled()
							.submitLabel(.done)
					}
					.font(.system(.body, weight: .medium))
					.padding(.horizontal, 20)
					.padding(.vertical, 15)
					.glass(cornerRadius: 26)
				}
				.padding(.horizontal, 24)
				.padding(.top, 8)
			}
			.scrollDismissesKeyboard(.interactively)
			.background(GlassBackground())
			.toolbarBackground(.hidden, for: .navigationBar)
			.toolbar {
				ToolbarItem(placement: .topBarLeading) {
					Button { dismiss() } label: {
						Image(systemName: "xmark")
					}
					.accessibilityLabel("Cancel")
				}
				ToolbarItem(placement: .topBarTrailing) {
					Button(action: save) {
						Image(systemName: "checkmark")
					}
					.accessibilityLabel("Save")
				}
			}
		}
		.photosPicker(isPresented: $choosingPhoto, selection: $photoItem, matching: .images)
		.onChange(of: photoItem) { _, item in
			guard let item else { return }
			Task {
				if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
					avatar = ProfileStore.squared(image, side: ProfileStore.avatarSide)
				}
				// Cleared so picking the same photo again still counts as a change.
				photoItem = nil
			}
		}
	}

	/// The pencil on the avatar's edge: choose a photo, or go back to the
	/// initial.
	private var avatarMenu: some View {
		Menu {
			Button { choosingPhoto = true } label: {
				Label("Choose Photo", systemImage: "photo")
			}
			if avatar != nil {
				Button(role: .destructive) { avatar = nil } label: {
					Label("Remove Photo", systemImage: "trash")
				}
			}
		} label: {
			Image(systemName: "pencil")
				.font(.system(.body, weight: .semibold))
				.foregroundStyle(.white)
				.frame(width: 44, height: 44)
				.background(Circle().fill(Glass.accent))
				.overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
				.shadow(color: .black.opacity(0.3), radius: 6, y: 3)
		}
		.accessibilityLabel("Change avatar")
	}

	private func save() {
		ProfileStore.shared.save(nickname: nickname, avatar: avatar)
		Haptics.success()
		dismiss()
	}
}
