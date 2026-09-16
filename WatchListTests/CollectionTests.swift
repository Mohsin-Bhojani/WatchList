//
//  CollectionTests.swift
//  WatchListTests
//
//  Your own collections: naming them, and putting titles in and taking them out.
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
}
