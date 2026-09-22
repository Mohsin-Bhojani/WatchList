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

// MARK: - Verdicts

/// Your verdicts added up: a bar split by how many titles have each, and the
/// counts under it. The profile makes it the way into Stats.
private struct VerdictSummaryCard: View {
	let counts: [ProfileFeed.VerdictCount]

	var body: some View {
		let total = counts.reduce(0) { $0 + $1.count }
		VStack(alignment: .leading, spacing: 12) {
			HStack(alignment: .firstTextBaseline) {
				Text("Your verdicts")
					.font(.system(size: 15, weight: .semibold))
				Spacer()
				HStack(spacing: 6) {
					Text(total == 0 ? "None yet" : "\(total) rated")
					// It opens Stats.
					Image(systemName: "chevron.right")
						.font(.system(size: 12, weight: .bold))
				}
				.font(.system(size: 13, weight: .medium))
				.foregroundStyle(.white.opacity(0.6))
			}
			if total > 0 { bar(total: total) }
			LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible())],
			          alignment: .leading, spacing: 8) {
				ForEach(counts) { item in
					HStack(spacing: 8) {
						Circle()
							.fill(Glass.tint(item.rating))
							.frame(width: 8, height: 8)
						Text(item.rating.rawValue)
							.font(.system(size: 13, weight: .medium))
							.foregroundStyle(.white.opacity(0.85))
						Spacer(minLength: 4)
						Text("\(item.count)")
							.font(.system(size: 13, weight: .bold))
							.monospacedDigit()
					}
					.accessibilityElement(children: .combine)
				}
			}
		}
		.padding(16)
		.liquidCard(cornerRadius: 20)
	}

	/// A segment for each verdict given, as wide as its share, 2pt apart.
	private func bar(total: Int) -> some View {
		let given = counts.filter { $0.count > 0 }
		return GeometryReader { proxy in
			let room = proxy.size.width - CGFloat(given.count - 1) * 2
			HStack(spacing: 2) {
				ForEach(given) { item in
					Rectangle()
						.fill(Glass.tint(item.rating))
						.frame(width: room * CGFloat(item.count) / CGFloat(total))
				}
			}
		}
		.frame(height: 10)
		.clipShape(Capsule())
		.accessibilityHidden(true)
	}
}

// MARK: - Shelf poster

/// A poster on the profile's Top 4 shelf, four across: the art, the title and
/// its stars.
private struct ShelfPoster: View {
	let item: WatchedTitle

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			PosterImage(urlString: item.posterURL, systemPlaceholder: item.placeholder)
				.aspectRatio(2.0 / 3.0, contentMode: .fit)
				.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
				.shadow(color: .black.opacity(0.35), radius: 8, y: 8)
			VStack(alignment: .leading, spacing: 2) {
				Text(item.title)
					.font(.system(size: 12, weight: .semibold))
					.lineLimit(1)
				if let stars = item.stars {
					HStack(spacing: 3) {
						Image(systemName: "star.fill")
							.font(.system(size: 9))
							.foregroundStyle(StarRatingPicker.gold)
						Text(StarRating.label(stars))
					}
					.font(.system(size: 11, weight: .semibold))
					.foregroundStyle(.white.opacity(0.7))
				} else {
					Text(item.kindLabel)
						.font(.system(size: 11, weight: .semibold))
						.foregroundStyle(.white.opacity(0.7))
				}
			}
		}
		.accessibilityElement(children: .combine)
	}
}

/// A free spot on the Top 4 shelf: a dashed poster-sized outline with a plus,
/// which opens Add Titles.
private struct ShelfAddSpot: View {
	var body: some View {
		RoundedRectangle(cornerRadius: 10, style: .continuous)
			.strokeBorder(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
			.aspectRatio(2.0 / 3.0, contentMode: .fit)
			.overlay {
				Image(systemName: "plus")
					.font(.system(size: 18, weight: .semibold))
					.foregroundStyle(.white.opacity(0.7))
			}
			.contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
			.accessibilityElement(children: .ignore)
			.accessibilityLabel("Add to Top 4")
	}
}

// MARK: - This week

/// This week: the time watched on each of the last seven days as columns, and
/// the titles that filled them — the week's most watched, or everything from a
/// day once its column is tapped.
private struct ProfileWeekSection: View {
	let films: [Film]
	private let now: Date

	@Query private var episodes: [Episode]
	/// The tapped day's start; nil for the whole week.
	@State private var picked: Date?

