//
//  ProfileView.swift
//  WatchList
//
//  The profile sheet from the header's profile button, and what it opens:
//    - ProfileView: on your accent's colour, the way a title page sits on a
//      poster's — your avatar and nickname, with Edit and Settings either side
//      of it; your verdicts added up, which open Stats; the pinned Top 4
//      collection's posters; and this week's watching, the time each day
//      as a bar and, below it, the titles behind the week or the day tapped
//    - EditProfileView: Customise Your Profile — the avatar with a pencil to
//      choose or remove a photo, and a nickname field
//

import SwiftUI
import SwiftData
import Charts
import PhotosUI

struct ProfileView: View {
	@ObservedObject private var profile = ProfileStore.shared
	/// Watched so the page re-tints when Settings, opened from here, changes
	/// the accent.
	@ObservedObject private var theme = AppTheme.shared
	@Query(sort: \Show.dateAdded, order: .reverse) private var shows: [Show]
	@Query(sort: \Film.dateAdded, order: .reverse) private var films: [Film]
	@Query(sort: \TitleCollection.created) private var collections: [TitleCollection]

	@State private var editing = false
	@State private var destination: Destination?
	@State private var addingTitles = false

	/// What the Settings button and the verdicts card open.
	private enum Destination: String, Identifiable {
		case settings = "Settings"
		case stats = "Stats"

		var id: Self { self }
	}

	/// Your accent, dimmed for white text and running down to a deeper shade, as
	/// a title page does with a poster's colour.
	private var ground: LinearGradient { PageGround.accent.gradient }

	/// No Done button: like Settings and Stats, the sheet closes with a swipe down.
	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 24) {
					header
					Button { destination = .stats } label: {
						VerdictSummaryCard(counts: ProfileFeed.verdictCounts(shows: shows, films: films))
					}
					.buttonStyle(.pressable)
					.accessibilityHint("Opens your stats")
					topFour
					ProfileWeekSection(films: films)
				}
				.foregroundStyle(.white)
				.padding(.horizontal, 20)
				.padding(.bottom, 32)
				.readableColumn()
			}
			// White text and dark glass on the colour, whatever the system's scheme —
			// set on the page rather than the stack, so the sheets opened from here
			// keep the system's.
			.environment(\.colorScheme, .dark)
			.background(ground.ignoresSafeArea())
			.toolbar(.hidden, for: .navigationBar)
		}
		.presentationBackground(ground)
		.sheet(isPresented: $editing) { EditProfileView() }
		.sheet(item: $destination) { destination in
			switch destination {
			case .settings: PhoneSettingsView()
			case .stats:    PhoneStatsView()
			}
		}
		.sheet(isPresented: $addingTitles) {
			CollectionTitlePicker(collectionID: TitleCollection.topFourID)
		}
	}

	/// Your avatar and nickname, with Edit in the top left corner and Settings
	/// in the top right.
	private var header: some View {
		VStack(spacing: 12) {
			ProfileAvatar(nickname: profile.nickname, image: profile.avatar, size: 96)
			Text(profile.nickname.isEmpty ? "Your Profile" : profile.nickname)
				.font(.system(size: 30, weight: .bold))
				.lineLimit(1)
				.minimumScaleFactor(0.6)
				.accessibilityAddTraits(.isHeader)
		}
		.frame(maxWidth: .infinity)
		.padding(.top, 40)
		.overlay(alignment: .top) {
			HStack {
				iconButton("Edit Profile", systemImage: "pencil") { editing = true }
				Spacer()
				iconButton("Settings", systemImage: "gearshape") { destination = .settings }
			}
			.padding(.top, 16)
		}
	}

	/// A round glass button with just its icon, like the tabs' profile button.
	private func iconButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Image(systemName: systemImage)
				.font(.system(size: 18, weight: .semibold))
				.frame(width: GlassControl.height, height: GlassControl.height)
				.contentShape(Circle())
		}
		.buttonStyle(.plain)
		.glassEffect(.regular.interactive(), in: Circle())
		.accessibilityLabel(title)
	}

	// MARK: Top 4

	/// The pinned collection's four posters, with a place to add one in each
	/// spot still free, and "3 of 4" opening its page; before anything's in, a
	/// way to fill it.
	private var topFour: some View {
		let pinned = CollectionsFeed.pinned(collections)
		let items = Array(CollectionsFeed.items(in: pinned, shows: shows, films: films)
			.prefix(TitleCollection.topFourSize))
		return VStack(alignment: .leading, spacing: 12) {
			HStack(spacing: 6) {
				Text(pinned?.name ?? TitleCollection.topFourName)
					.font(.system(size: 20, weight: .bold))
					.accessibilityAddTraits(.isHeader)
				Spacer(minLength: 8)
				if !items.isEmpty {
					NavigationLink { PhoneCollectionView(source: .mine(TitleCollection.topFourID)) } label: {
						HStack(spacing: 4) {
							Text(CollectionsFeed.countLabel(items.count, in: pinned))
							Image(systemName: "chevron.right")
								.font(.system(size: 12, weight: .bold))
						}
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(.white.opacity(0.75))
					}
				}
			}
			if items.isEmpty {
				emptyShelf
			} else {
				LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top),
				                         count: TitleCollection.topFourSize),
				          alignment: .leading, spacing: 10) {
					ForEach(items) { item in
						NavigationLink { item.destination } label: { ShelfPoster(item: item) }
							.buttonStyle(.pressable)
					}
					ForEach(items.count..<TitleCollection.topFourSize, id: \.self) { _ in
						Button { addingTitles = true } label: { ShelfAddSpot() }
							.buttonStyle(.pressable)
					}
				}
			}
		}
	}

	private var emptyShelf: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Pick the four titles you love most and they lead your profile.")
				.font(.system(size: 14, weight: .medium))
				.foregroundStyle(.white.opacity(0.75))
				.fixedSize(horizontal: false, vertical: true)
			Button { addingTitles = true } label: {
				Label("Add titles", systemImage: "plus")
					.font(.system(size: 15, weight: .semibold))
					.padding(.horizontal, 18)
					.frame(height: GlassControl.height)
					.contentShape(Capsule())
			}
			.buttonStyle(.plain)
			.glassEffect(.regular.interactive(), in: Capsule())
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(16)
		.liquidCard(cornerRadius: 20)
	}
}
