//
//  Aspects.swift
//  WatchList
//
//  What stood out in a title, beside its verdict: the parts of it the viewer
//  liked or didn't, picked as chips on the "How was it?" card. A verdict says
//  how much; aspects say why, which is what Discover can learn from.
//
//  Each title keeps two lists of aspect names, liked and disliked, on the model.
//  Names rather than the enum itself are stored, so retiring an aspect later
//  never stops a title from loading.
//

import Foundation

enum Aspect: String, CaseIterable, Identifiable {
	case story = "Story"
	case characters = "Characters"
	case acting = "Acting"
	case ending = "Ending"
	case visuals = "Visuals"
	case music = "Music"
	case humour = "Humour"
	case romance = "Romance"
	case pacing = "Pacing"
	case vibe = "Vibe"

	var id: String { rawValue }

	var systemImage: String {
		switch self {
		case .story:      return "text.book.closed"
		case .characters: return "person.2"
		case .acting:     return "theatermasks"
		case .ending:     return "flag.checkered"
		case .visuals:    return "eye"
		case .music:      return "music.note"
		case .humour:     return "face.smiling"
		case .romance:    return "heart"
		case .pacing:     return "gauge.with.dots.needle.50percent"
		case .vibe:       return "sparkles"
		}
	}
}

/// What a viewer picked out of a title: aspects they liked and aspects they
/// didn't. An aspect is in at most one of the two.
struct AspectTaste: Equatable {
	enum State { case unmarked, liked, disliked }

	private(set) var liked: Set<Aspect> = []
	private(set) var disliked: Set<Aspect> = []

	init() {}

	/// From the names a title stores; names that aren't aspects any more are
	/// dropped, and one stored in both lists counts as liked.
	init(liked: [String], disliked: [String]) {
		self.liked = Set(liked.compactMap(Aspect.init(rawValue:)))
		self.disliked = Set(disliked.compactMap(Aspect.init(rawValue:))).subtracting(self.liked)
	}

	var isEmpty: Bool { liked.isEmpty && disliked.isEmpty }

	func state(of aspect: Aspect) -> State {
		if liked.contains(aspect) { return .liked }
		return disliked.contains(aspect) ? .disliked : .unmarked
	}

	/// A tap on a chip: unmarked, then liked, then disliked, then unmarked again.
	mutating func cycle(_ aspect: Aspect) {
		switch state(of: aspect) {
		case .unmarked: liked.insert(aspect)
		case .liked:    liked.remove(aspect); disliked.insert(aspect)
		case .disliked: disliked.remove(aspect)
		}
	}

	/// The names to store, in the order the aspects are listed so a title's
	/// lists don't shuffle between saves.
	var likedNames: [String] { Aspect.allCases.filter(liked.contains).map(\.rawValue) }
	var dislikedNames: [String] { Aspect.allCases.filter(disliked.contains).map(\.rawValue) }
}

extension Film {
	var aspectTaste: AspectTaste {
		get { AspectTaste(liked: likedAspects, disliked: dislikedAspects) }
		set { likedAspects = newValue.likedNames; dislikedAspects = newValue.dislikedNames }
	}
}

extension Show {
	var aspectTaste: AspectTaste {
		get { AspectTaste(liked: likedAspects, disliked: dislikedAspects) }
		set { likedAspects = newValue.likedNames; dislikedAspects = newValue.dislikedNames }
	}
}
