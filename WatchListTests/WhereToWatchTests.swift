//
//  WhereToWatchTests.swift
//  WatchListTests
//
//  How a country's JustWatch offers become the page's Stream / Rent / Buy
//  lines, and where each logo goes. A service in the wrong line tells you it
//  costs money when it doesn't, and a logo that opens nothing is a dead end.
//

import Foundation
import Testing
@testable import WatchList

@MainActor
struct WhereToWatchTests {

	private func provider(_ id: Int, _ name: String, priority: Int = 1) -> TMDbProvider {
		TMDbProvider(provider_id: id, provider_name: name, logo_path: "/\(id).jpg", display_priority: priority)
	}

	private func region(flatrate: [TMDbProvider]? = nil, free: [TMDbProvider]? = nil, ads: [TMDbProvider]? = nil,
	                    rent: [TMDbProvider]? = nil, buy: [TMDbProvider]? = nil) -> TMDbProviderRegion {
		TMDbProviderRegion(link: "https://www.themoviedb.org/movie/1/watch?locale=AE",
		                   flatrate: flatrate, free: free, ads: ads, rent: rent, buy: buy)
	}

	@Test func subscriptionFreeAndAdsAllStreamInPriorityOrder() {
		let options = WhereToWatch.options(region(flatrate: [provider(8, "Netflix", priority: 3)],
		                                          free: [provider(73, "Tubi TV", priority: 1)],
		                                          ads: [provider(613, "Amazon Prime Video Free with Ads", priority: 2)]),
		                                   title: "Heat")
		#expect(options.stream.map(\.providerID) == [73, 613, 8])
		#expect(options.rent.isEmpty && options.buy.isEmpty)
	}

	@Test func aServiceInTwoStreamGroupsIsListedOnce() {
		let options = WhereToWatch.options(region(flatrate: [provider(8, "Netflix")], ads: [provider(8, "Netflix")]),
		                                   title: "Heat")
		#expect(options.stream.count == 1)
	}

	@Test func rentAndBuyStaySeparate() {
		let options = WhereToWatch.options(region(rent: [provider(2, "Apple TV Store")],
		                                          buy: [provider(2, "Apple TV Store"), provider(3, "Google Play Movies")]),
		                                   title: "Heat")
		#expect(options.rent.map(\.providerID) == [2])
		#expect(options.buy.map(\.providerID) == [2, 3])
	}

	@Test func noCountryMeansNothing() {
		#expect(WhereToWatch.options(nil, title: "Heat").isEmpty)
	}

	@Test func knownServiceSearchesForTheTitle() {
		let url = WhereToWatch.link(providerID: 8, name: "Netflix", title: "Mr. & Mrs. Smith")
		#expect(url?.absoluteString == "https://www.netflix.com/search?q=Mr.%20%26%20Mrs.%20Smith")
	}

	@Test func serviceWithoutSearchOpensItsHome() {
		#expect(WhereToWatch.link(providerID: 629, name: "OSN+", title: "Heat")?.absoluteString == "https://osnplus.com")
	}

	@Test func channelsOpenTheAppTheyreSoldIn() {
		#expect(WhereToWatch.link(providerID: 1825, name: "HBO Max Amazon Channel", title: "Heat")?.host
		        == "www.primevideo.com")
		#expect(WhereToWatch.link(providerID: 1853, name: "Paramount Plus Apple TV Channel", title: "Heat")?.host
		        == "tv.apple.com")
	}

	@Test func unknownServiceFallsBackToTMDbsWatchPage() {
		#expect(WhereToWatch.link(providerID: 99999, name: "Somewhere", title: "Heat") == nil)
		let options = WhereToWatch.options(region(flatrate: [provider(99999, "Somewhere")]), title: "Heat")
		#expect(options.stream.first?.url?.host == "www.themoviedb.org")
	}
}
