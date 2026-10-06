//
//  GenreRowsFilter.swift
//  WatchList
//
//  Genre, as Discover's filter shows it: small tiles dealt across two or three
//  rows that scroll sideways together, so a long list of TMDb's genres takes a
//  few lines of the sheet rather than most of it. All comes first; any number
//  can be picked.
//    - GenreRowsFilter: the heading and the rows
//    - ChipRows: which row each tile goes on
//

import SwiftUI

struct GenreRowsFilter: View {
	let options: [String]
	@Binding var picked: Set<String>
	/// Closed to start with: the heading says what's picked, and opens the tiles.
	@State private var open = false

	/// A tile: All, which clears the pick, or a genre.
	enum Chip: Hashable {
		case all
		case genre(String)

		var name: String {
			switch self {
			case .all:              return "All"
			case .genre(let name): return name
			}
		}
	}

	private static let font = UIFont.systemFont(ofSize: 13, weight: .medium)
	private static let padding: CGFloat = 12
	private static let spacing: CGFloat = 6

	/// Picked genres named while there are one or two, counted after that.
	private var detail: String? {
		switch picked.count {
		case 0:    return nil
		case 1, 2: return picked.sorted().joined(separator: ", ")
		default:   return "\(picked.count) picked"
		}
	}

	var body: some View {
		let chips = [Chip.all] + options.map(Chip.genre)
		// Dealt by name, never by what's picked, so tiles stay put as they're tapped.
		let rows = ChipRows.deal(chips, into: ChipRows.rowCount(for: chips.count), spacing: Self.spacing) { chip in
			(chip.name as NSString).size(withAttributes: [.font: Self.font]).width + 2 * Self.padding
		}
		VStack(alignment: .leading, spacing: 10) {
			Button {
				Haptics.selection()
				withAnimation(Glass.smooth) { open.toggle() }
			} label: {
				HStack(spacing: 8) {
					FilterHeading("Genre", detail: detail)
						.lineLimit(1)
					Spacer(minLength: 8)
					Image(systemName: "chevron.down")
						.font(.system(size: 12, weight: .bold))
						.foregroundStyle(.secondary)
						.rotationEffect(.degrees(open ? 180 : 0))
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Genre")
			.accessibilityValue(detail ?? "All")
			.accessibilityHint(open ? "Hides the genres" : "Shows the genres")
			if open { tileRows(rows) }
		}
	}

	private func tileRows(_ rows: [[Chip]]) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			ScrollView(.horizontal) {
				VStack(alignment: .leading, spacing: Self.spacing) {
					ForEach(rows.indices, id: \.self) { index in
						HStack(spacing: Self.spacing) {
							ForEach(rows[index], id: \.self) { tile($0) }
						}
					}
				}
			}
			.scrollIndicators(.hidden)
			// Out to the sheet's edges, so tiles scroll off them rather than
			// short of the heading's margin.
			.contentMargins(.horizontal, 20, for: .scrollContent)
			.padding(.horizontal, -20)
		}
		.transition(.opacity.combined(with: .move(edge: .top)))
	}

	private func tile(_ chip: Chip) -> some View {
		let chosen: Bool
		switch chip {
		case .all:              chosen = picked.isEmpty
		case .genre(let name): chosen = picked.contains(name)
		}
		return Button {
			Haptics.selection()
			withAnimation(Glass.smooth) {
				switch chip {
				case .all:
					picked.removeAll()
				case .genre(let name):
					if picked.contains(name) { picked.remove(name) } else { picked.insert(name) }
				}
			}
		} label: {
			// The same weight picked or not, so a tile never changes width.
			Text(chip.name)
				.font(Font(Self.font))
				.lineLimit(1)
				.fixedSize()
				.foregroundStyle(chosen ? Color.white : Color.primary)
				.padding(.horizontal, Self.padding)
				.frame(height: 30)
				.background(chosen ? AnyShapeStyle(Glass.accent) : AnyShapeStyle(Color.primary.opacity(0.06)),
				            in: Capsule())
				.contentShape(Capsule())
		}
		.buttonStyle(.plain)
		.accessibilityAddTraits(chosen ? .isSelected : [])
	}
}

enum ChipRows {
	/// Two rows for a short list, three for a longer one.
	static func rowCount(for count: Int) -> Int {
		count <= 12 ? 2 : 3
	}

	/// `items` in order, each onto whichever row is shortest so far — the first
	/// of them on a tie — so the rows end about level. Empty rows are dropped.
	static func deal<Item>(_ items: [Item], into count: Int, spacing: CGFloat,
	                       width: (Item) -> CGFloat) -> [[Item]] {
		guard count > 0 else { return [] }
		var rows = Array(repeating: [Item](), count: count)
		var widths = Array(repeating: CGFloat(0), count: count)
		for item in items {
			guard let shortest = widths.indices.min(by: { widths[$0] < widths[$1] }) else { continue }
			widths[shortest] += (rows[shortest].isEmpty ? 0 : spacing) + width(item)
			rows[shortest].append(item)
		}
		return rows.filter { !$0.isEmpty }
	}
}
