//
//  MediaPlayer.swift
//  WatchList
//
//  The app's video player: the system's own (AVPlayerViewController), full
//  screen, with its scrubber, subtitles and audio tracks, AirPlay and Picture
//  in Picture. It plays a PlayableStream from wherever one comes from — your
//  Jellyfin server (Jellyfin.swift) or put.io (Putio.swift) — picking up where
//  you left off, and tells the source where playback is as it goes.
//
//  Closing it after watching most of the title counts as having watched it:
//  the page that opened it marks the film or episode Watched.
//

import AVKit
import SwiftUI

/// Something to play, and whom to tell about it.
struct PlayableStream {
	let url: URL
	let title: String
	var subtitle: String?
	/// Where to start, in seconds: a resume point, or 0.
	var startAt: TimeInterval = 0
	var reporter: PlaybackReporter?
}

/// Told where a playback is as it goes — its source's own resume point and history.
protocol PlaybackReporter: AnyObject {
	func started(at seconds: TimeInterval) async
	func progress(at seconds: TimeInterval, paused: Bool) async
	/// `watched`: played through, by MediaPlayback.countsAsWatched.
	func stopped(at seconds: TimeInterval, watched: Bool) async
}

enum MediaPlayback {
	/// Watching this much of it counts as having watched it — the credits
	/// needn't be sat through. Jellyfin's own default is the same.
	static let watchedFraction = 0.9

	static func countsAsWatched(position: TimeInterval, duration: TimeInterval?) -> Bool {
		guard let duration, duration > 0, position.isFinite else { return false }
		return position >= duration * watchedFraction
	}

	/// Where to pick up from: nowhere for the first half-minute, or once it
	/// counts as watched — that starts it again from the top.
	static func resumePoint(position: TimeInterval, duration: TimeInterval?) -> TimeInterval? {
		guard position >= 30, !countsAsWatched(position: position, duration: duration) else { return nil }
		return position
	}

	/// "Resume from 1:04:12", "Resume from 12:30".
	static func clock(_ seconds: TimeInterval) -> String {
		let total = Int(seconds.rounded(.down))
		let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
		return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
	}
}

// MARK: - Playing

/// One playback, from the player opening until it closes — or until Picture
/// in Picture, which outlives the player's screen, ends.
@MainActor
final class MediaPlayer: NSObject, AVPlayerViewControllerDelegate {
	/// The playback on now; a new one ends it.
	private static var current: MediaPlayer?

	private let stream: PlayableStream
	private let onClose: (_ watched: Bool) -> Void
	private let player: AVPlayer
	private let controller = ClosingPlayerController()
	private var timeObserver: Any?
	private var endObserver: NSObjectProtocol?
	private var lastReport = Date.distantPast
	private var reachedEnd = false
	private var inPictureInPicture = false
	private var finished = false

	/// Plays the stream full screen, over whatever is showing. `onClose` is
	/// told, once it's over, whether it was watched through.
	static func play(_ stream: PlayableStream, onClose: @escaping (_ watched: Bool) -> Void = { _ in }) {
		current?.finish()
		let playback = MediaPlayer(stream: stream, onClose: onClose)
		current = playback
		playback.start()
	}

	private init(stream: PlayableStream, onClose: @escaping (Bool) -> Void) {
		self.stream = stream
		self.onClose = onClose
		let item = AVPlayerItem(url: stream.url)
		item.externalMetadata = [Self.metadata(.commonIdentifierTitle, stream.title),
		                         stream.subtitle.map { Self.metadata(.iTunesMetadataTrackSubTitle, $0) }]
			.compactMap { $0 }
		player = AVPlayer(playerItem: item)
		super.init()
	}

	private static func metadata(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
		let item = AVMutableMetadataItem()
		item.identifier = identifier
		item.value = value as NSString
		item.extendedLanguageTag = "und"
		return item.copy() as! AVMetadataItem
	}

	private func start() {
		try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
		try? AVAudioSession.sharedInstance().setActive(true)

		controller.player = player
		controller.delegate = self
		controller.allowsPictureInPicturePlayback = true
		controller.canStartPictureInPictureAutomaticallyFromInline = true
		controller.modalPresentationStyle = .fullScreen
		controller.onDismissed = { [weak self] in
			guard let self, !self.inPictureInPicture else { return }
			self.finish()
		}

		timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 1),
		                                              queue: .main) { [weak self] _ in
			MainActor.assumeIsolated { self?.tick() }
		}
		endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification,
		                                                     object: player.currentItem, queue: .main) { [weak self] _ in
			MainActor.assumeIsolated { self?.reachedEnd = true }
		}

		let startAt = stream.startAt
		if startAt > 0 {
			player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600),
			            toleranceBefore: .zero, toleranceAfter: .zero)
		}
		player.play()
		Self.topController()?.present(controller, animated: true)
		if let reporter = stream.reporter { Task { await reporter.started(at: startAt) } }
	}

	private var position: TimeInterval {
		let seconds = player.currentTime().seconds
		return seconds.isFinite ? seconds : 0
	}

	private var duration: TimeInterval? {
		guard let seconds = player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 else { return nil }
		return seconds
	}

	/// Every second; the source hears about it every ten.
	private func tick() {
		guard !finished, let reporter = stream.reporter, Date.now.timeIntervalSince(lastReport) >= 10 else { return }
		lastReport = .now
		let (position, paused) = (position, player.timeControlStatus == .paused)
		Task { await reporter.progress(at: position, paused: paused) }
	}

	private func finish() {
		guard !finished else { return }
		finished = true
		let position = position
		let watched = reachedEnd || MediaPlayback.countsAsWatched(position: position, duration: duration)
		player.pause()
		if let timeObserver { player.removeTimeObserver(timeObserver) }
		if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
		if let reporter = stream.reporter { Task { await reporter.stopped(at: position, watched: watched) } }
		if controller.presentingViewController != nil { controller.dismiss(animated: true) }
		try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
		if Self.current === self { Self.current = nil }
		onClose(watched)
	}

	// MARK: Picture in Picture

	nonisolated func playerViewControllerWillStartPictureInPicture(_ controller: AVPlayerViewController) {
		MainActor.assumeIsolated { inPictureInPicture = true }
	}

	/// Closed from its little window rather than sent back to full screen.
	nonisolated func playerViewControllerDidStopPictureInPicture(_ controller: AVPlayerViewController) {
		MainActor.assumeIsolated {
			inPictureInPicture = false
			if self.controller.presentingViewController == nil { finish() }
		}
	}

	/// Back to full screen from the little window.
	nonisolated func playerViewController(_ playerViewController: AVPlayerViewController,
	                                      restoreUserInterfaceForPictureInPictureStopWithCompletionHandler
	                                      completionHandler: @escaping (Bool) -> Void) {
		MainActor.assumeIsolated {
			guard controller.presentingViewController == nil, let top = Self.topController() else {
				completionHandler(true)
				return
			}
			top.present(controller, animated: true) { completionHandler(true) }
		}
	}

	private static func topController() -> UIViewController? {
		let window = UIApplication.shared.connectedScenes
			.compactMap { $0 as? UIWindowScene }
			.flatMap(\.windows)
			.first { $0.isKeyWindow }
		var top = window?.rootViewController
		while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
		return top
	}
}

/// The system player, telling its owner when its close button took it away.
private final class ClosingPlayerController: AVPlayerViewController {
	var onDismissed: (() -> Void)?

	override func viewDidDisappear(_ animated: Bool) {
		super.viewDidDisappear(animated)
		if isBeingDismissed || presentingViewController == nil { onDismissed?() }
	}
}
