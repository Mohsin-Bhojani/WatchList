//
//  DiscoverPage.swift
//  WatchList Watch App
//
//  Discover, a Crown turn below Up Next, in the iPhone's Discover colours: one
//  poster at a time on a gradient of its own colour, and nothing else. The watch
//  fetches the suggestions from TMDb itself, for the titles the iPhone sent,
//  and deals them as the iPhone's Discover does (Shared/DiscoverQueue.swift).
//    - tap the poster for the rest of the iPhone's card — why it's suggested,
//      TMDb's stars, the verdict and kind, the synopsis — with the three
//      decisions as buttons
//    - swipe right to add it to To Watch, left if not interested, up for later;
//      the poster says which as it goes, with a tick as it passes the point of
//      deciding, as the iPhone's card does
//    - swipe down, or turn the Crown back, for Up Next
//    - Filter, top left: TV shows, films or both, genres, and More like
//

import SwiftUI

struct DiscoverPage: View {
	@Environment(WatchStore.self) private var store
	@Binding var page: WatchPage

	@State private var drag: CGSize = .zero
	/// Set while a decided card flies off, so it can't be decided twice.
	@State private var flying = false
	@State private var detail: Suggestion?
	@State private var showingFilter = false
	/// Each poster's colour, once it's in.
	@State private var tones: [String: Color] = [:]

	/// How far a swipe goes to decide, in points: the iPhone's card needs 120.
	private static let threshold: CGFloat = 44

	/// When the deal needs topping up from TMDb.
	private struct FillTrigger: Equatable {
		let seeds: [UUID]
		let runningLow: Bool
		let fetched: Int
		let filter: DiscoverFilter
	}

	var body: some View {
		let deal = store.deal
		content(deal)
			.containerBackground(for: .tabView) { backdrop(deal.current) }
			.toolbar {
				ToolbarItem(placement: .topBarLeading) { filterButton }
			}
			.sheet(item: $detail) { suggestion in
				SuggestionDetailView(suggestion: suggestion, reason: store.reason(for: suggestion),
				                     tone: tone(for: suggestion)) { decision in
					detail = nil
					Task {
						// Once the sheet is away, so the card is seen to go.
						try? await Task.sleep(for: .milliseconds(350))
						commit(decision, suggestion)
					}
				}
			}
			.sheet(isPresented: $showingFilter) {
				DiscoverFilterView()
			}
			.task { await store.loader.loadGenres() }
			.onChange(of: FillTrigger(seeds: deal.seedOrder, runningLow: deal.ready < DiscoverFeed.readyAhead,
			                          fetched: store.loader.fetched.count, filter: store.filter), initial: true) {
				Task { await store.fill(deal) }
			}
			.onChange(of: deal.queue.prefix(3).map(\.posterURL)) { _, urls in
				Artwork.prefetch(urls.map(Artwork.poster))
			}
	}

