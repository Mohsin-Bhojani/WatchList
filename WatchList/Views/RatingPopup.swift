//
//  RatingPopup.swift
//  WatchList
//
//  The iPhone title pages' "How was it?" sheet, after design B of the
//  alternatives: the poster across its top, then a verdict, half-star stars
//  or both — each sets the other (StarRating) — and, one at a time, what stood
//  out or a private note, where the title keeps them. It opens when a film or
//  show is marked Watched, and from Edit. Nothing changes until Save rating;
//  Not now leaves the title as it is.
//

import SwiftUI
import WatchListCore
import WatchListLibrary

/// What the card rates: a film, a show or a season, read once when it opens and
/// written back through `save` on Save rating.
struct RatingSubject {
	let title: String
	let posterURL: String
	var placeholder = "film"
	let rating: Rating?
	/// Stars picked by hand, if any.
	let stars: Double?
	/// The private note, or nil for a title that keeps none — a season.
	let note: String?
	/// What stood out, or nil for a title that keeps none — a season.
	var aspects: AspectTaste?
	let save: (_ rating: Rating?, _ stars: Double?, _ note: String?, _ aspects: AspectTaste?) -> Void
}

extension RatingSubject {
	init(film: Film) {
		self.init(title: film.title, posterURL: film.posterURL, rating: film.rating, stars: film.stars,
		          note: film.notes, aspects: film.aspectTaste) { rating, stars, note, aspects in
			film.rate(rating, stars: stars)
			if let note { film.notes = note }
			if let aspects { film.aspectTaste = aspects }
		}
	}

	init(show: Show) {
		self.init(title: show.title, posterURL: show.posterURL, placeholder: "tv",
		          rating: show.rating, stars: show.stars, note: show.notes,
		          aspects: show.aspectTaste) { rating, stars, note, aspects in
			show.rate(rating, stars: stars)
			if let note { show.notes = note }
			if let aspects { show.aspectTaste = aspects }
		}
	}

	init(season: Season) {
		let show = season.show
		self.init(title: show.map { "\($0.title) · \(season.displayName)" } ?? season.displayName,
		          posterURL: season.posterURL.isEmpty ? (show?.posterURL ?? "") : season.posterURL,
		          placeholder: "tv", rating: season.rating, stars: season.stars, note: nil) { rating, stars, _, _ in
			season.rate(rating, stars: stars)
		}
	}
}

struct RatingPopup: View {
	enum Mode: Identifiable {
		case justMarked, edit
		var id: Self { self }
	}

	let subject: RatingSubject
	let mode: Mode
	/// The page's colour, which the card's glass takes on.
	let tint: Color
	let onClose: () -> Void

	@State private var rating: Rating?
	/// Stars picked by hand in this edit; nil shows the verdict's own.
	@State private var stars: Double?
	@State private var note: String
	@State private var aspects: AspectTaste
	/// Which of the two extras is open: what stood out, or the note.
	@State private var extra: Extra
	/// The card's own height, which the sheet opens to.
	@State private var cardHeight: CGFloat = 560

	enum Extra: String, CaseIterable, Identifiable {
		case aspects = "What stood out"
		case note = "Note"
		var id: String { rawValue }
	}

	init(subject: RatingSubject, mode: Mode, tint: Color, onClose: @escaping () -> Void) {
		self.subject = subject
		self.mode = mode
		self.tint = tint
		self.onClose = onClose
		_rating = State(initialValue: subject.rating)
		_stars = State(initialValue: StarRating.explicit(subject.stars, afterChoosing: subject.rating))
		_note = State(initialValue: subject.note ?? "")
		_aspects = State(initialValue: subject.aspects ?? AspectTaste())
		// A title with a note already opens on it; otherwise on what stood out.
		_extra = State(initialValue: subject.aspects == nil || !(subject.note ?? "").isEmpty ? .note : .aspects)
	}

	init(film: Film, mode: Mode, tint: Color, onClose: @escaping () -> Void) {
		self.init(subject: RatingSubject(film: film), mode: mode, tint: tint, onClose: onClose)
	}

	private var shownStars: Double? { StarRating.shown(explicit: stars, verdict: rating) }

	/// A system sheet as tall as the card, so Save is always in view; swipe
	/// down or Not now leaves the title as it is.
	var body: some View {
		ScrollView {
			card.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
		}
			.scrollBounceBehavior(.basedOnSize)
			.environment(\.colorScheme, .dark)
			.presentationDetents([.height(cardHeight), .large])
			.presentationDragIndicator(.visible)
			.presentationBackground(tint.gradient)
	}

