//
//  SettingsView.swift
//  WatchList
//
//  In-app settings: accent color, the watched-cascade toggle, and about info.
//  Preferences are stored in UserDefaults (the same keys the app already uses),
//  so changes take effect immediately app-wide.
//

import SwiftData
import SwiftUI

struct SettingsView: View {
	@Environment(\.dismiss) private var dismiss
	@ObservedObject private var theme = AppTheme.shared
	@AppStorage("autoMarkEpisodesWatched") private var autoMarkEpisodes = true
	@AppStorage("similarProxyHost") private var proxyHost = "127.0.0.1"
	@AppStorage("similarProxyPort") private var proxyPort = 8787
	@AppStorage("similarProxyToken") private var proxyToken = ""
	@AppStorage("autoCheckNewEpisodes") private var autoCheckEpisodes = true

	@Environment(\.modelContext) private var ctx
	@Query private var shows: [Show]
	@State private var checking = false
	@State private var checkResult: String?

	/// nil = not tested yet, so the row stays neutral until you ask.
	@State private var probeResult: Bool?
	@State private var probing = false

	private let columns = [GridItem(.adaptive(minimum: 96), spacing: 12)]

	var body: some View {
		NavigationStack {
			ZStack {
				GlassBackground()
				ScrollView {
					VStack(alignment: .leading, spacing: 22) {
						appearanceSection
						episodesSection
						newEpisodesSection
						similarSection
						aboutSection
					}
					.padding(18)
				}
			}
			.navigationTitle("Settings")
			.navigationBarTitleDisplayMode(.inline)
			.toolbarBackground(.hidden, for: .navigationBar)
			.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
		}
	}

	// MARK: Accent

