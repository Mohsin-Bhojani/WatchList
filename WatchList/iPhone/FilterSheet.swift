//
//  FilterSheet.swift
//  WatchList
//
//  Filter & Sort, as the Shows, Discover and Collections tabs open it: tapping
//  the tab again goes back to its list and up to the top, and once it's there
//  opens the sheet — a stack of filters, Reset and Done. The pieces:
//    - FilterSheet: the sheet itself
//    - FilterHeading: a filter's name, with what's picked beside it
//    - SegmentedFilter: a segmented control, one option picked
//    - SortSegments: sorts drawn like one, the chosen one reversing when tapped
//    - TileFilter: a wrap of tiles, any number picked
//    - FilterSummaryButton: the line under a tab's header saying what's set
//    - reportsListAtTop: whether a tab's list is on screen at its top
//

import SwiftUI

struct FilterSheet<Content: View>: View {
	let title: String
	/// Whether anything differs from how the tab starts out.
	let canReset: Bool
	let reset: () -> Void
	@ViewBuilder let content: () -> Content

	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			ScrollView {
				VStack(alignment: .leading, spacing: 22) {
					content()
				}
				.padding(.horizontal, 20)
				.padding(.top, 8)
				.padding(.bottom, 24)
			}
			.navigationTitle(title)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Reset") {
						Haptics.selection()
						withAnimation(Glass.smooth) { reset() }
					}
					.disabled(!canReset)
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Done", systemImage: "checkmark", role: .confirm) { dismiss() }
				}
			}
		}
		// Half an iPad's form sheet cuts the last row off.
		.presentationDetents(UIDevice.current.userInterfaceIdiom == .pad ? [.large] : [.medium, .large])
		.presentationDragIndicator(.visible)
	}
}

/// A filter's name, with what's picked beside it when that's worth saying.
struct FilterHeading: View {
	let title: String
	var detail: String?

	init(_ title: String, detail: String? = nil) {
		self.title = title
		self.detail = detail
	}

	var body: some View {
		HStack(spacing: 6) {
			Text(title)
				.foregroundStyle(Glass.ink)
			if let detail {
				Text(detail)
					.foregroundStyle(.secondary)
			}
		}
		.font(.system(size: 15, weight: .semibold))
		.accessibilityElement(children: .combine)
		.accessibilityAddTraits(.isHeader)
	}
}

/// A heading and a segmented control under it, one option picked.
struct SegmentedFilter<Value: Hashable>: View {
	let title: String
	let options: [Value]
	@Binding var selection: Value
	let label: (Value) -> String

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			FilterHeading(title)
			Picker(title, selection: $selection.animation(Glass.smooth)) {
				ForEach(options, id: \.self) { Text(label($0)).tag($0) }
			}
			.pickerStyle(.segmented)
			.labelsHidden()
			.onChange(of: selection) { Haptics.selection() }
		}
	}
}

/// Sorts drawn like a segmented control. Tapping the chosen one again reverses
/// it, so it says which way it runs: A–Z becomes Z–A, and the others turn their
/// arrow round.
struct SortSegments<Sort: ListSort>: View {
	let title: String
	@Binding var order: ListOrder<Sort>

	@Namespace private var thumb

	/// The system control's thumb: white, or a lighter grey in the dark.
	private static var thumbColor: Color {
		Color(uiColor: UIColor { traits in
			traits.userInterfaceStyle == .dark ? UIColor(white: 1, alpha: 0.24) : .white
		})
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			FilterHeading(title, detail: order.summary)
			HStack(spacing: 0) {
				ForEach(Sort.allCases) { segment($0) }
			}
			.padding(3)
			.background(Capsule().fill(Color.primary.opacity(0.06)))
		}
	}

	private func segment(_ sort: Sort) -> some View {
		let chosen = order.sort == sort
		return Button {
			Haptics.selection()
			withAnimation(Glass.smooth) { order.choose(sort) }
		} label: {
			HStack(spacing: 4) {
				Text(order.segmentTitle(for: sort))
				if chosen, let arrow = order.arrowSymbol {
					Image(systemName: arrow)
						.font(.system(size: 11, weight: .bold))
				}
			}
			.font(.system(size: 14, weight: .medium))
			.foregroundStyle(Color.primary)
			.frame(maxWidth: .infinity)
			.frame(height: 30)
			.background {
				if chosen {
					Capsule()
						.fill(Self.thumbColor)
						.shadow(color: .black.opacity(0.12), radius: 3, y: 1)
						.matchedGeometryEffect(id: "thumb", in: thumb)
				}
			}
			.contentShape(Capsule())
		}
		.buttonStyle(.plain)
		.accessibilityLabel(chosen ? order.summary : sort.title)
		.accessibilityHint(chosen ? "Tap again to reverse" : "")
		.accessibilityAddTraits(chosen ? .isSelected : [])
	}
}