	private var card: some View {
		VStack(alignment: .leading, spacing: 16) {
				HStack(alignment: .center, spacing: 14) {
					// The whole poster, so you can see what you're rating.
					PosterImage(urlString: subject.posterURL, systemPlaceholder: subject.placeholder)
						.frame(width: 64, height: 96)
						.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
						.overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
						.shadow(color: .black.opacity(0.35), radius: 8, y: 4)
						.accessibilityHidden(true)
					VStack(alignment: .leading, spacing: 2) {
						Text(subject.title)
							.font(.system(.title2, design: .serif, weight: .bold))
							.lineLimit(2)
						Text(mode == .justMarked ? "Marked watched just now. How was it?" : "How was it?")
							.font(.system(.footnote, weight: .medium))
							.foregroundStyle(.white.opacity(0.65))
					}
					Spacer()
					Button("Not now", action: onClose)
						.font(.system(.subheadline, weight: .semibold))
						.foregroundStyle(.white.opacity(0.8))
				}

				// The four verdicts as one segmented row; tapping the chosen one clears it.
				HStack(spacing: 2) {
					// Worst to best, left to right, the way the star slider grows.
					ForEach(Rating.allCases.reversed()) { option($0) }
				}
				.padding(3)
				.background(.white.opacity(0.08), in: Capsule())

				StarRatingSlider(value: shownStars) { picked in
					stars = picked
					rating = StarRating.verdict(for: picked)
				}

				if subject.aspects != nil && subject.note != nil {
					Picker("Add", selection: $extra.animation(Glass.smooth)) {
						ForEach(Extra.allCases) { Text($0.rawValue).tag($0) }
					}
					.pickerStyle(.segmented)
				}
				if subject.aspects != nil && (extra == .aspects || subject.note == nil) { aspectChips }
				if subject.note != nil && (extra == .note || subject.aspects == nil) {
					TextField("Add a private note…", text: $note, axis: .vertical)
						.lineLimit(2...5)
						.font(.subheadline)
						.padding(12)
						.background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
				}

				Button(action: save) {
					Text("Save rating")
						.font(.system(.callout, weight: .bold))
						.foregroundStyle(.black.opacity(0.85))
						.frame(maxWidth: .infinity)
						.padding(.vertical, 14)
						.background(.white, in: Capsule())
				}
				.buttonStyle(.pressable)
			}
			.padding(.horizontal, 20)
			.padding(.top, 28)
			.padding(.bottom, 20)
			.foregroundStyle(.white)
	}

	/// "What stood out?": each tap moves an aspect from unmarked to liked to
	/// disliked and back, so a title can say what worked and what didn't.
	private var aspectChips: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("Optional")
					.font(.system(.footnote, weight: .medium))
					.foregroundStyle(.white.opacity(0.6))
				Spacer()
				Text("Tap again if it didn\u{2019}t work")
					.font(.system(.caption2, weight: .medium))
					.foregroundStyle(.white.opacity(0.4))
			}
			TileFlowLayout(spacing: 8) {
				ForEach(Aspect.allCases) { aspectChip($0) }
			}
		}
	}

	private func aspectChip(_ aspect: Aspect) -> some View {
		let state = aspects.state(of: aspect)
		let shape = Capsule()
		let fill: Color = switch state {
		case .unmarked: .white.opacity(0.07)
		case .liked:    PhoneFilmDetailView.teal.opacity(0.55)
		case .disliked: .red.opacity(0.45)
		}
		return Button {
			Haptics.selection()
			aspects.cycle(aspect)
		} label: {
			HStack(spacing: 5) {
				Image(systemName: state == .disliked ? "hand.thumbsdown.fill" : aspect.systemImage)
					.font(.system(.caption2, weight: .semibold))
				Text(aspect.rawValue)
					.font(.system(.footnote, weight: .semibold))
					.strikethrough(state == .disliked)
			}
			.foregroundStyle(.white)
			.padding(.horizontal, 11)
			.padding(.vertical, 7)
			.background(fill, in: shape)
			.overlay(shape.strokeBorder(.white.opacity(state == .unmarked ? 0 : 0.5), lineWidth: 1))
		}
		.buttonStyle(.plain)
		.accessibilityLabel(aspect.rawValue)
		.accessibilityValue(state == .liked ? "Liked" : state == .disliked ? "Disliked" : "Not picked")
	}

	/// Tapping the chosen verdict again clears the rating. Hand-picked stars
	/// stay only if they still fit the verdict chosen. Chosen, it's solid in its
	/// own colour.
	private func option(_ option: Rating) -> some View {
		let selected = rating == option
		return Button {
			Haptics.selection()
			withAnimation(Glass.pop) {
				rating = selected ? nil : option
				stars = StarRating.explicit(stars, afterChoosing: rating)
			}
		} label: {
			Text(option.rawValue)
				.font(.system(.footnote, weight: .semibold))
				.lineLimit(1)
				.minimumScaleFactor(0.8)
				.foregroundStyle(selected ? Glass.onTint : .white)
				.frame(maxWidth: .infinity, minHeight: 36)
				.background(selected ? Glass.tint(option) : .clear, in: Capsule())
				.contentShape(Capsule())
		}
		.buttonStyle(.plain)
		.accessibilityAddTraits(selected ? .isSelected : [])
	}

	private func save() {
		let trimmed = subject.note == nil ? nil : note.trimmingCharacters(in: .whitespacesAndNewlines)
		withAnimation(Glass.smooth) { subject.save(rating, stars, trimmed, subject.aspects == nil ? nil : aspects) }
		Haptics.success()
		onClose()
	}
}
