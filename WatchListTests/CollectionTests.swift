//
//  CollectionTests.swift
//  WatchListTests
//
//  Your own collections: naming them, putting titles in and taking them out,
//  and putting them in order.
//

import Foundation
import Testing
@testable import WatchList

@MainActor
struct CollectionTests {

	@Test func namesAreTrimmedCappedAndNeverBlank() {
		#expect(TitleCollection.cleaned("  Comfort Movies  ") == "Comfort Movies")
		#expect(TitleCollection.cleaned(String(repeating: "x", count: 60)).count == TitleCollection.maxNameLength)

		let collection = TitleCollection(name: "Comfort")
		collection.rename(to: " ")
		#expect(collection.name == "Comfort")
		collection.rename(to: "Rainy Sunday")
		#expect(collection.name == "Rainy Sunday")
	}

	@Test func titlesGoInOnceInTheOrderAddedAndComeOut() {
		let collection = TitleCollection(name: "Top 20 Anime")
		let first = UUID(), second = UUID()

		collection.set(first, included: true)
		collection.set(second, included: true)
		collection.set(first, included: true)   // already in
		#expect(collection.titleIDs == [first, second])
		#expect(collection.contains(second))

		collection.set(first, included: false)
		#expect(collection.titleIDs == [second])
	}

	@Test func reorderingKeepsHiddenTitlesAtTheEndAndIgnoresStrangers() {
		let a = UUID(), b = UUID(), c = UUID(), gone = UUID(), stranger = UUID()
		let collection = TitleCollection(name: "Weekend", titleIDs: [a, gone, b, c])

		// `gone` left the library, so the sheet never showed it.
		collection.reorder([c, a, stranger, b])
		#expect(collection.titleIDs == [c, a, b, gone])

		// Moving one back again, and adding later, still goes on the end.
		collection.reorder([a, b, c])
		collection.set(stranger, included: true)
		#expect(collection.titleIDs == [a, b, c, gone, stranger])
	}
}
