//
//  FriendShareTests.swift
//  WatchListTests
//
//  Share with friends: a title's watchlist:// link and a collection's
//  .watchlist file each come back as what was sent, and a link someone has
//  tampered with can't smuggle in a rating the app doesn't have.
//

import Foundation
import Testing
@testable import WatchList

@MainActor
struct FriendShareTests {

	private let inception = SharedTitle(kind: .film, tmdbID: 27205, imdbID: "tt1375666", title: "Inception",
	                                    year: "2010", verdict: "Perfection", stars: 4.5,
	                                    note: "Watch it twice & listen for the kick?")

	@Test func aTitleLinkComesBackAsSent() throws {
		let link = try #require(FriendShare.link(for: inception, from: "Mohsin"))
		#expect(link.scheme == "watchlist" && link.host == "title")
		#expect(FriendShare.incoming(from: link) == .title(inception, from: "Mohsin"))
	}

	@Test func theMessageReadsWithoutTheApp() throws {
		let link = try #require(FriendShare.link(for: inception, from: nil))
		let message = FriendShare.message(for: inception, link: link)
		#expect(message.hasPrefix("Inception (2010)\nPerfection · 4.5 stars\n"))
		#expect(message.hasSuffix(link.absoluteString))
	}

	@Test func aTamperedLinkIsCleanedUp() throws {
		let url = try #require(URL(string: "watchlist://title?kind=show&tmdb=95396&title=Severance&verdict=Best%20Ever&stars=9"))
		guard case .title(let title, let from) = try #require(FriendShare.incoming(from: url)) else {
			Issue.record("Not a title")
			return
		}
		#expect(title.kind == .show && title.tmdbID == 95396)
		#expect(title.verdict == nil)
		#expect(title.stars == 5)
		#expect(from == nil)
		#expect(FriendShare.incoming(from: URL(string: "watchlist://title?kind=film")!) == nil)
		#expect(FriendShare.incoming(from: URL(string: "https://example.com/title?title=X")!) == nil)
	}

	@Test func aCollectionFileComesBackAsSent() throws {
		let collection = SharedCollection(name: "Weekend", from: "Mohsin", titles: [inception])
		let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
		let url = folder.appendingPathComponent(FriendShare.fileName(for: "Weekend: Part 1/2"))
		#expect(url.lastPathComponent == "Weekend Part 12.watchlist")
		try FriendShare.data(for: collection).write(to: url)
		#expect(FriendShare.incoming(from: url) == .collection(collection))
	}

	@Test func aFileFromANewerAppIsntMisread() {
		let newer = Data(#"{"version": 2, "name": "X", "titles": []}"#.utf8)
		#expect(FriendShare.collection(from: newer) == nil)
	}
}
