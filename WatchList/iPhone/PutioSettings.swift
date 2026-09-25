//
//  PutioSettings.swift
//  WatchList
//
//  Settings' put.io section: connecting your account with the OAuth token put.io
//  gives an app you register there — how to get one is on the card — and,
//  once connected, whose account it is and how many titles are linked, with
//  Disconnect. Links stay when you disconnect, for when you connect again.
//

import SwiftUI

struct PutioSettingsSection: View {
	@State private var token = ""
	@State private var working = false
	@State private var note: String?

	private var session: PutioSession { .shared }

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "put.io", systemImage: "icloud.fill")
			VStack(alignment: .leading, spacing: 10) {
				if session.isConnected, let userName = session.userName {
					connected(userName)
				} else {
					connectForm
				}
				if let note {
					Text(note)
						.font(.system(size: 13, weight: .medium))
						.foregroundStyle(.secondary)
				}
			}
			.padding(16)
			.glass(cornerRadius: 22)
		}
	}

	private func connected(_ userName: String) -> some View {
		let linked = PutioLinks.shared.links.count
		return VStack(alignment: .leading, spacing: 10) {
			HStack {
				VStack(alignment: .leading, spacing: 2) {
					Text(userName)
						.font(.system(size: 16, weight: .semibold))
						.foregroundStyle(Glass.ink)
					Text(linked == 0 ? "Nothing linked yet" : "\(linked) \(linked == 1 ? "title" : "titles") linked")
						.font(.system(size: 13, weight: .medium))
						.foregroundStyle(.secondary)
				}
				Spacer()
				Image(systemName: "checkmark.circle.fill")
					.foregroundStyle(Glass.accent)
			}
			Text("Link a show to its folder, or a film to its video, from the \u{201C}…\u{201D} menu on its page. Episodes are found by the S01E03 in their file names.")
				.font(.system(size: 13, weight: .medium))
				.foregroundStyle(.secondary)
			Rectangle()
				.fill(Glass.hairline.opacity(0.12))
				.frame(height: 1)
			Button(role: .destructive) {
				Haptics.tap()
				note = nil
				session.disconnect()
			} label: {
				Text("Disconnect")
					.font(.system(size: 15, weight: .semibold))
					.foregroundStyle(.red)
			}
			.buttonStyle(.pressable)
		}
	}

	private var connectForm: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("Play videos from your put.io account. To connect: on app.put.io, open Settings → Account → OAuth Apps, create an app (any name will do) and copy its OAuth token here.")
				.font(.system(size: 13, weight: .medium))
				.foregroundStyle(.secondary)
			Link(destination: URL(string: "https://app.put.io/settings/account/oauth/apps")!) {
				Label("Open put.io's OAuth Apps", systemImage: "arrow.up.right.square")
					.font(.system(size: 14, weight: .semibold))
					.foregroundStyle(Glass.accent)
			}
			VStack(alignment: .leading, spacing: 4) {
				Text("OAuth token")
					.font(.system(size: 13, weight: .semibold))
					.foregroundStyle(Glass.ink)
				SecureField("Paste the token", text: $token)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()
					.submitLabel(.go)
					.onSubmit(connect)
					.font(.system(size: 16, weight: .medium))
					.foregroundStyle(Glass.ink)
					.padding(.horizontal, 12)
					.padding(.vertical, 10)
					.background(Glass.hairline.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			}
			Button {
				Haptics.tap()
				connect()
			} label: {
				HStack(spacing: 8) {
					Text(working ? "Connecting…" : "Connect")
					if working { ProgressView().controlSize(.small) }
				}
				.font(.system(size: 15, weight: .semibold))
				.foregroundStyle(Glass.accent)
			}
			.buttonStyle(.pressable)
			.disabled(!canConnect)
			.opacity(canConnect ? 1 : 0.45)
			.padding(.top, 2)
		}
	}

	private var canConnect: Bool { !working && !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

	private func connect() {
		guard canConnect else { return }
		working = true
		note = nil
		Task {
			do {
				try await session.connect(token: token)
				token = ""
				Haptics.success()
			} catch {
				note = (error as? LocalizedError)?.errorDescription
					?? "Couldn't reach put.io: \(error.localizedDescription)"
				Haptics.warning()
			}
			working = false
		}
	}
}