/// A heading and its options as tiles, wrapping onto as many rows as they need.
/// Any number can be picked; All, first, clears the pick.
struct TileFilter: View {
	let title: String
	let options: [String]
	@Binding var picked: Set<String>

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			FilterHeading(title, detail: picked.isEmpty ? nil : "\(picked.count) picked")
			TileFlowLayout(spacing: 8) {
				tile("All", chosen: picked.isEmpty) { picked.removeAll() }
				ForEach(options, id: \.self) { option in
					tile(option, chosen: picked.contains(option)) {
						if picked.contains(option) { picked.remove(option) } else { picked.insert(option) }
					}
				}
			}
		}
	}

	private func tile(_ name: String, chosen: Bool, action: @escaping () -> Void) -> some View {
		Button {
			Haptics.selection()
			withAnimation(Glass.smooth) { action() }
		} label: {
			Text(name)
				.font(.system(size: 14, weight: .medium))
				.foregroundStyle(chosen ? Color.white : Color.primary)
				.padding(.horizontal, 14)
				.padding(.vertical, 8)
				.background(chosen ? AnyShapeStyle(Glass.accent) : AnyShapeStyle(Color.primary.opacity(0.06)),
				            in: Capsule())
				.contentShape(Capsule())
		}
		.buttonStyle(.plain)
		.accessibilityAddTraits(chosen ? .isSelected : [])
	}
}

/// Lays its children out left to right, starting a new row when one is full.
struct TileFlowLayout: Layout {
	var spacing: CGFloat = 8

	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let rows = rows(of: subviews, within: proposal.width ?? .infinity)
		let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
		return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
	}

	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		var y = bounds.minY
		for row in rows(of: subviews, within: bounds.width) {
			var x = bounds.minX
			for index in row.indices {
				let size = subviews[index].sizeThatFits(.unspecified)
				subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
				x += size.width + spacing
			}
			y += row.height + spacing
		}
	}

	private struct Row {
		var indices: [Int] = []
		var width: CGFloat = 0
		var height: CGFloat = 0
	}

	private func rows(of subviews: Subviews, within width: CGFloat) -> [Row] {
		var rows: [Row] = []
		var row = Row()
		for index in subviews.indices {
			let size = subviews[index].sizeThatFits(.unspecified)
			let widened = row.indices.isEmpty ? size.width : row.width + spacing + size.width
			if widened > width, !row.indices.isEmpty {
				rows.append(row)
				row = Row(indices: [index], width: size.width, height: size.height)
			} else {
				row.indices.append(index)
				row.width = widened
				row.height = max(row.height, size.height)
			}
		}
		if !row.indices.isEmpty { rows.append(row) }
		return rows
	}
}

/// Under a tab's header while its filters narrow or reorder the list: says
/// what they're set to, and opens them.
struct FilterSummaryButton: View {
	let summary: String
	let action: () -> Void

	var body: some View {
		Button(action: action) {
			HStack(spacing: 6) {
				Image(systemName: "line.3.horizontal.decrease")
					.font(.system(size: 12, weight: .bold))
				Text(summary)
					.font(.system(size: 13, weight: .semibold))
					.lineLimit(1)
			}
			.foregroundStyle(Glass.ink)
			.padding(.horizontal, 14)
			.frame(height: 34)
			.contentShape(Capsule())
		}
		.buttonStyle(.plain)
		.glassEffect(.regular.interactive(), in: Capsule())
		.accessibilityLabel("Filters: \(summary)")
		.accessibilityHint("Opens the filters")
	}
}

extension View {
	/// Keeps `atTop` true while this scroll view is on screen and at its top —
	/// not scrolled down, and with no page pushed over it — when tapping its
	/// tab again should open Filter & Sort.
	func reportsListAtTop(_ atTop: Binding<Bool>) -> some View {
		modifier(ListAtTop(atTop: atTop))
	}
}

private struct ListAtTop: ViewModifier {
	@Binding var atTop: Bool
	@State private var scrolledToTop = true
	@State private var onScreen = false

	func body(content: Content) -> some View {
		content
			.onScrollGeometryChange(for: Bool.self) { geometry in
				geometry.contentOffset.y + geometry.contentInsets.top < 1
			} action: { _, isAtTop in
				scrolledToTop = isAtTop
			}
			.onAppear { onScreen = true }
			.onDisappear { onScreen = false }
			.onChange(of: onScreen && scrolledToTop, initial: true) { _, ready in atTop = ready }
	}
}
