//
//  PutioTests.swift
//  WatchListTests
//
//  Finding an episode in a show's linked put.io folder, from its file names
//  alone. A name read wrong plays the wrong episode — or, worse, a year or a
//  resolution taken for an episode number.
//

import Foundation
import Testing
@testable import WatchList

@MainActor
struct PutioTests {

	private func number(_ name: String) -> EpisodeNumber? { PutioEpisodes.number(in: name) }

	@Test func commonNamings() {
		#expect(number("Severance.S01E03.1080p.WEB.mkv") == EpisodeNumber(season: 1, first: 3, last: 3))
		#expect(number("severance s2e10.mp4") == EpisodeNumber(season: 2, first: 10, last: 10))
		#expect(number("Severance - S01 E04 - In Perpetuity.mkv") == EpisodeNumber(season: 1, first: 4, last: 4))
		#expect(number("The Office 3x12.avi") == EpisodeNumber(season: 3, first: 12, last: 12))
	}

	@Test func doubleEpisodes() {
		#expect(number("Show.S02E05-E06.mkv") == EpisodeNumber(season: 2, first: 5, last: 6))
		#expect(number("Show.S02E05E06.mkv") == EpisodeNumber(season: 2, first: 5, last: 6))
		#expect(number("Show.S02E05E06.mkv")?.contains(season: 2, episode: 6) == true)
	}

	@Test func yearsAndResolutionsAreNotEpisodes() {
		#expect(number("Inception (2010) 1080p.mkv") == nil)
		#expect(number("Film.1920x1080.mp4") == nil)
		#expect(number("Trailer.mp4") == nil)
	}

	@Test func matchFindsTheEpisodeAmongAFoldersVideos() {
		let files = [PutioFile(id: 1, name: "Show.S01E01.mkv", fileType: "VIDEO"),
		             PutioFile(id: 2, name: "Show.S01E02-E03.mkv", fileType: "VIDEO"),
		             PutioFile(id: 3, name: "Show.S02E01.mkv", fileType: "VIDEO"),
		             PutioFile(id: 4, name: "Sample.mkv", fileType: "VIDEO")]
		#expect(PutioEpisodes.match(files, season: 1, episode: 3)?.id == 2)
		#expect(PutioEpisodes.match(files, season: 2, episode: 1)?.id == 3)
		#expect(PutioEpisodes.match(files, season: 3, episode: 1) == nil)
	}

	@Test func putioFilesDecode() throws {
		let json = #"{"files":[{"id":7,"name":"Show","file_type":"FOLDER","parent_id":0,"size":0},{"id":8,"name":"a.mkv","file_type":"VIDEO","parent_id":7,"size":1234,"screenshot":"https://x/y.jpg"}],"cursor":null}"#
		struct Page: Decodable { let files: [PutioFile] }
		let files = try JSONDecoder().decode(Page.self, from: Data(json.utf8)).files
		#expect(files.map(\.isFolder) == [true, false])
		#expect(files[1].isVideo && files[1].size == 1234 && files[1].screenshot == "https://x/y.jpg")
	}
}
