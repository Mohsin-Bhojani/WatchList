//
//  LibraryRefresher.swift
//  WatchList
//
//  ImportCoordinator fetches a show's seasons once, at import, and nothing
//  ever looks again — so a show that gets a new season, or one airing weekly,
//  quietly goes stale. This re-checks TMDb and fills in what's missing.
//
//  It never takes anything away. It inserts seasons and episodes that aren't
//  here yet, and on episodes that are recent or still to air it brings TMDb's
//  own details up to date — the name that replaces "Episode 5", the still, the
//  synopsis, a moved air date — since those arrive after the episode is listed.
//  Status, rating, episodeTier, notes and a still you picked yourself are yours,
//  and a refresh must never cost you them.
//

import Foundation
import SwiftData

@MainActor
enum LibraryRefresher {

	/// Don't re-check more often than this when running automatically.
	static let autoInterval: TimeInterval = 24 * 60 * 60
	private static let lastCheckKey = "lastEpisodeCheck"

	struct Report {
		var showsChecked = 0
		var seasonsAdded = 0
		var episodesAdded = 0
		/// Episodes already here whose details TMDb has since filled in or changed.
		var episodesUpdated = 0
		var showsFailed = 0

		var foundSomething: Bool { seasonsAdded > 0 || episodesAdded > 0 || episodesUpdated > 0 }

		static func + (a: Report, b: Report) -> Report {
			Report(showsChecked: a.showsChecked + b.showsChecked,
			       seasonsAdded: a.seasonsAdded + b.seasonsAdded,
			       episodesAdded: a.episodesAdded + b.episodesAdded,
			       episodesUpdated: a.episodesUpdated + b.episodesUpdated,
			       showsFailed: a.showsFailed + b.showsFailed)
		}

		/// Phrased for a settings row, so it has to read well when nothing changed.
		var summary: String {
			if showsChecked == 0 { return "Nothing to check yet." }
			guard foundSomething else {
				return showsFailed > 0
					? "Up to date. \(showsFailed) show\(showsFailed == 1 ? "" : "s") couldn't be checked."
					: "Everything's up to date."
			}
			var parts: [String] = []
			if seasonsAdded > 0 { parts.append("\(seasonsAdded) new season\(seasonsAdded == 1 ? "" : "s")") }
			if episodesAdded > 0 { parts.append("\(episodesAdded) new episode\(episodesAdded == 1 ? "" : "s")") }
			let updated = "\(episodesUpdated) episode\(episodesUpdated == 1 ? "" : "s")"
			guard !parts.isEmpty else { return "Updated \(updated)." }
			let added = "Added " + parts.joined(separator: " and ") + "."
			return episodesUpdated > 0 ? added + " Updated \(updated)." : added
		}
	}

	// MARK: Entry points

	/// True when an automatic check is due. Manual checks ignore this.
	static var autoCheckIsDue: Bool {
		guard UserDefaults.standard.bool(forKey: "autoCheckNewEpisodes") else { return false }
		let last = UserDefaults.standard.object(forKey: lastCheckKey) as? Date
		guard let last else { return true }
		return Date().timeIntervalSince(last) >= autoInterval
	}

	static func markChecked() {
		UserDefaults.standard.set(Date(), forKey: lastCheckKey)
	}

	static var lastChecked: Date? {
		UserDefaults.standard.object(forKey: lastCheckKey) as? Date
	}

	static func refreshAll(shows: [Show], into context: ModelContext) async -> Report {
		guard TMDbConfig.isConfigured else { return Report() }
		var report = Report()
		for show in shows {
			report = report + (await refresh(show, into: context))
		}
		markChecked()
		return report
	}

	// MARK: One show

	static func refresh(_ show: Show, into context: ModelContext) async -> Report {
		guard let tmdbID = show.tmdbID else { return Report() }

		guard let tv = try? await TMDbService.shared.tv(id: tmdbID) else {
			return Report(showsChecked: 1, showsFailed: 1)
		}

		var report = Report(showsChecked: 1)

		// Same rule as import: "Season 0" is specials, and we don't carry it.
		let summaries = (tv.seasons ?? [])
			.filter { $0.season_number > 0 }
			.sorted { $0.season_number < $1.season_number }

		for number in seasonsNeedingFetch(summaries: summaries, existing: show.seasons) {
			let existing = show.seasons.first { $0.seasonNumber == number }

			guard let detail = try? await TMDbService.shared.season(tvID: tmdbID, seasonNumber: number) else {
				continue
			}

			let season: Season
			if let existing {
				season = existing
				let byNumber = Dictionary((detail.episodes ?? []).map { ($0.episode_number, $0) },
				                          uniquingKeysWith: { a, _ in a })
				for episode in season.episodes where isProvisional(episode, asOf: .now) {
					guard let remote = byNumber[episode.episodeNumber] else { continue }
					let keepStill = ArtworkChoice.chosen(.landscape, for: episode.id)
					if update(episode, from: remote, keepingStill: keepStill) { report.episodesUpdated += 1 }
				}
			} else {
				season = Season(seasonNumber: number,
				                name: detail.name ?? "Season \(number)",
				                overview: detail.overview ?? "",
				                posterURL: TMDbConfig.poster(detail.poster_path),
				                airYear: String((detail.air_date ?? "").prefix(4)))
				season.show = show
				context.insert(season)
				report.seasonsAdded += 1
			}

			for e in missingEpisodes(from: detail, have: season.episodes.map(\.episodeNumber)) {
				let episode = Episode(episodeNumber: e.episode_number,
				                      seasonNumber: number,
				                      title: e.name ?? "Episode \(e.episode_number)",
				                      synopsis: e.overview ?? "",
				                      stillURL: TMDbConfig.still(e.still_path),
				                      airDate: e.air_date ?? "",
				                      runtimeMinutes: e.runtime,
				                      specs: TechSpecs(episode: e, tv: tv),
				                      tmdbShowID: tmdbID)
				episode.season = season
				context.insert(episode)
				report.episodesAdded += 1
			}
		}

		return report
	}

