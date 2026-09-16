//
//  ProfileStoreTests.swift
//  WatchListTests
//
//  The profile behind Home's profile sheet: what a nickname is cleaned to,
//  the letter the avatar shows, and that a saved profile — photo included —
//  is still there on the next launch.
//

import Foundation
import Testing
import UIKit
@testable import WatchList

@MainActor
struct ProfileStoreTests {

	@Test func nicknamesAreTrimmedAndCapped() {
		#expect(ProfileStore.cleaned("  Zero Mental \n") == "Zero Mental")
		#expect(ProfileStore.cleaned(String(repeating: "a", count: 50)).count == ProfileStore.maxNicknameLength)
	}

	@Test func theAvatarShowsTheFirstLetter() {
		#expect(ProfileStore.initial(of: " zeroMental") == "Z")
		#expect(ProfileStore.initial(of: "   ") == nil)
	}

	@Test func aSavedProfileIsThereNextLaunch() throws {
		let suite = "ProfileStoreTests-\(UUID().uuidString)"
		let defaults = try #require(UserDefaults(suiteName: suite))
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
		defer {
			defaults.removePersistentDomain(forName: suite)
			try? FileManager.default.removeItem(at: directory)
		}

		let photo = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 600)).image { context in
			UIColor.systemPink.setFill()
			context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
		}
		ProfileStore(defaults: defaults, directory: directory).save(nickname: " ZeroMental ", avatar: photo)

		let relaunched = ProfileStore(defaults: defaults, directory: directory)
		#expect(relaunched.nickname == "ZeroMental")
		let avatar = try #require(relaunched.avatar)
		#expect(avatar.size.width == ProfileStore.avatarSide)
		#expect(avatar.size.height == ProfileStore.avatarSide)

		relaunched.save(nickname: "ZeroMental", avatar: nil)
		#expect(ProfileStore(defaults: defaults, directory: directory).avatar == nil)
	}
}
