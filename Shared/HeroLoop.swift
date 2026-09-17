//
//  HeroLoop.swift
//  WatchList
//
//  The page arithmetic that lets Up Next go round: the iPhone's Home hero and
//  the watch's Up Next both use it. Compiled into both apps.
//

import Foundation

/// Page arithmetic for the Home hero's loop. The shows run in order with the
/// last one copied in front and the first copied after, so a swipe past either
/// end lands on a copy — which, once the scroll comes to rest, is swapped
/// without animation for the real page it copies. One show doesn't loop.
enum HeroLoop {
	/// Which show each page holds, as indices into the Watching list.
	static func pages(count: Int) -> [Int] {
		guard count > 1 else { return Array(0..<max(count, 0)) }
		return [count - 1] + Array(0..<count) + [0]
	}

	/// The page the hero opens on: the first real one.
	static func start(count: Int) -> Int { count > 1 ? 1 : 0 }

	/// Where a page that came to rest should really be: a copy's real page, or
	/// itself. Also brings back a page a shorter list has left out of range.
	static func settled(_ page: Int, count: Int) -> Int {
		guard count > 1 else { return 0 }
		let page = min(max(page, 0), count + 1)
		if page == 0 { return count }
		if page == count + 1 { return 1 }
		return page
	}

	/// The show a page holds — what the page dots follow.
	static func showIndex(ofPage page: Int, count: Int) -> Int {
		let pages = pages(count: count)
		guard !pages.isEmpty else { return 0 }
		return pages[min(max(page, 0), pages.count - 1)]
	}
}