	init(films: [Film], now: Date = .now) {
		self.films = films
		self.now = now
		// Only the episodes marked Watched this week, however big the library.
		let start = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: now)) ?? now
		let never = Date.distantPast
		_episodes = Query(filter: #Predicate<Episode> { ($0.watchedAt ?? never) >= start })
	}

	var body: some View {
		let week = ProfileFeed.week(ProfileFeed.watchedOneByOne(ProfileFeed.watches(episodes: episodes, films: films)),
		                            now: now)
		// Gone once midnight moves the week on past it.
		let day = week.days.first { $0.id == picked }
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .firstTextBaseline) {
				Text("This week")
					.font(.system(size: 20, weight: .bold))
					.accessibilityAddTraits(.isHeader)
				Spacer(minLength: 8)
				if week.minutes > 0 {
					Text("\(ProfileFeed.duration(week.minutes)) · \(ProfileFeed.duration(week.dailyAverage)) a day")
						.font(.system(size: 13, weight: .medium))
						.foregroundStyle(.white.opacity(0.6))
				}
			}
			VStack(alignment: .leading, spacing: 14) {
				if week.minutes == 0 {
					Text("Nothing watched in the last seven days. Episodes and films you mark Watched show up here, with how long they ran.")
						.font(.system(size: 14, weight: .medium))
						.foregroundStyle(.white.opacity(0.75))
						.fixedSize(horizontal: false, vertical: true)
				} else {
					chart(week, picked: day)
					Rectangle()
						.fill(.white.opacity(0.12))
						.frame(height: 1)
					ZStack(alignment: .topLeading) {
						// Every list the chart can show — the week's and each day's — laid
						// out but not drawn, so the card is always as tall as the longest
						// and the page doesn't move when a day is picked.
						ForEach([nil] + week.days.map(Optional.some), id: \.?.id) { option in
							titles(week, day: option)
								.hidden()
								.accessibilityHidden(true)
						}
						titles(week, day: day)
					}
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			.padding(16)
			.liquidCard(cornerRadius: 20)
		}
	}

	/// Picks a day, or goes back to the week when it's the day already picked.
	private func toggle(_ day: ProfileFeed.Day) {
		Haptics.selection()
		withAnimation(Glass.smooth) { picked = picked == day.id ? nil : day.id }
	}

	/// A thin white column a day, square on the baseline, with gridlines on the
	/// hour. Tapping anywhere in a day's column picks it, lighting its column and
	/// label and dimming the rest — at once, not animated: Charts can't ease
	/// between the two, so it cross-fades the whole plot and every column flashes.
	private func chart(_ week: ProfileFeed.Week, picked: ProfileFeed.Day?) -> some View {
		let top = ProfileFeed.chartTop(for: week)
		let step = ProfileFeed.gridStep(forTop: top)
		// The day whose label is lit: the one picked, or else today.
		let lit = picked.map { ProfileFeed.label(for: $0, now: now) } ?? "Today"
		return Chart {
			ForEach(week.days) { day in
				let label = ProfileFeed.label(for: day, now: now)
				BarMark(x: .value("Day", label), y: .value("Minutes", day.minutes), width: .fixed(22))
					.foregroundStyle(.white.opacity(picked == nil || picked?.id == day.id ? 0.92 : 0.35))
					.clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
					.accessibilityLabel(label)
					.accessibilityValue(ProfileFeed.duration(day.minutes))
			}
			RuleMark(y: .value("None", 0))
				.foregroundStyle(.white.opacity(0.3))
				.lineStyle(StrokeStyle(lineWidth: 1))
		}
		.chartYScale(domain: 0...top)
		.chartYAxis {
			AxisMarks(position: .leading, values: Array(stride(from: step, through: top, by: step))) { value in
				AxisGridLine()
					.foregroundStyle(.white.opacity(0.12))
				AxisValueLabel {
					if let minutes = value.as(Int.self) {
						Text("\(minutes / 60)h")
					}
				}
				.font(.system(size: 10, weight: .semibold))
				.foregroundStyle(.white.opacity(0.7))
			}
		}
		.chartXAxis {
			AxisMarks { value in
				AxisValueLabel {
					if let label = value.as(String.self) {
						// Only Today is bold, whichever day is picked: a label changing
						// weight changes width, and the axis lays itself out again.
						Text(label)
							.fontWeight(label == "Today" ? .bold : .semibold)
							.foregroundStyle(.white.opacity(label == lit ? 1 : 0.6))
					}
				}
				.font(.system(size: 11))
			}
		}
		.chartOverlay { proxy in
			GeometryReader { geometry in
				if let plot = proxy.plotFrame {
					Rectangle()
						.fill(.clear)
						.contentShape(Rectangle())
						.onTapGesture { location in
							guard let label: String = proxy.value(atX: location.x - geometry[plot].minX),
							      let day = week.days.first(where: { ProfileFeed.label(for: $0, now: now) == label })
							else { return }
							toggle(day)
						}
				}
			}
		}
		.accessibilityActions {
			ForEach(week.days) { day in
				Button("Show \(ProfileFeed.name(for: day, now: now))") { toggle(day) }
			}
		}
		.transaction { $0.animation = nil }
		.frame(height: 150)
	}

