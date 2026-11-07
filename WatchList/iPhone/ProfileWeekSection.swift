//
//  ProfileWeekSection.swift
//  WatchList
//
//  The Profile screen's This week: what was watched in the last seven days.
//  Split out of ProfileView.swift.
//

import SwiftUI
import SwiftData
import Charts

// MARK: - This week

/// This week: the time watched on each of the last seven days as columns, and
/// the titles that filled them — the week's most watched, or everything from a
/// day once its column is tapped.
struct ProfileWeekSection: View {
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
		let week = ProfileFeed.week(ProfileFeed.watches(episodes: episodes, films: films), now: now)
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
