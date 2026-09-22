//
//  CollectionsFeedTests.swift
//  WatchListTests
//
//  The Collections tab's by-verdict collections, the pinned Top 4, and
//  the lines their cards use.
//

import Foundation
import SwiftData
import Testing
@testable import WatchList

@MainActor
struct CollectionsFeedTests {

	@Test func eachVerdictHoldsItsTitlesMostStarsFirstThenNewest() {
		let now = Date(timeIntervalSince1970: 1_800_000_000)
		let olderPerfect = Show(title: "Older perfect", status: .watched, rating: .perfection)
		olderPerfect.dateAdded = now.addingTimeInterval(-500)
		let newerPerfect = Film(title: "Newer perfect", status: .watched, rating: .perfection)
		newerPerfect.dateAdded = now.addingTimeInterval(-10)
		let fourAndAHalf = Show(title: "Go for it, 4.5", status: .watched, rating: .goForIt)
		fourAndAHalf.dateAdded = now.addingTimeInterval(-900)
		let four = Film(title: "Go for it, 4", status: .toWatch, rating: .goForIt)
		four.dateAdded = now
		let unrated = Show(title: "Unrated", status: .watched)

		fourAndAHalf.stars = 4.5
		let collections = CollectionsFeed.byVerdict(shows: [olderPerfect, fourAndAHalf, unrated],
		                                            films: [newerPerfect, four])

		#expect(collections.map(\.rating) == [.perfection, .goForIt, .timepass, .skip])
		#expect(collections[0].items.map(\.title) == ["Newer perfect", "Older perfect"])
		#expect(collections[1].items.map(\.title) == ["Go for it, 4.5", "Go for it, 4"])
		#expect(collections[2].items.isEmpty)
		#expect(collections[3].items.isEmpty)
	}

	@Test func yourCollectionKeepsItsOrderAndSkipsRemovedTitles() {
		let first = Film(title: "First added")
		let second = Show(title: "Second added")
		let collection = TitleCollection(name: "Mine", titleIDs: [first.id, UUID(), second.id])
		let items = CollectionsFeed.items(in: collection, shows: [second], films: [first]).map(\.title)
		#expect(items == ["First added", "Second added"])
		#expect(CollectionsFeed.items(in: nil, shows: [second], films: [first]).isEmpty)
	}

	@Test func yourCollectionsSortByCreatedNameOrSizeEitherWay() {
		let now = Date(timeIntervalSince1970: 1_800_000_000)
		let zombies = TitleCollection(name: "zombies", titleIDs: [UUID()], created: now.addingTimeInterval(-200))
		let anime = TitleCollection(name: "Anime", titleIDs: [UUID(), UUID(), UUID()], created: now.addingTimeInterval(-100))
		let comfort = TitleCollection(name: "Comfort", titleIDs: [UUID(), UUID(), UUID()], created: now)
		let collections = [comfort, zombies, anime]

		func order(_ sort: CollectionsFeed.Sort, reversed: Bool = false) -> [String] {
			CollectionsFeed.sorted(collections, by: ListOrder(sort: sort, reversed: reversed)) { $0.titleIDs.count }
				.map(\.name)
		}
		#expect(CollectionsFeed.Sort.allCases.map(\.title) == ["Created", "A–Z", "Size"])
		#expect(order(.created) == ["zombies", "Anime", "Comfort"])
		#expect(order(.created, reversed: true) == ["Comfort", "Anime", "zombies"])
		#expect(order(.name) == ["Anime", "Comfort", "zombies"])
		#expect(order(.name, reversed: true) == ["zombies", "Comfort", "Anime"])
		// Anime and Comfort both hold three: the one made first leads, either way round.
		#expect(order(.size) == ["Anime", "Comfort", "zombies"])
		#expect(order(.size, reversed: true) == ["zombies", "Anime", "Comfort"])

		var standard = ListOrder<CollectionsFeed.Sort>()
		#expect(standard.summary == "Oldest first")
		#expect(standard.arrowSymbol == "arrow.up")
		standard.choose(.size)
		#expect(standard.summary == "Biggest first")
		#expect(standard.arrowSymbol == "arrow.down")
		standard.choose(.name)
		standard.choose(.name)
		#expect(standard.segmentTitle(for: .name) == "Z–A")
	}

	@Test func topFourIsPinnedApartFromYourCollections() {
		let pinned = TitleCollection(name: TitleCollection.topFourName)
		pinned.id = TitleCollection.topFourID
		let mine = TitleCollection(name: "Comfort")

		#expect(pinned.isPinned)
		#expect(!mine.isPinned)
		#expect(CollectionsFeed.pinned([mine, pinned]) === pinned)
		#expect(CollectionsFeed.pinned([mine]) == nil)
		#expect(CollectionsFeed.yours([mine, pinned]).map(\.name) == ["Comfort"])
	}

	@Test func aLibraryGetsTopFourOnlyOnce() throws {
		let container = try ModelContainer(for: TitleCollection.self,
		                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
		let context = container.mainContext
		context.insert(TitleCollection(name: "Comfort"))
		context.ensurePinnedCollection()
		context.ensurePinnedCollection()

		let collections = try context.fetch(FetchDescriptor<TitleCollection>())
		#expect(collections.count == 2)
		#expect(collections.filter(\.isPinned).map(\.name) == ["Top 4"])
	}

	@Test func anOldAllTimeBestBecomesTopFourKeepingItsFirstFourStillInTheLibrary() throws {
		let container = try ModelContainer(for: Show.self, Season.self, Episode.self, Film.self, TitleCollection.self,
		                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
		let context = container.mainContext
		let titles = (1...6).map { Film(title: "Film \($0)") }
		titles.forEach(context.insert)
		let gone = UUID()
		let old = TitleCollection(name: "All Time Best", titleIDs: [titles[0].id, gone] + titles[1...].map(\.id))
		old.id = TitleCollection.topFourID
		context.insert(old)

		context.ensurePinnedCollection()

		#expect(old.name == "Top 4")
		#expect(old.titleIDs == titles.prefix(4).map(\.id))
	}

	@Test func topFourHoldsFourAndYourOwnAnyNumber() {
		let pinned = TitleCollection(name: TitleCollection.topFourName)
		pinned.id = TitleCollection.topFourID
		let mine = TitleCollection(name: "Comfort")

		#expect(pinned.hasRoom(holding: 3))
		#expect(!pinned.hasRoom(holding: 4))
		#expect(mine.hasRoom(holding: 400))
		#expect(CollectionsFeed.countLabel(3, in: pinned) == "3 of 4")
		#expect(CollectionsFeed.countLabel(0, in: pinned) == "Nothing yet")
		#expect(CollectionsFeed.countLabel(3, in: mine) == "3 titles")
	}

	@Test func countsAndKindLinesRead() {
		#expect(CollectionsFeed.countLabel(0) == "Nothing yet")
		#expect(CollectionsFeed.countLabel(1) == "1 title")
		#expect(CollectionsFeed.countLabel(31) == "31 titles")
		#expect(CollectionsFeed.kindLine(isShow: true, episodes: 64, seasons: 1) == "TV Show · 64 episodes")
		#expect(CollectionsFeed.kindLine(isShow: true, episodes: 0, seasons: 2) == "TV Show · 2 seasons")
		#expect(CollectionsFeed.kindLine(isShow: true, episodes: 0, seasons: 0) == "TV Show")
		#expect(CollectionsFeed.kindLine(isShow: false, episodes: 0, seasons: 0) == "Film")
	}
}
