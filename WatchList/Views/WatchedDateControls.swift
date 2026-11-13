//
//  WatchedDateControls.swift
//  WatchList
//
//  Saying when something was watched, for the times it's marked later than it
//  was seen: a capsule under a title page's status switch that reads "Watched
//  yesterday" and opens Today / Yesterday / A week ago / A month ago or a
//  calendar, and the same choices as a menu section for episode rows.
//

import SwiftUI
import WatchListCore
import WatchListLibrary

/// The capsule under a watched title's status switch: when it was watched,
/// and a menu to change it.
struct WatchedDateButton: View {
	/// When it was watched; nil reads as "Set watched date".
	let date: Date?
	/// What a choice is applied to — a title, or a season's episodes.
	var prompt = "When did you watch it?"
	let apply: (Date) -> Void

	@State private var picking = false

	var body: some View {
		Menu {
			Section(prompt) {
				WatchedWhenButtons(apply: apply)
			}
			Button("Pick a Date…", systemImage: "calendar") { picking = true }
		} label: {
			HStack(spacing: 6) {
				Image(systemName: "calendar")
					.font(.system(.caption, weight: .semibold))
				Text(date.map { WatchedWhen.label(for: $0) } ?? "Set watched date")
				Image(systemName: "chevron.up.chevron.down")
					.font(.system(.caption2, weight: .semibold))
					.foregroundStyle(.white.opacity(0.6))
			}
			.font(.system(.footnote, weight: .semibold))
			.foregroundStyle(.white)
			.padding(.horizontal, 14)
			.frame(minHeight: 36)
			.glassEffect(.regular.interactive(), in: Capsule())
		}
		.accessibilityLabel(date.map { WatchedWhen.label(for: $0) } ?? "Set watched date")
		.accessibilityHint("Changes when it was watched")
		.sheet(isPresented: $picking) {
			WatchedDateSheet(initial: date ?? .now) { picked in
				apply(picked)
				Haptics.selection()
			}
		}
	}
}

/// Today, Yesterday, A week ago and A month ago, as buttons for any menu.
struct WatchedWhenButtons: View {
	let apply: (Date) -> Void

	var body: some View {
		ForEach(WatchedWhen.allCases) { when in
			Button(when.title) {
				Haptics.selection()
				withAnimation(Glass.smooth) { apply(when.date()) }
			}
		}
	}
}

/// A calendar for any day up to today.
struct WatchedDateSheet: View {
	let save: (Date) -> Void

	@Environment(\.dismiss) private var dismiss
	@State private var date: Date

	init(initial: Date, save: @escaping (Date) -> Void) {
		self.save = save
		_date = State(initialValue: min(initial, .now))
	}

	var body: some View {
		NavigationStack {
			DatePicker("Watched on", selection: $date, in: ...Date.now, displayedComponents: .date)
				.datePickerStyle(.graphical)
				.padding(.horizontal)
				.navigationTitle("Watched On")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .cancellationAction) {
						Button("Cancel", systemImage: "xmark", role: .cancel) { dismiss() }
					}
					ToolbarItem(placement: .confirmationAction) {
						Button("Done", systemImage: "checkmark", role: .confirm) {
							withAnimation(Glass.smooth) { save(date) }
							dismiss()
						}
					}
				}
		}
		.presentationDetents([.medium, .large])
	}
}

/// An episode row's context menu items: Mark Watched or Unwatched, and a
/// submenu to mark it — or move it — to yesterday, a week or a month back.
struct EpisodeWatchedMenuItems: View {
	let episode: Episode

	var body: some View {
		let watched = episode.status == .watched
		Button(watched ? "Mark Unwatched" : "Mark Watched",
		       systemImage: watched ? "circle" : "checkmark.circle") {
			withAnimation(Glass.smooth) { watched ? episode.mark(.toWatch) : episode.markWatched() }
		}
		Menu(watched ? "Change Watched Date" : "Mark Watched On…", systemImage: "calendar") {
			WatchedWhenButtons { date in
				watched ? episode.setWatchedDate(date) : episode.markWatched(at: date)
			}
		}
	}
}
