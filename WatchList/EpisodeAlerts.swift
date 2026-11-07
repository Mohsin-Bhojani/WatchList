//
//  EpisodeAlerts.swift
//  WatchList
//
//  New-episode notifications, and the background refresh that brings them.
//
//  A few times a day iOS wakes the app in the background (BGAppRefreshTask).
//  It runs the same daily check Home does — LibraryRefresher, at most once a
//  day — and then looks for episodes of shows you're Watching that have just
//  aired: one notification a show, once per episode. The notifications are off
//  until turned on in Settings, which is when permission is asked for.
//
//  What counts as just aired is the last couple of days, so turning this on, or
//  coming back after a while, never sends a backlog. Opening the app counts as
//  seeing what's out, so the background won't announce it afterwards.
//

import Foundation
import SwiftData
import UserNotifications
import BackgroundTasks

enum EpisodeAlerts {

	static let enabledKey = "notifyNewEpisodes"
	private static let notifiedKey = "notifiedEpisodeIDs"
	/// How far back an episode still counts as just aired.
	static let windowDays = 2

	static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

	// MARK: Deciding — free of the system, so it can be tested

	/// Episodes of Watching shows that aired in the last `windowDays` days, up
	/// to today, aren't Watched, and haven't been announced or seen yet.
	static func due(in shows: [Show], notified: Set<UUID>, asOf now: Date = .now,
	                calendar: Calendar = .current) -> [Episode] {
		let today = AirDate.day(now, calendar: calendar)
		let earliest = AirDate.day(calendar.date(byAdding: .day, value: -windowDays, to: now) ?? now, calendar: calendar)
		return HomeFeed.watching(shows).flatMap { show in
			HomeFeed.runningOrder(of: show).filter { episode in
				guard episode.status != .watched, !notified.contains(episode.id),
				      let day = AirDate.dayPart(of: episode.airDate) else { return false }
				return day >= earliest && day <= today
			}
		}
	}

	struct Alert: Equatable {
		/// One a show, so a second alert for it replaces the first.
		let id: String
		let title: String
		let body: String
	}

	/// One alert a show: its episode by name when it's one, a count when more.
	static func alerts(for episodes: [Episode]) -> [Alert] {
		var order: [UUID] = []
		var byShow: [UUID: (show: Show, episodes: [Episode])] = [:]
		for episode in episodes {
			guard let show = episode.season?.show else { continue }
			if byShow[show.id] == nil { order.append(show.id) }
			byShow[show.id, default: (show, [])].episodes.append(episode)
		}
		return order.compactMap { byShow[$0] }.map { show, episodes in
			let body = episodes.count == 1
				? "\(ShowFacts.code(episodes[0])) · \(episodes[0].displayTitle) is out now."
				: "\(episodes.count) new episodes are out."
			return Alert(id: "new-episodes-\(show.id.uuidString)", title: show.title, body: body)
		}
	}

	// MARK: Remembering

	static var notified: Set<UUID> {
		Set((UserDefaults.standard.stringArray(forKey: notifiedKey) ?? []).compactMap(UUID.init(uuidString:)))
	}

	/// Remembers `episodes` as announced or seen, dropping ids from long ago so
	/// the list stays short.
	static func remember(_ episodes: [Episode]) {
		guard !episodes.isEmpty else { return }
		let ids = (UserDefaults.standard.stringArray(forKey: notifiedKey) ?? []) + episodes.map(\.id.uuidString)
		UserDefaults.standard.set(Array(ids.suffix(500)), forKey: notifiedKey)
	}

	// MARK: The system

	/// Asks for permission; true when notifications can be shown.
	static func requestPermission() async -> Bool {
		(try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
	}

	/// Announces what's due, when notifications are on, and remembers it.
	@MainActor
	static func announce(in shows: [Show]) async {
		let episodes = due(in: shows, notified: notified)
		guard !episodes.isEmpty else { return }
		if isEnabled {
			for alert in alerts(for: episodes) {
				let content = UNMutableNotificationContent()
				content.title = alert.title
				content.body = alert.body
				content.sound = .default
				let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: nil)
				try? await UNUserNotificationCenter.current().add(request)
			}
		}
		remember(episodes)
	}

	/// With the app open, what's out is on Home already: remembered as seen.
	@MainActor
	static func markSeen(in shows: [Show]) {
		remember(due(in: shows, notified: notified))
	}
}

// MARK: - Background refresh

enum BackgroundRefresh {
	/// Listed under BGTaskSchedulerPermittedIdentifiers in the iPhone's Info.plist.
	static let identifier = "com.mohsin.WatchList.episodeCheck"

	/// Asks iOS to wake the app in a few hours. It decides when, if at all.
	static func schedule() {
		let request = BGAppRefreshTaskRequest(identifier: identifier)
		request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
		try? BGTaskScheduler.shared.submit(request)
	}

	/// What a background wake does: books the next one, runs the daily check
	/// when it's due, and announces what's just aired.
	@MainActor
	static func run(in container: ModelContainer) async {
		schedule()
		let context = container.mainContext
		guard let shows = try? context.fetch(FetchDescriptor<Show>()) else { return }
		if LibraryRefresher.autoCheckIsDue {
			_ = await LibraryRefresher.refreshAll(shows: shows, into: context)
			try? context.save()
		}
		await EpisodeAlerts.announce(in: shows)
	}
}
