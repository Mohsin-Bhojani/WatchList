//
//  NearbyView.swift
//  WatchList
//
//  The sharing hub: find nearby devices and Share (which exchanges watched
//  lists both ways), and browse the lists other devices have shared with you.
//  A received list opens as an overlay where each title can be adopted into
//  your own library.
//

import SwiftUI
import SwiftData
import MultipeerConnectivity

struct NearbyView: View {
	@Environment(\.modelContext) private var ctx
	@Environment(\.dismiss) private var dismiss
	@StateObject private var peer = PeerSyncService()
	@Query(sort: \SharedLibrary.receivedAt, order: .reverse) private var shared: [SharedLibrary]
	@State private var openLibrary: SharedLibrary?
	@State private var myName = PeerSyncService.deviceName()
	@FocusState private var nameFocused: Bool

	var body: some View {
		NavigationStack {
			ZStack {
				GlassBackground()
				ScrollView {
					VStack(alignment: .leading, spacing: 22) {
						identitySection
						nearbySection
						sharedSection
					}
					.padding(18)
				}
			}
			.navigationTitle("Nearby")
			.navigationBarTitleDisplayMode(.inline)
			.toolbarBackground(.hidden, for: .navigationBar)
			.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
			.sheet(item: $openLibrary) { SharedLibrarySheet(library: $0) }
		}
		.onAppear {
			peer.snapshotProvider = { LibrarySnapshot.build(ownerName: peer.myName, context: ctx) }
			peer.onReceive = { receive($0) }
			peer.start()
		}
		.onDisappear { peer.stop() }
	}

	// MARK: Your name

	private var identitySection: some View {
		VStack(alignment: .leading, spacing: 10) {
			SectionLabel(text: "Your Name", systemImage: "person.crop.circle")
			HStack(spacing: 8) {
				TextField("Your name", text: $myName)
					.font(.system(size: 15, weight: .medium, design: .rounded))
					.autocorrectionDisabled()
					.submitLabel(.done)
					.focused($nameFocused)
					.onSubmit { peer.rename(to: myName); nameFocused = false }
				if nameFocused {
					Button("Save") { peer.rename(to: myName); nameFocused = false }
						.font(.system(size: 14, weight: .bold, design: .rounded))
						.foregroundStyle(Glass.accent)
				}
			}
			.padding(15)
			.glass(cornerRadius: 16)
			Text("How you appear to nearby devices.")
				.font(.system(size: 12, weight: .medium, design: .rounded))
				.foregroundStyle(.secondary)
		}
	}

	// MARK: Nearby devices

	private var nearbySection: some View {
		VStack(alignment: .leading, spacing: 10) {
			SectionLabel(text: "Nearby Devices", systemImage: "dot.radiowaves.left.and.right")
			VStack(spacing: 0) {
				if peer.discoveredPeers.isEmpty {
					HStack(spacing: 10) {
						ProgressView()
						Text("Searching for nearby devices…")
							.font(.system(size: 14, weight: .medium, design: .rounded))
							.foregroundStyle(.secondary)
						Spacer()
					}
					.padding(.vertical, 6)
				} else {
					ForEach(Array(peer.discoveredPeers.enumerated()), id: \.element) { index, p in
						if index > 0 { Divider().opacity(0.4) }
						deviceRow(p)
					}
				}
			}
			.padding(16)
			.glass(cornerRadius: 18)
			Text("Connecting also shares the titles you've watched.")
				.font(.system(size: 12, weight: .medium, design: .rounded))
				.foregroundStyle(.secondary)
		}
	}