	/// Under the chart: the week's three most watched titles, or everything the
	/// picked day held with its time.
	@ViewBuilder private func titles(_ week: ProfileFeed.Week, day: ProfileFeed.Day?) -> some View {
		let titles = (day?.titles ?? week.titles).filter { $0.minutes > 0 }
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .firstTextBaseline) {
				Text(day.map { ProfileFeed.name(for: $0, now: now) } ?? "Most watched")
					.font(.system(size: 15, weight: .semibold))
					.accessibilityAddTraits(.isHeader)
				Spacer(minLength: 8)
				if let day {
					if day.minutes > 0 {
						Text(ProfileFeed.duration(day.minutes))
							.font(.system(size: 13, weight: .medium))
							.foregroundStyle(.white.opacity(0.6))
					}
					Button {
						Haptics.selection()
						withAnimation(Glass.smooth) { picked = nil }
					} label: {
						Image(systemName: "xmark")
							.font(.system(size: 11, weight: .bold))
							.frame(width: 26, height: 26)
							.contentShape(Circle())
					}
					.buttonStyle(.plain)
					.glassEffect(.regular.interactive(), in: Circle())
					.accessibilityLabel("Show the week")
				} else {
					Text("Tap a day")
						.font(.system(size: 13, weight: .medium))
						.foregroundStyle(.white.opacity(0.6))
				}
			}
			if titles.isEmpty {
				Text("Nothing watched this day.")
					.font(.system(size: 14, weight: .medium))
					.foregroundStyle(.white.opacity(0.75))
			} else {
				ForEach(day == nil ? Array(titles.prefix(3)) : titles) { title in
					row(title, longest: titles[0].minutes)
				}
			}
		}
		// A new list fades in rather than rows sliding between the week and a day.
		.id(day?.id)
		.transition(.opacity)
	}

	/// A title's share of the week or day: its poster, what was watched, a bar
	/// against the longest listed and its time.
	private func row(_ title: ProfileFeed.TitleTime, longest: Int) -> some View {
		HStack(spacing: 10) {
			PosterImage(urlString: title.posterURL, systemPlaceholder: title.isFilm ? "film" : "tv")
				.frame(width: 24, height: 36)
				.clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
			VStack(alignment: .leading, spacing: 6) {
				HStack(alignment: .firstTextBaseline, spacing: 8) {
					Text(title.title)
						.font(.system(size: 13, weight: .semibold))
						.lineLimit(1)
					Spacer(minLength: 4)
					Text(title.isFilm ? "Film" : ShowFacts.episodes(title.episodes))
						.font(.system(size: 12, weight: .medium))
						.foregroundStyle(.white.opacity(0.6))
				}
				GeometryReader { proxy in
					Capsule()
						.fill(.white.opacity(0.18))
						.overlay(alignment: .leading) {
							Capsule()
								.fill(.white)
								.frame(width: proxy.size.width * CGFloat(title.minutes) / CGFloat(max(longest, 1)))
						}
				}
				.frame(height: 4)
			}
			Text(ProfileFeed.duration(title.minutes))
				.font(.system(size: 14, weight: .bold))
				.frame(minWidth: 62, alignment: .trailing)
		}
		.accessibilityElement(children: .ignore)
		.accessibilityLabel("\(title.title), \(ProfileFeed.duration(title.minutes))")
	}
}

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
							.font(.system(size: 26, weight: .bold))
						Text("Set your identity with an avatar and a nickname.")
							.font(.system(size: 16))
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
					.font(.system(size: 17, weight: .medium))
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
				.font(.system(size: 18, weight: .semibold))
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
