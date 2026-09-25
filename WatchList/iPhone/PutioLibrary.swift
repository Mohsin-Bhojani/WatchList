//
//  PutioLibrary.swift
//  WatchList
//
//  Your put.io files, a folder at a time, in the title pages' dark style:
//    - On put.io, from its card on the Collections tab: folders open, videos
//      play (resuming where you stopped)
//    - linking, from a show's or film's "…" menu: the same folders, with
//      "Link this folder" for a show, or a tap on a video for a film
//

import SwiftUI

/// What a put.io page is for.
enum PutioBrowseMode {
	case browse
	/// A show's folder: every folder offers itself.
	case pickFolder((PutioFile) -> Void)
	/// A film's video: a tap on a video chooses it.
	case pickVideo((PutioFile) -> Void)
}

struct PutioFolderView: View {
	/// Nil for the account's top level.
	let folder: PutioFile?
	let mode: PutioBrowseMode

	@State private var files: [PutioFile]?
	@State private var failure: String?
	@State private var starting: Int?
	@State private var playFailure: String?
	@State private var compactBar = false

	var body: some View {
		ScrollView {
			VStack(alignment: .leading, spacing: 14) {
				if case .pickFolder(let pick) = mode, let folder {
					Button {
						Haptics.success()
						pick(folder)
					} label: {
						Label("Link \u{201C}\(folder.name)\u{201D}", systemImage: "link")
							.font(.system(size: 16, weight: .semibold))
							.foregroundStyle(.black)
							.lineLimit(1)
							.padding(.horizontal, 16)
							.frame(maxWidth: .infinity, minHeight: GlassControl.height)
							.background(.white, in: Capsule())
					}
					.buttonStyle(.pressable)
				}
				content
			}
			.padding(.horizontal, 18)
			.padding(.top, 8)
			.padding(.bottom, 32)
			.readableColumn()
		}
		.onScrollGeometryChange(for: Bool.self) { geometry in
			geometry.contentOffset.y + geometry.contentInsets.top > 8
		} action: { _, scrolled in
			withAnimation(.easeInOut(duration: 0.2)) { compactBar = scrolled }
		}
		.navigationTitle(folder?.name ?? "put.io")
		.titlePage(color: nil, compactBar: compactBar)
		.task { await load() }
		.refreshable { await load() }
		.alert("Can't play this", isPresented: Binding(get: { playFailure != nil }, set: { if !$0 { playFailure = nil } })) {
			Button("OK", role: .cancel) {}
		} message: {
			Text(playFailure ?? "")
		}
	}

	@ViewBuilder private var content: some View {
		if let files {
			let shown = files.filter { $0.isFolder || $0.isVideo }
			if shown.isEmpty {
				PutioNote(text: "No folders or videos here.")
			} else {
				VStack(spacing: 0) {
					ForEach(Array(shown.enumerated()), id: \.element.id) { index, file in
						if index > 0 { PageRowDivider() }
						row(file)
					}
				}
				.padding(.vertical, 4)
				.liquidCard(cornerRadius: 20)
			}
		} else if let failure {
			PutioNote(text: failure)
		} else {
			ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.top, 40)
		}
	}

	@ViewBuilder private func row(_ file: PutioFile) -> some View {
		if file.isFolder {
			NavigationLink { PutioFolderView(folder: file, mode: mode) } label: {
				PutioRow(file: file, trailing: "chevron.right", loading: false)
			}
			.buttonStyle(.pressable)
		} else {
			switch mode {
			case .browse:
				Button { play(file) } label: {
					PutioRow(file: file, trailing: "play.circle", loading: starting == file.id)
				}
				.buttonStyle(.pressable)
				.disabled(starting != nil)
				.accessibilityHint("Plays it")
			case .pickVideo(let pick):
				Button {
					Haptics.success()
					pick(file)
				} label: {
					PutioRow(file: file, trailing: "link", loading: false)
				}
				.buttonStyle(.pressable)
				.accessibilityHint("Links it")
			case .pickFolder:
				PutioRow(file: file, trailing: nil, loading: false)
					.opacity(0.55)
			}
		}
	}

	private func play(_ file: PutioFile) {
		Haptics.tap()
		starting = file.id
		Task {
			do {
				let stream = try await PutioSession.shared.stream(for: file, title: file.name, subtitle: folder?.name)
				MediaPlayer.play(stream)
			} catch {
				playFailure = error.localizedDescription
			}
			starting = nil
		}
	}

	private func load() async {
		do {
			let list = try await PutioSession.shared.files(in: folder?.id ?? 0)
			failure = nil
			withAnimation(Glass.smooth) { files = list }
		} catch is CancellationError {
		} catch {
			if files == nil { failure = "Couldn't reach put.io: \(error.localizedDescription)" }
		}
	}
}

