//
//  StarRatings.swift
//  WatchList
//
//  The half-star scale that sits beside the four verdicts, and the rules that
//  keep the two in step:
//    - rating in stars picks the verdict: 0–2 Skip, 2.5–3.5 Timepass,
//      4–4.5 Go For It, 5 Perfection
//    - rating with a verdict assumes its stars: Skip 1, Timepass 3,
//      Go For It 4, Perfection 5
//  Either is optional; setting one sets the other. Hand-picked stars are kept
//  on the title itself (Rated, in WatchTracking.swift).
//

import Foundation

enum StarRating {
	/// 0, 0.5, 1 … 5.
	static let values: [Double] = Array(stride(from: 0.0, through: 5.0, by: 0.5))

	/// The verdict a star rating stands for.
	static func verdict(for stars: Double) -> Rating {
		switch snapped(stars) {
		case ...2:   return .skip
		case ...3.5: return .timepass
		case ...4.5: return .goForIt
		default:     return .perfection
		}
	}

	/// The stars a verdict stands for.
	static func stars(for verdict: Rating) -> Double {
		switch verdict {
		case .skip:       return 1
		case .timepass:   return 3
		case .goForIt:    return 4
		case .perfection: return 5
		}
	}

	/// Onto the scale: the nearest half star, 0 to 5.
	static func snapped(_ value: Double) -> Double {
		(min(max(value, 0), 5) * 2).rounded() / 2
	}

	/// The stars to show for a title: the hand-picked ones while they still
	/// agree with its verdict — it may have been changed somewhere stars aren't
	/// shown — otherwise the verdict's own. Nil when it isn't rated.
	static func shown(explicit: Double?, verdict: Rating?) -> Double? {
		guard let verdict else { return nil }
		if let explicit, self.verdict(for: explicit) == verdict { return explicit }
		return stars(for: verdict)
	}

	/// The hand-picked stars that survive choosing `verdict`: kept when they
	/// already fall in its range (4.5 stays for Go For It), dropped otherwise so
	/// the verdict's own stars show instead.
	static func explicit(_ explicit: Double?, afterChoosing verdict: Rating?) -> Double? {
		guard let verdict, let explicit, self.verdict(for: explicit) == verdict else { return nil }
		return explicit
	}

	/// "4.5", or "4" for a whole star.
	static func label(_ stars: Double) -> String {
		stars.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(stars)) : String(format: "%.1f", stars)
	}
}
