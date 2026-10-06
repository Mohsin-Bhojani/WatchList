//
//  RatingPopup.swift
//  WatchList
//
//  The iPhone title pages' "How was it?" card, after the design: a verdict,
//  half-star stars or both — each sets the other (StarRating) — and a private
//  note where the title keeps one. It opens when a film or show is marked
//  Watched, and from Edit. Nothing changes until Save rating; Not now leaves
//  the title as it is.
//

import SwiftUI

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
	enum Mode { case justMarked, edit }

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

	private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

	init(subject: RatingSubject, mode: Mode, tint: Color, onClose: @escaping () -> Void) {
		self.subject = subject
		self.mode = mode
		self.tint = tint
		self.onClose = onClose
		_rating = State(initialValue: subject.rating)
		_stars = State(initialValue: StarRating.explicit(subject.stars, afterChoosing: subject.rating))
		_note = State(initialValue: subject.note ?? "")
		_aspects = State(initialValue: subject.aspects ?? AspectTaste())
	}

	init(film: Film, mode: Mode, tint: Color, onClose: @escaping () -> Void) {
		self.init(subject: RatingSubject(film: film), mode: mode, tint: tint, onClose: onClose)
	}

	private var shownStars: Double? { StarRating.shown(explicit: stars, verdict: rating) }

	var body: some View {
		ZStack {
			Color.black.opacity(0.4)
				.ignoresSafeArea()
				.onTapGesture(perform: onClose)
				.accessibilityHidden(true)
			card
				// A phone's width, even on an iPad.
				.frame(maxWidth: 460)
				.padding(.horizontal, 24)
		}
	}

	private var card: some View {
		VStack(alignment: .leading, spacing: 14) {
			HStack(spacing: 12) {
				PosterImage(urlString: subject.posterURL, systemPlaceholder: subject.placeholder)
					.frame(width: 40, height: 60)
					.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
					.accessibilityHidden(true)
				VStack(alignment: .leading, spacing: 2) {
					Text(subject.title)
						.font(.system(size: 17, weight: .bold))
						.lineLimit(2)
					Text(mode == .justMarked ? "Marked watched just now" : "Your rating")
						.font(.system(size: 12, weight: .medium))
						.foregroundStyle(.white.opacity(0.6))
				}
			}

			Text("How was it?")
				.font(.system(size: 15, weight: .semibold))

			LazyVGrid(columns: columns, spacing: 10) {
				ForEach(Rating.allCases) { option($0) }
			}

			VStack(alignment: .leading, spacing: 8) {
				HStack {
					Text("Stars, optional")
						.font(.system(size: 13, weight: .medium))
						.foregroundStyle(.white.opacity(0.6))
					Spacer()
					if let shownStars {
						Text("\(StarRating.label(shownStars)) of 5")
							.font(.system(size: 13, weight: .semibold))
							.foregroundStyle(.white.opacity(0.85))
					}
				}
				StarRatingPicker(value: shownStars) { picked in
					stars = picked
					rating = StarRating.verdict(for: picked)
				}
			}

			if subject.aspects != nil { aspectChips }

			if subject.note != nil {
				TextField("Add a private note…", text: $note, axis: .vertical)
					.lineLimit(1...4)
					.font(.system(size: 14))
					.padding(12)
					.background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
			}

			HStack(spacing: 10) {
				Button(action: onClose) {
					Text("Not now")
						.font(.system(size: 15, weight: .semibold))
						.foregroundStyle(.white)
						.frame(maxWidth: .infinity)
						.padding(.vertical, 13)
						.background(.white.opacity(0.1), in: Capsule())
				}
				.buttonStyle(.pressable)
				Button(action: save) {
					Text("Save rating")
						.font(.system(size: 15, weight: .bold))
						.foregroundStyle(.black.opacity(0.85))
						.frame(maxWidth: .infinity)
						.padding(.vertical, 13)
						.background(PhoneFilmDetailView.teal, in: Capsule())
				}
				.buttonStyle(.pressable)
			}
		}
		.foregroundStyle(.white)
		.padding(18)
		.glassEffect(.regular.tint(tint.opacity(0.55)),
		             in: RoundedRectangle(cornerRadius: 28, style: .continuous))
	}

	/// "What stood out?": each tap moves an aspect from unmarked to liked to
	/// disliked and back, so a title can say what worked and what didn't.
	private var aspectChips: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack {
				Text("What stood out, optional")
					.font(.system(size: 13, weight: .medium))
					.foregroundStyle(.white.opacity(0.6))
				Spacer()
				Text("Tap again if it didn\u{2019}t work")
					.font(.system(size: 11, weight: .medium))
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
					.font(.system(size: 11, weight: .semibold))
				Text(aspect.rawValue)
					.font(.system(size: 13, weight: .semibold))
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
	/// stay only if they still fit the verdict chosen.
	private func option(_ option: Rating) -> some View {
		let selected = rating == option
		let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
		return Button {
			Haptics.selection()
			rating = selected ? nil : option
			stars = StarRating.explicit(stars, afterChoosing: rating)
		} label: {
			HStack(spacing: 7) {
				Circle()
					.fill(Glass.tint(option))
					.frame(width: 8, height: 8)
				Text(option.rawValue)
					.font(.system(size: 13, weight: .semibold))
				Spacer(minLength: 0)
			}
			.foregroundStyle(.white)
			.padding(.horizontal, 12)
			.padding(.vertical, 11)
			.background(.white.opacity(selected ? 0.2 : 0.07), in: shape)
			.overlay(shape.strokeBorder(.white.opacity(selected ? 0.55 : 0), lineWidth: 1))
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
