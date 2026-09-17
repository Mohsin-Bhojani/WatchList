//
//  PhoneSync.swift
//  WatchList Watch App
//
//  The watch's end of the link with the iPhone app (Shared/WatchLink.swift) —
//  the one place the watch app talks to WatchConnectivity:
//    - snapshots arrive as the application context, and are kept by WatchStore
//    - each action taken here goes with transferUserInfo, which queues it and
//      delivers it whenever the iPhone is next there. Until the session is
//      active, or while the iPhone app isn't installed, actions wait in the
//      store's outbox and go when that changes.
//    - while the iPhone is reachable, a refresh message asks for a snapshot
//      there and then: as the app opens, and when the iPhone comes back
//

import Foundation
import OSLog
import WatchConnectivity

@MainActor
final class PhoneSync: NSObject {
	private let store: WatchStore
	private let log = Logger(subsystem: "com.mohsin.WatchList.watchkitapp", category: "PhoneSync")

	init(store: WatchStore) {
		self.store = store
		super.init()
		store.onRecord = { [weak self] in self?.flush() }
	}

	func start() {
		guard WCSession.isSupported() else { return }
		WCSession.default.delegate = self
		WCSession.default.activate()
	}

	/// Hands the outbox's unsent actions to WatchConnectivity, in order.
	func flush() {
		let session = WCSession.default
		guard session.activationState == .activated, session.isCompanionAppInstalled else { return }
		let unsent = store.outbox.unsent
		guard !unsent.isEmpty else { return }
		var handed = Set<UUID>()
		for action in unsent {
			guard let data = WatchLink.pack(action) else { continue }
			session.transferUserInfo([WatchLink.actionKey: data])
			handed.insert(action.id)
		}
		store.markHandedOver(handed)
	}

	/// Asks the iPhone for a snapshot now, when it can answer now.
	func refresh() {
		let session = WCSession.default
		guard session.activationState == .activated, session.isCompanionAppInstalled, session.isReachable else { return }
		session.sendMessage([WatchLink.refreshKey: true], replyHandler: { reply in
			guard let data = reply[WatchLink.snapshotKey] as? Data else { return }
			Task { @MainActor in self.store.receive(packed: data) }
		}, errorHandler: { error in
			let message = error.localizedDescription
			Task { @MainActor in self.log.info("Refresh went unanswered: \(message, privacy: .public)") }
		})
	}

	fileprivate func update(installed: Bool, reachable: Bool) {
		store.phone = installed ? .installed : .notInstalled
		store.phoneIsReachable = reachable
	}
}

extension PhoneSync: WCSessionDelegate {
	nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
	                         error: Error?) {
		let context = session.receivedApplicationContext[WatchLink.snapshotKey] as? Data
		let activated = activationState == .activated
		let installed = session.isCompanionAppInstalled
		let reachable = session.isReachable
		let message = error?.localizedDescription
		Task { @MainActor in
			if let message { self.log.error("Session activation failed: \(message, privacy: .public)") }
			guard activated else { return }
			self.update(installed: installed, reachable: reachable)
			if let context { self.store.receive(packed: context) }
			self.flush()
			self.refresh()
		}
	}

	nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
		guard let data = applicationContext[WatchLink.snapshotKey] as? Data else { return }
		Task { @MainActor in self.store.receive(packed: data) }
	}

	/// The iPhone app installed, or removed.
	nonisolated func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
		let installed = session.isCompanionAppInstalled
		let reachable = session.isReachable
		Task { @MainActor in
			self.update(installed: installed, reachable: reachable)
			self.flush()
		}
	}

	nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
		let installed = session.isCompanionAppInstalled
		let reachable = session.isReachable
		Task { @MainActor in
			let cameBack = reachable && !self.store.phoneIsReachable
			self.update(installed: installed, reachable: reachable)
			if cameBack { self.refresh() }
		}
	}
}
