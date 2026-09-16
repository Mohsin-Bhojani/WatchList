//
//  FannedPosters.swift
//  WatchList
//
//  Up to four posters fanned out and overlapping, the last on top — on the
//  Collections tab's cards and under a collection's name. Places without a
//  poster show as dashed outlines, the way the design draws an empty collection.
//

import SwiftUI

struct FannedPosters: View {
	let urls: [String]
	var posterWidth: CGFloat = 44

	private static let angles: [Double] = [-9, -3, 3, 9]

	var body: some View {
		let height = posterWidth * 1.5
		let step = posterWidth * 0.8
		let corner = RoundedRectangle(cornerRadius: posterWidth * 0.12, style: .continuous)
		ZStack(alignment: .leading) {
			ForEach(0..<4, id: \.self) { index in
				Group {
					if index < urls.count {
						PosterImage(urlString: urls[index], systemPlaceholder: "film")
							.clipShape(corner)
							.overlay(corner.strokeBorder(.white.opacity(0.18), lineWidth: 1))
					} else {
						corner
							.strokeBorder(.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
					}
				}
				.frame(width: posterWidth, height: height)
				.shadow(color: .black.opacity(index < urls.count ? 0.4 : 0), radius: 6, x: -2, y: 3)
				.rotationEffect(.degrees(Self.angles[index]))
				.offset(x: CGFloat(index) * step)
			}
		}
		.frame(width: posterWidth + step * 3, height: height, alignment: .leading)
		.accessibilityHidden(true)
	}
}
