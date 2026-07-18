//
//  DetailHeader.swift
//  WatchList
//
//  Shared hero header for Show / Season / Episode / Film pages. The landscape
//  backdrop (or still) fills the entire top section, with the title, subtitle,
//  meta and an optional IMDb link overlaid on a legibility scrim.
//

import SwiftUI

struct DetailHeader: View {
	let posterURL: String
	let backdropURL: String
	let title: String
	let subtitle: String
	let meta: String
	var imdbID: String? = nil
	var placeholder: String = "film"

	// Prefer the landscape backdrop; fall back to the poster, then a gradient.
	private var heroURL: String { backdropURL.isEmpty ? posterURL : backdropURL }

	var body: some View {
		ZStack(alignment: .bottomLeading) {
			Group {
				if !heroURL.isEmpty {
					PosterImage(urlString: heroURL, systemPlaceholder: placeholder)
				} else {
					LinearGradient(colors: [Glass.accent.opacity(0.7), Glass.accent3.opacity(0.6)],
					               startPoint: .topLeading, endPoint: .bottomTrailing)
				}
			}
			.frame(maxWidth: .infinity)
			.frame(height: 230)
			.clipped()

			// Legibility scrim so overlaid text reads on any image.
			LinearGradient(colors: [.clear, .black.opacity(0.2), .black.opacity(0.78)],
			               startPoint: .top, endPoint: .bottom)

			VStack(alignment: .leading, spacing: 6) {
				Text(title)
					.font(Glass.serif(26, .bold))
					.foregroundStyle(.white)
					.lineLimit(2)
					.fixedSize(horizontal: false, vertical: true)
					.shadow(color: .black.opacity(0.35), radius: 6, y: 2)
				if !subtitle.isEmpty {
					Text(subtitle)
						.font(.system(size: 13, weight: .semibold, design: .rounded))
						.foregroundStyle(.white.opacity(0.9))
				}
				if !meta.isEmpty {
					Text(meta)
						.font(.system(size: 12, weight: .semibold, design: .rounded))
						.foregroundStyle(.white.opacity(0.85))
				}
				if let id = imdbID, !id.isEmpty, let url = IMDb.titleURL(id) {
					Link(destination: url) {
						HStack(spacing: 5) {
							Image(systemName: "arrow.up.right.square.fill")
							Text("View on IMDb")
						}
						.font(.system(size: 12, weight: .bold, design: .rounded))
						.foregroundStyle(.black)
						.padding(.horizontal, 11).padding(.vertical, 6)
						.background(Capsule().fill(Color(hex: "#F5C518")))
					}
					.padding(.top, 4)
				}
			}
			.padding(16)
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.frame(maxWidth: .infinity)
		.frame(height: 230)
		.clipShape(RoundedRectangle(cornerRadius: Glass.corner, style: .continuous))
		.overlay(RoundedRectangle(cornerRadius: Glass.corner, style: .continuous)
			.strokeBorder(Glass.hairline.opacity(0.16), lineWidth: 1))
		.shadow(color: .black.opacity(0.12), radius: 12, y: 6)
	}
}
