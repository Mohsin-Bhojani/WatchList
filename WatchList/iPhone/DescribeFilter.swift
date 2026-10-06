//
//  DescribeFilter.swift
//  WatchList
//
//  Describe, below Genre in Discover's filter: a line to say what you're in the
//  mood for, and what it was read as. Asking sets the filter's description,
//  which Discover answers with swipe cards of its own (DescribeSearch.swift).
//

import SwiftUI

struct DescribeFilter: View {
	@Binding var draft: String
	/// The description Discover is showing matches for; empty when it isn't.
	let applied: String
	let session: DescribeSession
	/// Asks for a description, or with "" clears it.
	let ask: (String) -> Void

	@FocusState private var focused: Bool

	private var canAsk: Bool {
		let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
		return !trimmed.isEmpty && trimmed != applied
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			FilterHeading("Describe")
			HStack(spacing: 8) {
				TextField("Something romantic, no sad ending\u{2026}", text: $draft, axis: .vertical)
					.lineLimit(1...3)
					.font(.system(size: 15))
					.focused($focused)
					.submitLabel(.search)
					.onSubmit(submit)
				if !applied.isEmpty {
					Button {
						Haptics.selection()
						draft = ""
						ask("")
					} label: {
						Image(systemName: "xmark.circle.fill")
							.foregroundStyle(.secondary)
					}
					.buttonStyle(.plain)
					.accessibilityLabel("Clear description")
				}
			}
			.padding(12)
			.background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

			HStack(spacing: 8) {
				status
				Spacer(minLength: 8)
				Button("Find", action: submit)
					.buttonStyle(.glassProminent)
					.controlSize(.small)
					.disabled(!canAsk)
			}
		}
	}

	/// What it was read as, or how it will be.
	private var status: some View {
		statusLine
			.font(.system(size: 12, weight: .medium))
			.foregroundStyle(.secondary)
			.lineLimit(2)
	}

	@ViewBuilder private var statusLine: some View {
		switch session.phase {
		case .working:
			Label("Reading\u{2026}", systemImage: "sparkles")
		case .ready, .failed:
			if let query = session.query, !query.isEmpty {
				Label("Read as \(query.summary)", systemImage: session.usedModel ? "apple.intelligence" : "text.magnifyingglass")
			}
		case .idle:
			Label(DescribeInterpreter.onDeviceAvailable ? "Read on this device" : "Simple word matching on this device",
			      systemImage: DescribeInterpreter.onDeviceAvailable ? "apple.intelligence" : "text.magnifyingglass")
		}
	}

	private func submit() {
		let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		focused = false
		Haptics.selection()
		ask(trimmed)
	}
}
