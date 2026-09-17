//
//  MessageView.swift
//  WatchList Watch App
//
//  A page with nothing to show yet: a symbol, a short line, a little more, and
//  at most one thing to do about it.
//

import SwiftUI

struct MessageView: View {
	let systemImage: String
	let title: String
	var detail: String?
	var actionTitle: String?
	var action: () -> Void = {}

	var body: some View {
		ScrollView {
			VStack(spacing: 6) {
				Image(systemName: systemImage)
					.font(.title2)
					.foregroundStyle(.secondary)
					.accessibilityHidden(true)
				Text(title)
					.font(.headline)
					.multilineTextAlignment(.center)
				if let detail {
					Text(detail)
						.font(.footnote)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
				}
				if let actionTitle {
					Button(actionTitle, action: action)
						.padding(.top, 4)
				}
			}
			.frame(maxWidth: .infinity)
			.padding(.top, 12)
		}
	}
}
