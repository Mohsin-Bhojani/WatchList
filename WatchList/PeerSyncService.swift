//
//  PeerSyncService.swift
//  WatchList
//
//  Local device-to-device transport over WiFi via MultipeerConnectivity. Each
//  device advertises and browses a "watchlist-sync" service; tapping Share on a
//  found peer invites it, and once connected both sides exchange their watched
//  lists (a LibrarySnapshot). Received snapshots are handed to `onReceive`.
//
//  Needs NSLocalNetworkUsageDescription + NSBonjourServices in Info.plist
//  (added via INFOPLIST_KEY_* build settings).
//

import SwiftUI
import Combine
@preconcurrency import MultipeerConnectivity
import UIKit

final class PeerSyncService: NSObject, ObservableObject {
	/// 1–15 chars, lowercase letters/digits/hyphens.
	static let serviceType = "watchlist-sync"

	@Published var discoveredPeers: [MCPeerID] = []
	@Published var connecting: Set<MCPeerID> = []
	@Published var isRunning = false

	nonisolated(unsafe) private var myPeerID: MCPeerID
	nonisolated(unsafe) private var session: MCSession
	nonisolated(unsafe) private var advertiser: MCNearbyServiceAdvertiser
	nonisolated(unsafe) private var browser: MCNearbyServiceBrowser

	/// Builds the outgoing snapshot (watched titles) from the local library.
	nonisolated(unsafe) var snapshotProvider: (() -> LibrarySnapshot)?
	/// Delivered a peer's snapshot on the main actor.
	nonisolated(unsafe) var onReceive: ((LibrarySnapshot) -> Void)?

	var myName: String { myPeerID.displayName }

	override init() {
		let peer = MCPeerID(displayName: PeerSyncService.deviceName())
		myPeerID = peer
		session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
		advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: nil, serviceType: PeerSyncService.serviceType)
		browser = MCNearbyServiceBrowser(peer: peer, serviceType: PeerSyncService.serviceType)
		super.init()
		session.delegate = self
		advertiser.delegate = self
		browser.delegate = self
	}

	static func deviceName() -> String {
		if let stored = UserDefaults.standard.string(forKey: "sharing.displayName"), !stored.isEmpty { return stored }
		return UIDevice.current.name
	}

	/// Change the name others see. Rebuilds the peer identity (an MCPeerID can't
	/// be renamed) and restarts if we were already advertising/browsing.
	func rename(to newName: String) {
		let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, trimmed != myPeerID.displayName else { return }
		UserDefaults.standard.set(trimmed, forKey: "sharing.displayName")
		let wasRunning = isRunning
		stop()
		let peer = MCPeerID(displayName: trimmed)
		myPeerID = peer
		session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
		advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: nil, serviceType: PeerSyncService.serviceType)
		browser = MCNearbyServiceBrowser(peer: peer, serviceType: PeerSyncService.serviceType)
		session.delegate = self
		advertiser.delegate = self
		browser.delegate = self
		objectWillChange.send()
		if wasRunning { start() }
	}

	func start() {
		advertiser.startAdvertisingPeer()
		browser.startBrowsingForPeers()
		isRunning = true
	}

	func stop() {
		advertiser.stopAdvertisingPeer()
		browser.stopBrowsingForPeers()
		session.disconnect()
		discoveredPeers.removeAll()
		connecting.removeAll()
		isRunning = false
	}

	/// Invite a found peer and (on connect) share our watched list.
	func share(with peer: MCPeerID) {
		connecting.insert(peer)
		browser.invitePeer(peer, to: session, withContext: nil, timeout: 25)
	}

	nonisolated private func sendSnapshot(to peers: [MCPeerID]) {
		guard !peers.isEmpty else { return }
		let provider = snapshotProvider
		Task { @MainActor in
			guard let snapshot = provider?(),
			      let data = try? JSONEncoder.snapshot.encode(snapshot) else { return }
			try? self.session.send(data, toPeers: peers, with: .reliable)
		}
	}
}

// MARK: - Advertiser

extension PeerSyncService: MCNearbyServiceAdvertiserDelegate {
	nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
	                            didReceiveInvitationFromPeer peerID: MCPeerID,
	                            withContext context: Data?,
	                            invitationHandler: @escaping (Bool, MCSession?) -> Void) {
		invitationHandler(true, session)   // accept; both sides just exchange watched lists
	}

	nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {}
}

// MARK: - Browser

extension PeerSyncService: MCNearbyServiceBrowserDelegate {
	nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
	                         withDiscoveryInfo info: [String: String]?) {
		Task { @MainActor in
			if !self.discoveredPeers.contains(peerID) { self.discoveredPeers.append(peerID) }
		}
	}

	nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
		Task { @MainActor in
			self.discoveredPeers.removeAll { $0 == peerID }
			self.connecting.remove(peerID)
		}
	}

	nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {}
}

// MARK: - Session

extension PeerSyncService: MCSessionDelegate {
	nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
		switch state {
		case .connected:
			sendSnapshot(to: [peerID])
			Task { @MainActor in self.connecting.remove(peerID) }
		case .notConnected:
			Task { @MainActor in self.connecting.remove(peerID) }
		default:
			break
		}
	}

	nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
		guard let snapshot = try? JSONDecoder.snapshot.decode(LibrarySnapshot.self, from: data) else { return }
		let handler = onReceive
		Task { @MainActor in handler?(snapshot) }
	}

	nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
	nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
	nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
