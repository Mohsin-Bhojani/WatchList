//
//  WatchLinkTests.swift
//  WatchListTests
//
//  The link with the watch app: what the iPhone sends, what the watch's actions
//  do to the library, and how the watch lays its own actions over the last
//  snapshot until the iPhone has applied them.
//

import Foundation
import SwiftData
import Testing
@testable import WatchList

@MainActor
struct WatchLinkTests {

	private let now = Date(timeIntervalSince1970: 1_800_000_000)

	/// A show whose seasons each hold `episodes` To Watch episodes.
	private func show(_ title: String, status: WatchStatus, tmdbID: Int? = nil,
	                  _ seasons: [(number: Int, episodes: Int)]) -> Show {
		let show = Show(title: title, tmdbID: tmdbID, status: status)
		for spec in seasons {
			let season = Season(seasonNumber: spec.number)
			season.show = show
			show.seasons.append(season)
			for number in 1...max(spec.episodes, 1) where spec.episodes > 0 {
				let episode = Episode(episodeNumber: number, seasonNumber: spec.number, title: "E\(number)",
				                      runtimeMinutes: 40)
				episode.season = season
				season.episodes.append(episode)
			}
		}
		return show
	}

	private func snapshot(upNext: [UpNextShow] = [], library: Set<String> = [], notInterested: Set<String> = [],
	                      putOff: [String: Date] = [:], applied: Set<UUID> = [], sentAt: Date) -> PhoneSnapshot {
		PhoneSnapshot(upNext: upNext, seeds: [], library: library, notInterested: notInterested, putOff: putOff,
		              applied: applied, sentAt: sentAt)
	}

	// MARK: What the iPhone sends

	@Test func upNextIsTheWatchingShowsWithTheirNextEpisodesSpecialsLast() {
		let started = show("Started", status: .watching, [(0, 1), (1, 3), (2, 2)])
		started.sortedSeasons[1].sortedEpisodes[0].mark(.watched)
		let waiting = show("Waiting", status: .toWatch, [(1, 2)])
		let upNext = WatchSnapshotBuilder.upNext([waiting, started], upcoming: 3)

		#expect(upNext.map(\.title) == ["Started"])
		#expect(upNext[0].upcoming.map(\.code) == ["S1 · E2", "S1 · E3", "S2 · E1"])
		#expect(upNext[0].remaining == 5)                         // the special counts, last
		#expect(upNext[0].episodeCount == 6)
		#expect(upNext[0].upcoming[0].status == .toWatch)
	}

	@Test func upNextCarriesHomesHeroArtworkOrWhatTheShowWasSavedWith() {
		let withHero = show("Hero", status: .watching, [(1, 1)])
		let saved = show("Saved", status: .watching, [(1, 1)])
		saved.backdropURL = "https://image.tmdb.org/t/p/w780/backdrop.jpg"
		let posterOnly = show("Poster", status: .watching, [(1, 1)])
		posterOnly.posterURL = "https://image.tmdb.org/t/p/w500/poster.jpg"
		let hero = "https://image.tmdb.org/t/p/original/textless.jpg"

		let upNext = WatchSnapshotBuilder.upNext([withHero, saved, posterOnly], artwork: [withHero.id: hero])
		#expect(upNext.map(\.artworkURL) == [hero, saved.backdropURL, posterOnly.posterURL])
	}

	@Test func theSnapshotKeysTheLibraryAndSplitsTheDecisions() {
		let owned = show("Owned", status: .watched, tmdbID: 7, [])
		let byHand = show("By hand", status: .toWatch, [])
		let film = Film(title: "Film", tmdbID: 9, rating: .perfection)
		let decisions = [SuggestionDecision(key: "Show-1", choice: .notInterested, decidedAt: now),
		                 SuggestionDecision(key: "Film-2", choice: .later, decidedAt: now)]
		let sent = WatchSnapshotBuilder.snapshot(shows: [owned, byHand], films: [film], decisions: decisions,
		                                         applied: [], now: now)

		#expect(sent.library == ["Show-7", "Film-9"])
		#expect(sent.notInterested == ["Show-1"])
		#expect(sent.putOff == ["Film-2": now])
		// Seeds need TMDb: the rated film first, the title added by hand left out.
		#expect(sent.seeds.map(\.title) == ["Film", "Owned"])
	}