	private func deviceRow(_ p: MCPeerID) -> some View {
		HStack(spacing: 11) {
			Image(systemName: "iphone.gen3")
				.font(.system(size: 19, weight: .semibold))
				.foregroundStyle(Glass.accent)
			VStack(alignment: .leading, spacing: 1) {
				Text(p.displayName)
					.font(.system(size: 15, weight: .semibold, design: .rounded))
				Text("Ready to receive")
					.font(.system(size: 12, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
			}
			Spacer()
			if peer.connecting.contains(p) {
				ProgressView()
			} else {
				Button { peer.share(with: p) } label: {
					Text("Share")
						.font(.system(size: 13, weight: .bold, design: .rounded))
						.foregroundStyle(.white)
						.padding(.horizontal, 16).padding(.vertical, 7)
						.background(Capsule().fill(Glass.accent))
				}
				.buttonStyle(.pressable)
			}
		}
		.padding(.vertical, 8)
	}

	// MARK: Shared with you

	private var sharedSection: some View {
		VStack(alignment: .leading, spacing: 10) {
			SectionLabel(text: "Shared With You", systemImage: "tray.and.arrow.down.fill")
			if shared.isEmpty {
				Text("Lists you receive from nearby devices will appear here.")
					.font(.system(size: 14, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(16).glass(cornerRadius: 18)
			} else {
				ForEach(shared) { lib in
					Button { openLibrary = lib } label: { sharedRow(lib) }
						.buttonStyle(.pressable)
						.contextMenu {
							Button(role: .destructive) { withAnimation { ctx.delete(lib) } } label: {
								Label("Remove", systemImage: "trash")
							}
						}
				}
			}
		}
	}

	private func sharedRow(_ lib: SharedLibrary) -> some View {
		HStack(spacing: 12) {
			Text(String(lib.ownerName.prefix(1)).uppercased())
				.font(.system(size: 15, weight: .bold, design: .rounded))
				.foregroundStyle(Glass.accent)
				.frame(width: 36, height: 36)
				.background(Glass.accent.opacity(0.14), in: Circle())
			Text(lib.ownerName)
				.font(.system(size: 15, weight: .semibold, design: .rounded))
				.foregroundStyle(.primary)
			Spacer()
			Image(systemName: "chevron.right")
				.font(.system(size: 13, weight: .bold))
				.foregroundStyle(.tertiary)
		}
		.padding(.vertical, 12).padding(.horizontal, 14)
		.glass(cornerRadius: 18)
	}

	// MARK: Receiving

	private func receive(_ snapshot: LibrarySnapshot) {
		let data = (try? JSONEncoder.snapshot.encode(snapshot)) ?? Data()
		if let existing = shared.first(where: { $0.peerID == snapshot.ownerName }) {
			existing.ownerName = snapshot.ownerName
			existing.data = data
			existing.receivedAt = .now
		} else {
			ctx.insert(SharedLibrary(peerID: snapshot.ownerName, ownerName: snapshot.ownerName, data: data))
		}
		Haptics.success()
	}
}

// MARK: - Received list overlay

struct SharedLibrarySheet: View {
	@Environment(\.modelContext) private var ctx
	@Environment(\.dismiss) private var dismiss
	@Query private var shows: [Show]
	@Query private var films: [Film]
	@State private var adopting: Set<String> = []

	let library: SharedLibrary

	var body: some View {
		NavigationStack {
			ZStack {
				GlassBackground()
				ScrollView {
					VStack(alignment: .leading, spacing: 10) {
						if library.titles.isEmpty {
							EmptyState(icon: "tv", title: "Nothing shared",
							           subtitle: "\(library.ownerName) hasn't marked anything watched yet.")
								.padding(.top, 44)
						} else {
							ForEach(library.titles) { title in
								row(title)
							}
						}
						Color.clear.frame(height: 20)
					}
					.padding(18)
				}
			}
			.navigationTitle(library.ownerName)
			.navigationBarTitleDisplayMode(.inline)
			.toolbarBackground(.hidden, for: .navigationBar)
			.toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
		}
	}

	private func row(_ t: SharedTitle) -> some View {
		HStack(spacing: 11) {
			poster(t)
				.frame(width: 44, height: 63)
				.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
			VStack(alignment: .leading, spacing: 3) {
				Text(t.title)
					.font(.system(size: 15, weight: .semibold, design: .rounded))
					.foregroundStyle(.primary)
					.lineLimit(2)
				Text([t.year, t.genre].filter { !$0.isEmpty }.joined(separator: " · "))
					.font(.system(size: 12, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
				if let rating = t.ratingValue {
					RatingBadge(rating: rating, compact: false)
						.padding(.top, 1)
				}
			}
			Spacer(minLength: 6)
			adoptControl(t)
		}
		.padding(10)
		.glass(cornerRadius: 16)
	}

	@ViewBuilder private func poster(_ t: SharedTitle) -> some View {
		if let data = t.posterData, let image = UIImage(data: data) {
			Image(uiImage: image).resizable().scaledToFill()
		} else {
			PosterImage(urlString: t.posterURL, systemPlaceholder: t.mediaKind == .show ? "tv" : "film")
		}
	}

	@ViewBuilder private func adoptControl(_ t: SharedTitle) -> some View {
		if adopting.contains(t.id) {
			ProgressView()
		} else if inLibrary(t) {
			HStack(spacing: 4) {
				Image(systemName: "checkmark")
				Text("Added")
			}
			.font(.system(size: 12, weight: .semibold, design: .rounded))
			.foregroundStyle(Glass.watched)
		} else {
			Button { adopt(t) } label: {
				Image(systemName: "plus")
					.font(.system(size: 18, weight: .bold))
					.foregroundStyle(.white)
					.frame(width: 34, height: 34)
					.background(Circle().fill(Glass.accent))
			}
			.buttonStyle(.pressable)
		}
	}

	// MARK: Adopt

	private func inLibrary(_ t: SharedTitle) -> Bool {
		switch t.mediaKind {
		case .show: return shows.contains { matches(t, tmdbID: $0.tmdbID, imdbID: $0.imdbID) }
		case .film: return films.contains { matches(t, tmdbID: $0.tmdbID, imdbID: $0.imdbID) }
		}
	}

	private func matches(_ t: SharedTitle, tmdbID: Int?, imdbID: String?) -> Bool {
		if let a = t.tmdbID, let b = tmdbID, a == b { return true }
		if let a = t.imdbID, !a.isEmpty, a == imdbID { return true }
		return false
	}

	/// Adds the title to your own library — re-fetched fresh, so it lands as
	/// "To Watch" and unrated (their rating stays theirs).
	private func adopt(_ t: SharedTitle) {
		adopting.insert(t.id)
		Haptics.tap(.medium)
		Task {
			let importer = ImportCoordinator()
			if let tmdbID = t.tmdbID {
				_ = await importer.importFromTMDb(id: tmdbID, kind: t.mediaKind, into: ctx)
			} else if let imdbID = t.imdbID, !imdbID.isEmpty {
				_ = await importer.importFromIMDb(imdbID, into: ctx)
			} else {
				buildManual(t)
			}
			adopting.remove(t.id)
			Haptics.success()
		}
	}

	private func buildManual(_ t: SharedTitle) {
		switch t.mediaKind {
		case .show:
			let show = Show(title: t.title, genre: t.genre, firstAirYear: t.year, imdbID: t.imdbID)
			if let data = t.posterData, let path = ManualPosterStore.save(data) { show.posterURL = path }
			ctx.insert(show)
		case .film:
			let film = Film(title: t.title, genre: t.genre, year: t.year, imdbID: t.imdbID)
			if let data = t.posterData, let path = ManualPosterStore.save(data) { film.posterURL = path }
			ctx.insert(film)
		}
	}
}