	private var appearanceSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "Accent Color", systemImage: "paintpalette.fill")
			LazyVGrid(columns: columns, spacing: 12) {
				ForEach(AccentCatalog.all) { swatch($0) }
			}
		}
	}

	private func swatch(_ palette: AccentPalette) -> some View {
		let selected = theme.accentID == palette.id
		return Button {
			Haptics.selection()
			withAnimation(Glass.pop) { theme.setAccent(palette.id) }
		} label: {
			VStack(spacing: 8) {
				ZStack {
					Circle().fill(palette.accent).frame(width: 34, height: 34)
					if selected {
						Image(systemName: "checkmark")
							.font(.system(size: 14, weight: .bold))
							.foregroundStyle(.white)
					}
				}
				Text(palette.name)
					.font(.system(size: 11, weight: .semibold, design: .rounded))
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			.frame(maxWidth: .infinity)
			.padding(.vertical, 13)
			.background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Glass.surface))
			.overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
				.strokeBorder(selected ? palette.accent : Glass.hairline.opacity(0.16), lineWidth: selected ? 2 : 1))
		}
		.buttonStyle(.pressable)
	}

	// MARK: Episodes

	private var episodesSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "Episodes", systemImage: "list.and.film")
			VStack(alignment: .leading, spacing: 8) {
				Toggle(isOn: $autoMarkEpisodes) {
					Text("Mark all episodes watched")
						.font(.system(size: 15, weight: .semibold, design: .rounded))
				}
				.tint(Glass.accent)
				Text("When you set a show or season to Watched, mark every episode watched too.")
					.font(.system(size: 12, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
			}
			.padding(16)
			.glass(cornerRadius: 18)
		}
	}

	// MARK: New episodes

	private var newEpisodesSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "New Episodes", systemImage: "arrow.triangle.2.circlepath")
			VStack(alignment: .leading, spacing: 10) {
				Toggle(isOn: $autoCheckEpisodes) {
					Text("Check automatically")
						.font(.system(size: 15, weight: .semibold, design: .rounded))
				}
				.tint(Glass.accent)
				Text("Looks for new seasons and episodes once a day. Only ever adds — your watched marks and ratings are never changed.")
					.font(.system(size: 12, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)

				Divider().opacity(0.4)

				HStack(spacing: 10) {
					Button {
						Haptics.tap()
						checkNow()
					} label: {
						Text(checking ? "Checking…" : "Check now")
							.font(.system(size: 14, weight: .semibold, design: .rounded))
					}
					.buttonStyle(.pressable)
					.disabled(checking || shows.isEmpty)

					if checking { ProgressView().controlSize(.small) }
					Spacer()
				}

				if let checkResult {
					Text(checkResult)
						.font(.system(size: 12, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
				} else if let last = LibraryRefresher.lastChecked {
					Text("Last checked \(last.formatted(.relative(presentation: .named))).")
						.font(.system(size: 12, weight: .medium, design: .rounded))
						.foregroundStyle(.secondary)
				}
			}
			.padding(16)
			.glass(cornerRadius: 18)
		}
	}

	private func checkNow() {
		checking = true
		checkResult = nil
		Task {
			let report = await LibraryRefresher.refreshAll(shows: shows, into: ctx)
			checking = false
			checkResult = report.summary
			report.foundSomething ? Haptics.success() : Haptics.tap()
		}
	}

	// MARK: Similar

	private var similarSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "Similar", systemImage: "sparkles")
			VStack(alignment: .leading, spacing: 12) {
				field("Mac address", text: $proxyHost, placeholder: "127.0.0.1")
					.keyboardType(.numbersAndPunctuation)
				field("Port", text: portText, placeholder: "8787")
					.keyboardType(.numberPad)
				secureField("Token", text: $proxyToken, placeholder: "Only if not on 127.0.0.1")

				Divider().opacity(0.4)

				HStack(spacing: 10) {
					Button {
						Haptics.tap()
						probe()
					} label: {
						Text(probing ? "Testing…" : "Test connection")
							.font(.system(size: 14, weight: .semibold, design: .rounded))
					}
					.buttonStyle(.pressable)
					.disabled(probing)

					if probing {
						ProgressView().controlSize(.small)
					} else if let ok = probeResult {
						Label(ok ? "Reachable" : "No answer", systemImage: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
							.font(.system(size: 13, weight: .semibold, design: .rounded))
							.foregroundStyle(ok ? Glass.watched : Glass.ratingSkip)
					}
					Spacer()
				}

				Text("Suggestions are generated on your Mac, which holds the API key. Use 127.0.0.1 in the Simulator, or your Mac's Wi-Fi address on a device.")
					.font(.system(size: 12, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
			}
			.padding(16)
			.glass(cornerRadius: 18)
		}
	}

	/// Port is an Int in storage but a String in the field; bridged here so the
	/// field can be emptied mid-edit without resetting to 0.
	private var portText: Binding<String> {
		Binding(
			get: { proxyPort > 0 ? String(proxyPort) : "" },
			set: { proxyPort = Int($0.filter(\.isNumber)) ?? 0 }
		)
	}

	private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
		HStack(spacing: 10) {
			Text(label)
				.font(.system(size: 15, weight: .semibold, design: .rounded))
				.frame(width: 108, alignment: .leading)
			TextField(placeholder, text: text)
				.font(.system(size: 15, weight: .medium, design: .rounded))
				.multilineTextAlignment(.trailing)
				.autocorrectionDisabled()
				.textInputAutocapitalization(.never)
				.onChange(of: text.wrappedValue) { _, _ in probeResult = nil }
		}
	}

	private func secureField(_ label: String, text: Binding<String>, placeholder: String) -> some View {
		HStack(spacing: 10) {
			Text(label)
				.font(.system(size: 15, weight: .semibold, design: .rounded))
				.frame(width: 108, alignment: .leading)
			SecureField(placeholder, text: text)
				.font(.system(size: 15, weight: .medium, design: .rounded))
				.multilineTextAlignment(.trailing)
				.onChange(of: text.wrappedValue) { _, _ in probeResult = nil }
		}
	}

	private func probe() {
		probing = true
		probeResult = nil
		Task {
			let ok = await SuggestionService.shared.health()
			probing = false
			probeResult = ok
			ok ? Haptics.success() : Haptics.warning()
		}
	}

	// MARK: About

	private var aboutSection: some View {
		VStack(alignment: .leading, spacing: 12) {
			SectionLabel(text: "About", systemImage: "info.circle.fill")
			VStack(alignment: .leading, spacing: 10) {
				HStack {
					Text("Version").font(.system(size: 15, weight: .semibold, design: .rounded))
					Spacer()
					Text(appVersion).font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
				}
				Divider().opacity(0.4)
				Text("Titles, posters and details are from TMDb. This product uses the TMDb API but is not endorsed or certified by TMDb.")
					.font(.system(size: 12, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
			}
			.padding(16)
			.glass(cornerRadius: 18)
		}
	}

	private var appVersion: String {
		let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
		let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
		return "\(v) (\(b))"
	}
}