	// MARK: The decisions, kept free of the network so they can be tested

	/// Which season numbers actually need a detail request.
	///
	/// TMDb reports each season's episode count in the show payload we already
	/// have, so a season whose count still matches costs nothing — a
	/// long-running show is one request, not twenty. Anything missing, or with
	/// a count that moved, gets fetched.
	///
	/// A season whose count matches is fetched anyway while it holds an episode
	/// that's provisional — recent or still to air — so its details can catch up.
	static func seasonsNeedingFetch(summaries: [TMDbSeasonSummary], existing: [Season],
	                                asOf now: Date = .now) -> [Int] {
		let local = Dictionary(existing.map { ($0.seasonNumber, $0) }, uniquingKeysWith: { a, _ in a })
		return summaries
			.filter { $0.season_number > 0 }          // season 0 is specials
			.filter { summary in
				guard let season = local[summary.season_number] else { return true }
				guard let remote = summary.episode_count else { return true }
				return remote != season.episodes.count
					|| season.episodes.contains { isProvisional($0, asOf: now) }
			}
			.map(\.season_number)
			.sorted()
	}

	/// How long after airing an episode's details are still worth re-reading:
	/// TMDb's stills and synopses tend to arrive in the days after.
	static let settleDays = 14

	/// True for an episode from TMDb whose details may still change: one still
	/// to air, aired in the last `settleDays`, or with no air date yet. An
	/// episode added by hand has no TMDb show and never is.
	static func isProvisional(_ episode: Episode, asOf now: Date = .now, calendar: Calendar = .current) -> Bool {
		guard episode.tmdbShowID != nil else { return false }
		guard let day = AirDate.dayPart(of: episode.airDate) else { return true }
		let settled = calendar.date(byAdding: .day, value: -settleDays, to: now) ?? now
		return day >= AirDate.day(settled, calendar: calendar)
	}

	/// Brings TMDb's own details on `episode` in line with `remote`: name,
	/// synopsis, still (unless `keepingStill`, a still picked by hand), air date
	/// and runtime. Only replaces with something — an empty field from TMDb
	/// never blanks one here — and never touches status, tier or watched date.
	/// True when anything changed.
	@discardableResult
	static func update(_ episode: Episode, from remote: TMDbEpisode, keepingStill: Bool) -> Bool {
		var changed = false
		func set<Value: Equatable>(_ path: ReferenceWritableKeyPath<Episode, Value>, _ value: Value?) {
			guard let value, episode[keyPath: path] != value else { return }
			episode[keyPath: path] = value
			changed = true
		}
		func text(_ value: String?) -> String? {
			guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
			return value
		}
		set(\.title, text(remote.name))
		set(\.synopsis, text(remote.overview))
		if !keepingStill { set(\.stillURL, text(TMDbConfig.still(remote.still_path))) }
		set(\.airDate, text(remote.air_date))
		let runtime = (remote.runtime ?? 0) > 0 ? remote.runtime : nil
		set(\.runtimeMinutes, runtime.map(Optional.some))
		if var specs = episode.specs {
			let before = specs
			if let runtime { specs.runtimeMinutes = runtime }
			if let date = text(remote.air_date) { specs.releaseDate = date }
			if specs != before { episode.specs = specs; changed = true }
		}
		return changed
	}

	/// Episodes present on TMDb that aren't here yet. Never the reverse: if
	/// TMDb drops or renumbers one, the local record stays put, because it may
	/// carry a watched mark or a rewatch tier.
	nonisolated static func missingEpisodes(from detail: TMDbSeasonDetail, have: [Int]) -> [TMDbEpisode] {
		let known = Set(have)
		return (detail.episodes ?? []).filter { !known.contains($0.episode_number) }
	}
}