	@Test func snapshotsAndActionsSurviveTheTrip() throws {
		let episode = UUID()
		let sent = PhoneSnapshot(
			upNext: [UpNextShow(id: UUID(), title: "Show", artworkURL: "",
			                    upcoming: [UpNextEpisode(id: episode, seasonNumber: 1, episodeNumber: 2, title: "Two",
			                                             runtimeMinutes: nil, status: .toWatch, tier: .rewatch)],
			                    remaining: 1, episodeCount: 2)],
			seeds: [DiscoverSeed(id: UUID(), kind: .film, tmdbID: 3, title: "Seed")],
			library: ["Film-3"], notInterested: ["Show-4"], putOff: ["Show-5": now], applied: [UUID()], sentAt: now)
		let packed = try #require(WatchLink.pack(sent))
		#expect(WatchLink.unpack(PhoneSnapshot.self, from: packed) == sent)

		for change: WatchAction.Change in [.markWatched(episode: episode, tier: .skip),
		                                   .putBack(episode: episode, status: .watching, tier: nil),
		                                   .add(kind: .show, tmdbID: 8), .notInterested(key: "Film-1"),
		                                   .later(key: "Show-2")] {
			let action = WatchAction(change: change)
			#expect(WatchLink.unpack(WatchAction.self, from: try #require(WatchLink.pack(action))) == action)
		}
	}

	@Test func aBigLibraryStillFitsThePayload() throws {
		let shows = (0..<40).map { show("Show \($0)", status: .watching, tmdbID: $0, [(1, 20)]) }
		let films = (0..<600).map { Film(title: "Film \($0)", tmdbID: 10_000 + $0) }
		let decisions = (0..<800).map { SuggestionDecision(key: "Show-\(50_000 + $0)", choice: .notInterested) }
		let sent = WatchSnapshotBuilder.snapshot(shows: shows, films: films, decisions: decisions, applied: [])
		let packed = try #require(WatchLink.pack(sent))
		#expect(packed.count < WatchLink.payloadBudget)
	}

	// MARK: The watch's actions on the library

