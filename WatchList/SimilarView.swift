//
//  SimilarView.swift
//  WatchList
//
//  Suggestions built from your own ratings: Claude reads what you called
//  Perfection and Go For It (and what you skipped), proposes titles, and each
//  one is resolved against TMDb so "＋" imports it through the normal path.
//
//  Cache-first: whatever was suggested last time shows immediately, even with
//  the Mac helper asleep. See SimilarLoader for the refresh policy.
//

import SwiftData
import SwiftUI

struct SimilarView: View {
	@Environment(\.modelContext) private var ctx
	@Environment(\.dismiss) private var dismiss

	@Query(sort: \Show.dateAdded, order: .reverse) private var shows: [Show]
	@Query(sort: \Film.dateAdded, order: .reverse) private var films: [Film]
	@Query(sort: \Suggestion.rank) private var suggestions: [Suggestion]

	@State private var loading = false
	@State private var outcome: SimilarLoader.Outcome?
	@State private var adding: Set<UUID> = []

	/// Anything already in the library is hidden rather than shown as "Added" —
	/// this is a discovery list, so a row you can't act on is just noise.
	private var visible: [Suggestion] {
		suggestions.filter { !inLibrary($0) }
	}

	var body: some View {
		NavigationStack {
			ZStack {
				GlassBackground()
				ScrollView {
					VStack(alignment: .leading, spacing: 14) {
						header
						if loading && suggestions.isEmpty {
							loadingCard
						} else if case .needsRatings = outcome {
							EmptyState(icon: "star",
							           title: "Rate a few things first",
							           subtitle: "Mark some watched titles Perfection or Go For It and suggestions will appear here.")
								.padding(.top, 30)
						} else if suggestions.isEmpty {
							emptyOrError
						} else {
							if case .stale(let why) = outcome { staleBanner(why) }
							if visible.isEmpty {
								EmptyState(icon: "checkmark.circle",
								           title: "All caught up",
								           subtitle: "Everything suggested is already in your list. Pull to refresh for more.")
									.padding(.top, 20)
							} else {
								ForEach(visible) { row($0) }
									.transition(.opacity.combined(with: .move(edge: .leading)))
							}
						}
					}
					.padding(18)
				}
			}
			.navigationTitle("Similar")
			.navigationBarTitleDisplayMode(.inline)
			.toolbarBackground(.hidden, for: .navigationBar)
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Button {
						Haptics.tap()
						Task { await refresh(force: true) }
					} label: {
						Image(systemName: "arrow.clockwise")
							.font(.system(size: 16, weight: .semibold))
							.foregroundStyle(Glass.accent)
					}
					.disabled(loading)
				}
				ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
			}
			.refreshable { await refresh(force: true) }
			.task { await refresh(force: false) }
		}
	}

	// MARK: Pieces

	private var header: some View {
		VStack(alignment: .leading, spacing: 6) {
			SectionLabel(text: "Based on your ratings", systemImage: "sparkles")
			Text(basisLine)
				.font(.system(size: 12, weight: .medium, design: .rounded))
				.foregroundStyle(.secondary)
		}
	}

	private var basisLine: String {
		let loved = shows.filter { $0.rating == .perfection }.count + films.filter { $0.rating == .perfection }.count
		let liked = shows.filter { $0.rating == .goForIt }.count + films.filter { $0.rating == .goForIt }.count
		if loved + liked == 0 { return "Nothing rated yet." }
		return "From \(loved) Perfection and \(liked) Go For It \(loved + liked == 1 ? "title" : "titles")."
	}

	private var loadingCard: some View {
		HStack(spacing: 10) {
			ProgressView()
			Text("Asking your Mac for suggestions…")
				.font(.system(size: 13, weight: .medium, design: .rounded))
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(16)
		.glass(cornerRadius: 18)
	}

	private func staleBanner(_ why: String) -> some View {
		HStack(alignment: .top, spacing: 8) {
			Image(systemName: "exclamationmark.triangle.fill")
				.font(.system(size: 12, weight: .semibold))
				.foregroundStyle(Glass.toWatch)
			Text("Showing your last suggestions — \(why)")
				.font(.system(size: 12, weight: .medium, design: .rounded))
				.foregroundStyle(.secondary)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.padding(12)
		.glass(cornerRadius: 14)
	}

	@ViewBuilder private var emptyOrError: some View {
		if case .stale(let why) = outcome {
			EmptyState(icon: "wifi.exclamationmark", title: "No suggestions yet", subtitle: why)
				.padding(.top, 30)
		} else {
			EmptyState(icon: "sparkles",
			           title: "No suggestions yet",
			           subtitle: "Pull to refresh once the helper is running on your Mac.")
				.padding(.top, 30)
		}
	}

	private func row(_ s: Suggestion) -> some View {
		HStack(spacing: 11) {
			PosterImage(urlString: s.posterURL, systemPlaceholder: s.kind.systemImage)
				.frame(width: 54, height: 78)
				.clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

			VStack(alignment: .leading, spacing: 3) {
				Text(s.title)
					.font(Glass.serif(15))
					.lineLimit(2)
				Text(s.subtitle)
					.font(.system(size: 12, weight: .medium, design: .rounded))
					.foregroundStyle(.secondary)
				if !s.reason.isEmpty {
					Text(s.reason)
						.font(.system(size: 13, weight: .regular, design: .rounded))
						.foregroundStyle(.secondary)
						.fixedSize(horizontal: false, vertical: true)
				}
			}

			Spacer(minLength: 6)
			addControl(s)
		}
		.padding(10)
		.glass(cornerRadius: 16)
	}

	@ViewBuilder private func addControl(_ s: Suggestion) -> some View {
		if adding.contains(s.id) {
			ProgressView().frame(width: 34, height: 34)
		} else if s.isAddable {
			Button {
				add(s)
			} label: {
				Image(systemName: "plus")
					.font(.system(size: 15, weight: .bold))
					.foregroundStyle(.white)
					.frame(width: 34, height: 34)
					.background(Circle().fill(Glass.accent))
			}
			.buttonStyle(.pressable)
		} else if s.resolved {
			// Claude suggested something TMDb doesn't have — say so rather
			// than offering a button that can't work.
			Text("Not on TMDb")
				.font(.system(size: 10, weight: .semibold, design: .rounded))
				.foregroundStyle(.secondary)
				.frame(width: 52)
				.multilineTextAlignment(.center)
		} else {
			ProgressView().frame(width: 34, height: 34)
		}
	}

	// MARK: Actions

	private func refresh(force: Bool) async {
		guard !loading else { return }
		loading = true
		outcome = await SimilarLoader.refreshIfNeeded(shows: shows,
		                                              films: films,
		                                              cached: suggestions,
		                                              into: ctx,
		                                              force: force)
		loading = false
	}

	/// Re-fetched fresh through the normal import path, so it lands as
	/// To Watch and unrated — same as adding it by hand.
	///
	/// On success the row leaves the list (inLibrary starts matching it); on
	/// failure nothing is inserted, so the row stays and can be retried.
	private func add(_ s: Suggestion) {
		guard let tmdbID = s.tmdbID else { return }
		adding.insert(s.id)
		Haptics.tap(.medium)
		Task {
			let importer = ImportCoordinator()
			// A show pulls every season and episode, so this can take a few
			// seconds — the spinner covers the whole await.
			let imported = await importer.importFromTMDb(id: tmdbID, kind: s.kind, into: ctx)
			withAnimation(Glass.smooth) { adding.remove(s.id) }
			imported == nil ? Haptics.warning() : Haptics.success()
		}
	}

	// MARK: Dedupe

	/// Mirrors the id-first matching the old Nearby sheet used, plus a title
	/// fallback for suggestions TMDb hasn't resolved yet.
	private func inLibrary(_ s: Suggestion) -> Bool {
		switch s.kind {
		case .show: return shows.contains { matches(s, tmdbID: $0.tmdbID, imdbID: $0.imdbID, title: $0.title, year: $0.firstAirYear) }
		case .film: return films.contains { matches(s, tmdbID: $0.tmdbID, imdbID: $0.imdbID, title: $0.title, year: $0.year) }
		}
	}

	private func matches(_ s: Suggestion, tmdbID: Int?, imdbID: String?, title: String, year: String) -> Bool {
		if let a = s.tmdbID, let b = tmdbID, a == b { return true }
		if let a = s.imdbID, !a.isEmpty, a == imdbID { return true }
		// Unresolved suggestions have no ids yet, so fall back to the title —
		// with the year as a tiebreak when both sides have one.
		if s.tmdbID == nil,
		   s.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame,
		   s.year.isEmpty || year.isEmpty || s.year == year {
			return true
		}
		return false
	}
}