	@ViewBuilder
	private func content(_ deal: DiscoverDeal<DiscoverSeed>) -> some View {
		if let current = deal.current {
			PosterCard(suggestion: current) { tones[current.id] = $0 }
				.overlay { stamp }
				.offset(drag)
				.rotationEffect(.degrees(Double(drag.width) / 12), anchor: .bottom)
				.onTapGesture { detail = current }
				.highPriorityGesture(swipe(current))
				.id(current.id)
				.transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)), removal: .opacity))
				.accessibilityElement(children: .ignore)
				.accessibilityLabel(current.title)
				.accessibilityHint("Shows the synopsis")
				.accessibilityAddTraits(.isButton)
				.accessibilityActions {
					ForEach([CardDecision.add, .notInterested, .later], id: \.self) { decision in
						Button(decision.label) { commit(decision, current) }
					}
				}
				.padding(.horizontal, 6)
				.padding(.bottom, 6)
				.ignoresSafeArea(edges: .bottom)
		} else {
			emptyMessage(deal)
		}
	}

	/// The iPhone's Discover backdrop: the poster's colour, deepening downwards.
	/// Black while there's no card.
	@ViewBuilder
	private func backdrop(_ current: Suggestion?) -> some View {
		if let current {
			let base = tone(for: current)
			LinearGradient(colors: [base, Artwork.deeper(base)], startPoint: .top, endPoint: .bottom)
		} else {
			Color.black
		}
	}

	private var filterButton: some View {
		Button { showingFilter = true } label: {
			Image(systemName: store.filter.isDefault ? "line.3.horizontal.decrease"
			                                         : "line.3.horizontal.decrease.circle.fill")
		}
		// Plain glass rather than the red accent, which fights the poster's colour.
		.tint(.white.opacity(0.35))
		.accessibilityLabel(store.filter.isDefault ? "Filter" : "Filter, on")
	}

	// MARK: Swiping

	/// What the card is about to decide, stamped on the poster and firming up as
	/// it nears the point of deciding — the iPhone card's stamp.
	@ViewBuilder
	private var stamp: some View {
		if let lean = CardDecision.leaning(drag, threshold: Self.threshold) {
			Label(lean.decision.swipeLabel, systemImage: lean.decision.symbol)
				.font(.system(size: 13, weight: .heavy))
				.foregroundStyle(.white)
				.lineLimit(1)
				.padding(.horizontal, 11)
				.padding(.vertical, 6)
				.background(stampColor(lean.decision), in: Capsule())
				.scaleEffect(0.85 + 0.15 * lean.progress)
				.opacity(Double(lean.progress))
				.allowsHitTesting(false)
		}
	}

	/// The iPhone's: Perfection's green for Add, Skip's red for Not interested.
	private func stampColor(_ decision: CardDecision) -> Color {
		switch decision {
		case .add:           return Color(.ratingPerfection)
		case .notInterested: return Color(.ratingSkip)
		case .later:         return .black.opacity(0.6)
		}
	}

	/// Right adds, left turns it down, up puts it off — where it was heading
	/// counts, so a flick will do. Down goes back to Up Next.
	private func swipe(_ suggestion: Suggestion) -> some Gesture {
		DragGesture(minimumDistance: 6)
			.onChanged { value in
				guard !flying else { return }
				let wasPast = CardDecision.forSwipe(translation: drag, predictedEnd: drag, threshold: Self.threshold) != nil
				drag = value.translation
				let isPast = CardDecision.forSwipe(translation: drag, predictedEnd: drag, threshold: Self.threshold) != nil
				// A tick as it crosses the point of deciding, either way.
				if isPast != wasPast { Haptics.click() }
			}
			.onEnded { value in
				guard !flying else { return }
				if let decision = CardDecision.forSwipe(translation: value.translation,
				                                        predictedEnd: value.predictedEndTranslation,
				                                        threshold: Self.threshold) {
					return commit(decision, suggestion)
				}
				let heading = value.predictedEndTranslation
				if heading.height > Self.threshold, abs(heading.height) > abs(heading.width) {
					withAnimation(.smooth) {
						drag = .zero
						page = .upNext
					}
					return
				}
				withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { drag = .zero }
			}
	}

	/// Flies the card off the way the decision goes, from wherever it's been
	/// dragged, then decides; the next card comes in as the iPhone's does.
	private func commit(_ decision: CardDecision, _ suggestion: Suggestion) {
		guard !flying else { return }
		flying = true
		if decision == .add { Haptics.success() } else { Haptics.click() }
		withAnimation(.easeIn(duration: 0.22)) {
			switch decision {
			case .add:           drag = CGSize(width: 300, height: drag.height + 20)
			case .notInterested: drag = CGSize(width: -300, height: drag.height + 20)
			case .later:         drag = CGSize(width: drag.width, height: -400)
			}
		}
		Task {
			try? await Task.sleep(for: .milliseconds(220))
			var still = Transaction()
			still.disablesAnimations = true
			withTransaction(still) {
				drag = .zero
				flying = false
			}
			withAnimation(.smooth(duration: 0.3)) { store.decide(decision, on: suggestion) }
		}
	}

	// MARK: Pieces

	private func tone(for suggestion: Suggestion) -> Color {
		tones[suggestion.id] ?? Artwork.cached(Artwork.poster(suggestion.posterURL))?.tone
			?? Artwork.placeholderTone(for: suggestion.title)
	}

	@ViewBuilder
	private func emptyMessage(_ deal: DiscoverDeal<DiscoverSeed>) -> some View {
		let fetching = store.loader.isLoading || deal.dealing.contains { !store.loader.fetched.contains($0) }
		if store.snapshot == nil {
			if store.phone == .notInstalled {
				MessageView(systemImage: "iphone", title: "Suggestions start from your library",
				            detail: "Install WatchList on your iPhone and add a few titles.")
			} else {
				MessageView(systemImage: "iphone", title: "Open WatchList on your iPhone",
				            detail: "Suggestions start from the titles there.")
			}
		} else if store.snapshot?.seeds.isEmpty == true {
			MessageView(systemImage: "sparkles", title: "Nothing to go on yet",
			            detail: "Add or rate shows and films on your iPhone.")
		} else if !TMDbConfig.isConfigured {
			MessageView(systemImage: "key", title: "No TMDb key",
			            detail: "This build has no key to ask TMDb for suggestions with.")
		} else if !deal.dealing.isEmpty, fetching {
			ProgressView("Finding suggestions")
		} else if store.loader.failed {
			MessageView(systemImage: "wifi.slash", title: "Can't reach TMDb",
			            detail: "Suggestions need your iPhone nearby, or Wi-Fi.", actionTitle: "Try Again") {
				store.loader.retry()
				Task { await store.fill(store.deal) }
			}
		} else if !store.filter.isDefault {
			MessageView(systemImage: "line.3.horizontal.decrease", title: "Nothing fits this filter",
			            actionTitle: "Clear Filter") { store.filter = DiscoverFilter() }
		} else {
			MessageView(systemImage: "checkmark.circle", title: "You're all caught up",
			            detail: "Rate or add more titles and new ones turn up here.")
		}
	}
}

/// A suggestion's poster as the iPhone's card frames it — rounded, with a fine
/// edge and a deep shadow — or its name on a colour until the poster's in.
private struct PosterCard: View {
	let suggestion: Suggestion
	let onTone: (Color) -> Void

	var body: some View {
		let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
		ArtworkImage(url: Artwork.poster(suggestion.posterURL), onTone: onTone) {
			ZStack {
				LinearGradient(colors: [Artwork.placeholderTone(for: suggestion.title), .black],
				               startPoint: .topLeading, endPoint: .bottomTrailing)
				VStack(spacing: 6) {
					Image(systemName: suggestion.placeholder)
						.foregroundStyle(.white.opacity(0.6))
					Text(suggestion.title)
						.font(.system(size: 16, weight: .bold))
						.multilineTextAlignment(.center)
						.minimumScaleFactor(0.6)
				}
				.padding(10)
			}
		}
		.aspectRatio(2 / 3, contentMode: .fit)
		.clipShape(shape)
		.overlay(shape.strokeBorder(.white.opacity(0.14), lineWidth: 1))
		.shadow(color: .black.opacity(0.35), radius: 12, y: 6)
	}
}