	@Test func markingRatingAndPuttingBackGoThroughTheIPhonesOwnRules() throws {
		let container = try ModelContainer(for: Show.self, Season.self, Episode.self, Film.self,
		                                   SuggestionDecision.self,
		                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
		let context = container.mainContext
		let watching = show("Watching", status: .watching, [(1, 2)])
		context.insert(watching)
		let episode = watching.sortedSeasons[0].sortedEpisodes[0]
		episode.episodeTier = .watch

		WatchActionApplier.apply(WatchAction(change: .markWatched(episode: episode.id, tier: .rewatch)), in: context)
		#expect(episode.status == .watched)
		#expect(episode.episodeTier == .rewatch)
		#expect(episode.watchedAt != nil)

		// Marked without a rating, an earlier one stays.
		let second = watching.sortedSeasons[0].sortedEpisodes[1]
		second.episodeTier = .skip
		WatchActionApplier.apply(WatchAction(change: .markWatched(episode: second.id, tier: nil)), in: context)
		#expect(second.episodeTier == .skip)

		WatchActionApplier.apply(WatchAction(change: .putBack(episode: episode.id, status: .toWatch, tier: .watch)),
		                         in: context)
		#expect(episode.status == .toWatch)
		#expect(episode.episodeTier == .watch)
		#expect(episode.watchedAt == nil)
	}

	@Test func decisionsKeepOnePerTitleTheLatestWinning() throws {
		let container = try ModelContainer(for: SuggestionDecision.self,
		                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
		let context = container.mainContext
		WatchActionApplier.apply(WatchAction(madeAt: now, change: .later(key: "Show-1")), in: context)
		WatchActionApplier.apply(WatchAction(madeAt: now.addingTimeInterval(60), change: .notInterested(key: "Show-1")),
		                         in: context)
		// Older than what's saved — delivered late — it changes nothing.
		WatchActionApplier.apply(WatchAction(madeAt: now.addingTimeInterval(-60), change: .later(key: "Show-1")),
		                         in: context)

		let saved = try context.fetch(FetchDescriptor<SuggestionDecision>())
		#expect(saved.count == 1)
		#expect(saved.first?.choice == .notInterested)
		#expect(saved.first?.decidedAt == now.addingTimeInterval(60))
	}

	// MARK: On the watch until applied

	@Test func aMarkMovesUpNextOnUntilUndoneOrApplied() {
		let first = UpNextEpisode(id: UUID(), seasonNumber: 1, episodeNumber: 1, title: "", runtimeMinutes: nil,
		                          status: .toWatch, tier: nil)
		let second = UpNextEpisode(id: UUID(), seasonNumber: 1, episodeNumber: 2, title: "", runtimeMinutes: nil,
		                           status: .toWatch, tier: nil)
		let shown = UpNextShow(id: UUID(), title: "Show", artworkURL: "", upcoming: [first, second], remaining: 2,
		                       episodeCount: 2)
		let before = snapshot(upNext: [shown], sentAt: now)
		var outbox = WatchOutbox()

		let mark = WatchAction(madeAt: now, change: .markWatched(episode: first.id, tier: .watch))
		outbox.add(mark)
		#expect(before.upNext(markedOnWatch: outbox.watched).first?.next == second)

		outbox.add(WatchAction(change: .putBack(episode: first.id, status: .toWatch, tier: nil)))
		#expect(before.upNext(markedOnWatch: outbox.watched).first?.next == first)

		// Marked all the way through: nothing to go, until the iPhone sends more.
		var marked = WatchOutbox()
		marked.add(WatchAction(change: .markWatched(episode: first.id, tier: nil)))
		marked.add(WatchAction(change: .markWatched(episode: second.id, tier: nil)))
		#expect(before.upNext(markedOnWatch: marked.watched).first?.next == nil)

		// The iPhone names the mark as applied: it's gone from the outbox.
		var applied = WatchOutbox()
		applied.add(mark)
		applied.confirm(by: snapshot(applied: [mark.id], sentAt: now.addingTimeInterval(5)))
		#expect(applied.isEmpty)
	}

	@Test func anActionHandedOverLongAgoAndNeverAppliedIsLetGo() {
		var outbox = WatchOutbox()
		let lost = WatchAction(madeAt: now, change: .notInterested(key: "Show-1"))
		let unsent = WatchAction(madeAt: now, change: .notInterested(key: "Show-2"))
		outbox.add(lost)
		outbox.add(unsent)
		outbox.markHandedOver([lost.id])

		outbox.confirm(by: snapshot(sentAt: now.addingTimeInterval(60)))
		#expect(outbox.entries.count == 2)

		outbox.confirm(by: snapshot(sentAt: now.addingTimeInterval(WatchOutbox.patience + 60)))
		// Never handed over — the iPhone app isn't there yet — it waits however long.
		#expect(outbox.unsent == [unsent])
		#expect(outbox.entries.count == 1)
	}

	@Test func aFailedTransferGoesBackToWaiting() {
		var outbox = WatchOutbox()
		let first = WatchAction(change: .later(key: "Show-1")), second = WatchAction(change: .later(key: "Show-2"))
		outbox.add(first)
		outbox.add(second)
		outbox.markHandedOver([first.id, second.id])
		#expect(outbox.unsent.isEmpty)

		outbox.markUnsent(second.id)
		#expect(outbox.unsent == [second])
		// Still laid over the snapshot meanwhile.
		#expect(outbox.decisions["Show-2"]?.choice == .later)
	}

	@Test func decisionsOnTheWatchShapeWhatDiscoverLeavesOut() {
		let sent = snapshot(library: ["Show-1"], notInterested: ["Film-2", "Film-3"],
		                    putOff: ["Show-4": now, "Show-5": now], sentAt: now)
		var outbox = WatchOutbox()
		let later = now.addingTimeInterval(60)
		outbox.add(WatchAction(madeAt: later, change: .later(key: "Film-2")))        // turned down there, put off here
		outbox.add(WatchAction(madeAt: later, change: .later(key: "Show-1")))        // in the library: stays out
		outbox.add(WatchAction(madeAt: later, change: .add(kind: .show, tmdbID: 4))) // put off there, added here
		outbox.add(WatchAction(madeAt: later, change: .notInterested(key: "Show-6")))

		#expect(sent.excluded(with: outbox) == ["Show-1", "Film-3", "Show-4", "Show-6"])
		#expect(sent.putOff(with: outbox) == ["Show-5": now, "Film-2": later, "Show-1": later])
	}
}
