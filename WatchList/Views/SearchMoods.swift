//
//  SearchMoods.swift
//  WatchList
//
//  The Search page before anything's typed, after design D of the second
//  round: moods and genres as colour tiles, each a TMDb discover query whose
//  titles show right there, ready to add.
//

import SwiftUI
import WatchListCore

enum SearchMood: String, CaseIterable, Identifiable {
	case mindBending = "Mind-bending sci-fi"
	case thrillers = "Tense thrillers"
	case feelGood = "Feel-good comedy"
	case anime = "Anime series"
	case short = "Short, one sitting"
	case acclaimed = "Highly rated shows"

	var id: String { rawValue }

	var kind: MediaKind {
		switch self {
		case .anime, .acclaimed: return .show
		default: return .film
		}
	}

	/// TMDb discover filters. Genre ids are TMDb's: 878 science fiction,
	/// 53 thriller, 35 comedy, 10751 family, 16 animation.
	var filters: [String: String] {
		switch self {
		case .mindBending: return ["with_genres": "878"]
		case .thrillers:   return ["with_genres": "53"]
		case .feelGood:    return ["with_genres": "35,10751"]
		case .anime:       return ["with_genres": "16", "with_original_language": "ja"]
		case .short:       return ["with_runtime.gte": "60", "with_runtime.lte": "95"]
		case .acclaimed:   return ["sort_by": "vote_average.desc", "vote_count.gte": "1500"]
		}
	}

	var symbol: String {
		switch self {
		case .mindBending: return "brain"
		case .thrillers:   return "bolt.heart"
		case .feelGood:    return "sun.max"
		case .anime:       return "sparkles.tv"
		case .short:       return "timer"
		case .acclaimed:   return "star"
		}
	}

	var colors: [Color] {
		switch self {
		case .mindBending: return [Color(red: 0.24, green: 0.31, blue: 0.56), Color(red: 0.11, green: 0.13, blue: 0.27)]
		case .thrillers:   return [Color(red: 0.56, green: 0.24, blue: 0.31), Color(red: 0.27, green: 0.11, blue: 0.13)]
		case .feelGood:    return [Color(red: 0.24, green: 0.56, blue: 0.42), Color(red: 0.11, green: 0.27, blue: 0.2)]
		case .anime:       return [Color(red: 0.56, green: 0.42, blue: 0.24), Color(red: 0.27, green: 0.2, blue: 0.11)]
		case .short:       return [Color(red: 0.42, green: 0.24, blue: 0.56), Color(red: 0.2, green: 0.11, blue: 0.27)]
		case .acclaimed:   return [Color(red: 0.31, green: 0.35, blue: 0.4), Color(red: 0.13, green: 0.15, blue: 0.18)]
		}
	}
}

/// The six moods as a two-column grid of colour tiles.
struct SearchMoodGrid: View {
	let onPick: (SearchMood) -> Void
	@Environment(\.dynamicTypeSize) private var typeSize

	var body: some View {
		let count = typeSize.isAccessibilitySize ? 1 : 2
		LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: count), spacing: 10) {
			ForEach(SearchMood.allCases) { mood in
				Button { onPick(mood) } label: {
					VStack(alignment: .leading) {
						Image(systemName: mood.symbol)
							.font(.system(.body, weight: .semibold))
							.foregroundStyle(.white.opacity(0.85))
						Spacer(minLength: 0)
						Text(mood.rawValue)
							.font(.system(.subheadline, weight: .bold))
							.foregroundStyle(.white)
							.multilineTextAlignment(.leading)
							.lineLimit(2)
					}
					.padding(12)
					.frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
					.background(LinearGradient(colors: mood.colors, startPoint: .topLeading, endPoint: .bottomTrailing),
					            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
					.contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
				}
				.buttonStyle(.pressable)
			}
		}
	}
}
