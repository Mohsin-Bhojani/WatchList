//
//  JellyfinSettings.swift
//  WatchList
//
//  Settings' Jellyfin section: signing in to your own server — its address,
//  your Jellyfin username and password — and, once signed in, which server and
//  how many of its titles WatchList found, with Refresh and Sign out. The
//  password goes to the server only; the token it answers with is kept.
//

import SwiftUI

struct JellyfinSettingsSection: View {
	@AppStorage("jellyfinLastServer") private var server = ""
	@AppStorage("jellyfinLastUser") private var userName = ""
	@State private var password = ""
	@State private var working = false
	@State private var note: String?

	private var session: JellyfinSession { .shared }

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "Jellyfin", systemImage: "play.rectangle.fill")
			VStack(alignment: .leading, spacing: 10) {
				if let account = session.account, session.isSignedIn {
					signedIn(account)
				} else {
					signInForm
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

	// MARK: Signed in

	private func signedIn(_ account: JellyfinAccount) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack {
				VStack(alignment: .leading, spacing: 2) {
					Text(account.serverName)
						.font(.system(size: 16, weight: .semibold))
						.foregroundStyle(Glass.ink)
					Text("\(account.userName) · \(account.server.absoluteString)")
						.font(.system(size: 13, weight: .medium))
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.truncationMode(.middle)
				}
				Spacer()
				Image(systemName: "checkmark.circle.fill")
					.foregroundStyle(Glass.accent)
			}
			Text(counts)
				.font(.system(size: 13, weight: .medium))
				.foregroundStyle(.secondary)

			divider

			HStack(spacing: 18) {
				Button {
					Haptics.tap()
					refresh()
				} label: {
					Text(working ? "Refreshing…" : "Refresh")
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(Glass.accent)
				}
				.buttonStyle(.pressable)
				.disabled(working)
				Button(role: .destructive) {
					Haptics.tap()
					note = nil
					session.signOut()
				} label: {
					Text("Sign out")
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(.red)
				}
				.buttonStyle(.pressable)
				if working { ProgressView().controlSize(.small) }
				Spacer()
			}
		}
	}

	private var counts: String {
		guard let index = session.index else {
			return "Film and episode pages show Play for anything on this server."
		}
		let films = "\(index.movieCount) \(index.movieCount == 1 ? "film" : "films")"
		let shows = "\(index.seriesCount) \(index.seriesCount == 1 ? "show" : "shows")"
		return "\(films) and \(shows) on the server. Film and episode pages show Play for anything here."
	}

	private func refresh() {
		working = true
		note = nil
		Task {
			do { try await session.refreshIndex() } catch { note = error.localizedDescription }
			working = false
		}
	}

	// MARK: Signing in

	private var signInForm: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("Play films and episodes from your own Jellyfin server, right on their pages. Titles are matched by their TMDb or IMDb ids, as Jellyfin fetches them.")
				.font(.system(size: 13, weight: .medium))
				.foregroundStyle(.secondary)
			field("Server address", text: $server, placeholder: "192.168.1.20:8096")
				.keyboardType(.URL)
			field("Username", text: $userName, placeholder: "Username")
				.textContentType(.username)
			VStack(alignment: .leading, spacing: 4) {
				fieldLabel("Password")
				SecureField("Password", text: $password)
					.textContentType(.password)
					.submitLabel(.go)
					.onSubmit(signIn)
					.modifier(FieldStyle())
			}

			Button {
				Haptics.tap()
				signIn()
			} label: {
				HStack(spacing: 8) {
					Text(working ? "Signing in…" : "Sign in")
					if working { ProgressView().controlSize(.small) }
				}
				.font(.system(size: 15, weight: .semibold))
				.foregroundStyle(Glass.accent)
			}
			.buttonStyle(.pressable)
			.disabled(!canSignIn)
			.opacity(canSignIn ? 1 : 0.45)
			.padding(.top, 2)
		}
	}

	private var canSignIn: Bool {
		!working && !server.trimmingCharacters(in: .whitespaces).isEmpty
			&& !userName.trimmingCharacters(in: .whitespaces).isEmpty
	}

	private func signIn() {
		guard canSignIn else { return }
		working = true
		note = nil
		Task {
			do {
				try await session.signIn(server: server, userName: userName.trimmingCharacters(in: .whitespaces),
				                         password: password)
				password = ""
				Haptics.success()
			} catch {
				note = (error as? LocalizedError)?.errorDescription
					?? "Couldn't reach the server: \(error.localizedDescription)"
				Haptics.warning()
			}
			working = false
		}
	}

	// MARK: Pieces

	private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
		VStack(alignment: .leading, spacing: 4) {
			fieldLabel(label)
			TextField(placeholder, text: text)
				.textInputAutocapitalization(.never)
				.autocorrectionDisabled()
				.modifier(FieldStyle())
		}
	}

	private func fieldLabel(_ text: String) -> some View {
		Text(text)
			.font(.system(size: 13, weight: .semibold))
			.foregroundStyle(Glass.ink)
	}

	private var divider: some View {
		Rectangle()
			.fill(Glass.hairline.opacity(0.12))
			.frame(height: 1)
	}

	private struct FieldStyle: ViewModifier {
		func body(content: Content) -> some View {
			content
				.font(.system(size: 16, weight: .medium))
				.foregroundStyle(Glass.ink)
				.padding(.horizontal, 12)
				.padding(.vertical, 10)
				.background(Glass.hairline.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
		}
	}
}