/// A folder or video: a frame from it, or a folder icon; its name and size.
private struct PutioRow: View {
	let file: PutioFile
	let trailing: String?
	let loading: Bool

	var body: some View {
		HStack(spacing: 12) {
			ZStack {
				if file.isFolder {
					RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.08))
					Image(systemName: "folder.fill")
						.font(.system(size: 20))
						.foregroundStyle(.white.opacity(0.8))
				} else {
					PosterImage(urlString: file.screenshot ?? "", systemPlaceholder: "film")
				}
				if loading {
					Color.black.opacity(0.4)
					ProgressView().tint(.white)
				}
			}
			.frame(width: file.isFolder ? 44 : 78, height: 44)
			.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
			VStack(alignment: .leading, spacing: 3) {
				Text(file.name)
					.font(.system(size: 14, weight: .semibold))
					.foregroundStyle(.white)
					.lineLimit(2)
					.multilineTextAlignment(.leading)
				if !file.isFolder, let size = file.size {
					Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
						.font(.system(size: 12, weight: .medium))
						.foregroundStyle(.white.opacity(0.6))
				}
			}
			Spacer(minLength: 0)
			if let trailing {
				Image(systemName: trailing)
					.font(.system(size: trailing == "chevron.right" ? 13 : 20, weight: .semibold))
					.foregroundStyle(.white.opacity(0.7))
			}
		}
		.padding(.horizontal, 12)
		.padding(.vertical, 10)
		.contentShape(Rectangle())
		.accessibilityElement(children: .combine)
	}
}

private struct PutioNote: View {
	let text: String

	var body: some View {
		Text(text)
			.font(.system(size: 14, weight: .medium))
			.foregroundStyle(.white.opacity(0.75))
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(16)
			.liquidCard(cornerRadius: 20)
	}
}

// MARK: - Linking

/// Choosing a show's folder or a film's video, from its "…" menu.
struct PutioLinkSheet: View {
	enum Kind { case show, film }

	let kind: Kind
	let titleID: UUID

	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			PutioFolderView(folder: nil, mode: kind == .show ? .pickFolder(link) : .pickVideo(link))
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button("Cancel") { dismiss() }
					}
					ToolbarItem(placement: .principal) {
						Text(kind == .show ? "Choose the show's folder" : "Choose the film's video")
							.font(.system(size: 15, weight: .semibold))
							.foregroundStyle(.white)
					}
				}
		}
	}

	private func link(_ file: PutioFile) {
		PutioLinks.shared.set(PutioLink(fileID: file.id, name: file.name, isFolder: file.isFolder), for: titleID)
		dismiss()
	}
}

/// The "…" menu's put.io items: link, or show what's linked and unlink.
struct PutioLinkMenuItems: View {
	let titleID: UUID
	let kind: PutioLinkSheet.Kind
	let choose: () -> Void

	var body: some View {
		if PutioSession.shared.isConnected {
			if let link = PutioLinks.shared.link(titleID) {
				Menu {
					Button { choose() } label: { Label("Change…", systemImage: "arrow.triangle.swap") }
					Button(role: .destructive) { PutioLinks.shared.set(nil, for: titleID) } label: {
						Label("Unlink", systemImage: "link.badge.minus")
					}
				} label: {
					Label("put.io: \(link.name)", systemImage: "link")
				}
			} else {
				Button { choose() } label: {
					Label(kind == .show ? "Link put.io folder…" : "Link put.io video…", systemImage: "link")
				}
			}
		}
	}
}
