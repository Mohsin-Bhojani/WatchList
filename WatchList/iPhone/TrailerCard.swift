//
//  TrailerCard.swift
//  WatchList
//
//  The trailer on a show or film page. TMDb lists a title's videos, almost all
//  of them on YouTube; the card shows the best trailer over the title's
//  landscape artwork and plays it in place when tapped, and a row under it
//  lists the rest of the trailers and teasers, each playing in the card.
//  A title with no trailer on TMDb has no card.
//

import SwiftUI
import WebKit

/// The TMDb title a page's trailer and Where to watch come from.
enum TitleSource: Hashable {
	case series(tvID: Int)
	case movie(movieID: Int)

	func videos() async throws -> [TMDbVideo] {
		switch self {
		case .series(let tvID): try await TMDbService.shared.videos(tvID: tvID)
		case .movie(let movieID): try await TMDbService.shared.videos(movieID: movieID)
		}
	}

	func watchProviders() async throws -> [String: TMDbProviderRegion] {
		switch self {
		case .series(let tvID): try await TMDbService.shared.watchProviders(tvID: tvID)
		case .movie(let movieID): try await TMDbService.shared.watchProviders(movieID: movieID)
		}
	}
}

/// One YouTube trailer or teaser.
struct Trailer: Identifiable, Equatable {
	let key: String
	let name: String
	let isTeaser: Bool

	var id: String { key }
	/// YouTube's 16:9 still for the video.
	var thumbnailURL: String { "https://i.ytimg.com/vi/\(key)/mqdefault.jpg" }
}

enum Trailers {
	/// The trailers and teasers worth offering, best first: trailers before
	/// teasers, the studio's own before anyone else's, then the earliest — the
	/// first trailer is the one that sells the whole title, where later ones
	/// are often for a later season. Clips, featurettes and anything not on
	/// YouTube are left out.
	static func ranked(_ videos: [TMDbVideo]) -> [Trailer] {
		var seen = Set<String>()
		return videos
			.filter { $0.site == "YouTube" && ($0.type == "Trailer" || $0.type == "Teaser") }
			.compactMap { video -> (Trailer, Bool, String)? in
				// The key goes into the player's page, so only a YouTube id's characters get through.
				guard let key = video.key, !key.isEmpty,
				      key.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
				      seen.insert(key).inserted else { return nil }
				let name = video.name?.trimmingCharacters(in: .whitespaces) ?? ""
				let trailer = Trailer(key: key, name: name.isEmpty ? (video.type ?? "Trailer") : name,
				                      isTeaser: video.type == "Teaser")
				return (trailer, video.official ?? false, video.published_at ?? "")
			}
			.sorted { a, b in
				if a.0.isTeaser != b.0.isTeaser { return !a.0.isTeaser }
				if a.1 != b.1 { return a.1 }
				// ISO 8601 timestamps sort as text; an undated video goes last.
				if a.2.isEmpty != b.2.isEmpty { return !a.2.isEmpty }
				return a.2 < b.2
			}
			.map(\.0)
	}
}

/// The trailer card, and the row of the title's other videos under it.
struct PageTrailerCard: View {
	/// Nil for a title that isn't on TMDb, which has no videos to find.
	let source: TitleSource?
	let backdropURL: String
	/// The show page heads it "Trailer"; the film page runs it straight on.
	var title: String?

	/// Nil until loaded.
	@State private var trailers: [Trailer]?
	@State private var playing: Trailer?

	/// Fetched once a session per title.
	private static var cache: [TitleSource: [Trailer]] = [:]

	init(source: TitleSource?, backdropURL: String, title: String? = nil) {
		self.source = source
		self.backdropURL = backdropURL
		self.title = title
		_trailers = State(initialValue: source.flatMap { Self.cache[$0] })
	}

	var body: some View {
		Group {
			// Kept while loading, so the page doesn't jump when most titles' trailers arrive.
			if source != nil, trailers.map({ !$0.isEmpty }) ?? true {
				if let title {
					PageSection(title: title) { content }
				} else {
					content
				}
			}
		}
		.task(id: source) { await load() }
	}

	private var content: some View {
		VStack(alignment: .leading, spacing: 12) {
			card
			if let trailers, trailers.count > 1 { videoRow(trailers) }
		}
	}

	// MARK: Card

	private var card: some View {
		let best = trailers?.first
		let shown = playing ?? best
		return ZStack {
			if let playing {
				// Clear until YouTube's player paints, which takes a few seconds.
				ProgressView().tint(.white)
				YouTubePlayer(key: playing.key)
			} else {
				PosterImage(urlString: backdropURL.isEmpty ? (best?.thumbnailURL ?? "") : backdropURL,
				            systemPlaceholder: "film")
					.overlay { Color.black.opacity(0.25) }
					.overlay {
						Image(systemName: "play.fill")
							.font(.system(size: 18, weight: .bold))
							.foregroundStyle(.white.opacity(best == nil ? 0.35 : 0.9))
							.frame(width: 48, height: 48)
							.glassEffect(.regular, in: Circle())
					}
					.overlay(alignment: .bottomLeading) {
						if let best {
							Text(best.name)
								.font(.system(size: 12, weight: .semibold))
								.foregroundStyle(.white)
								.lineLimit(1)
								.padding(.horizontal, 10)
								.padding(.vertical, 5)
								.background(.black.opacity(0.45), in: Capsule())
								.padding(10)
						}
					}
					.contentShape(Rectangle())
					.onTapGesture { if let best { playing = best } }
					.accessibilityElement(children: .ignore)
					.accessibilityLabel(best.map { "Play \($0.name)" } ?? "Trailer, loading")
					.accessibilityAddTraits(best == nil ? [] : .isButton)
			}
		}
		.aspectRatio(16 / 9, contentMode: .fit)
		.frame(maxWidth: .infinity)
		.background(.black)
		.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
		.id(shown?.key)
	}

	// MARK: Other videos

	/// Every trailer and teaser, the one in the card ringed; each plays in the card.
	private func videoRow(_ trailers: [Trailer]) -> some View {
		let current = playing ?? trailers.first
		return VStack(alignment: .leading, spacing: 8) {
			PageSmallCaps(text: "Videos · \(trailers.count)")
			ScrollView(.horizontal) {
				HStack(alignment: .top, spacing: 12) {
					ForEach(trailers) { trailer in
						Button { playing = trailer } label: {
							VStack(alignment: .leading, spacing: 6) {
								PosterImage(urlString: trailer.thumbnailURL, systemPlaceholder: "film")
									.frame(width: 150, height: 84)
									.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
									.overlay {
										RoundedRectangle(cornerRadius: 12, style: .continuous)
											.strokeBorder(.white.opacity(trailer == current ? 0.9 : 0.15),
											              lineWidth: trailer == current ? 2 : 1)
									}
								Text(trailer.name)
									.font(.system(size: 11, weight: .semibold))
									.foregroundStyle(.white)
									.lineLimit(2)
									.multilineTextAlignment(.leading)
								Text(trailer.isTeaser ? "Teaser" : "Trailer")
									.font(.system(size: 10, weight: .medium))
									.foregroundStyle(.white.opacity(0.55))
							}
							.frame(width: 150, alignment: .leading)
						}
						.buttonStyle(.plain)
						.accessibilityLabel("Play \(trailer.name)")
						.accessibilityAddTraits(trailer == current ? .isSelected : [])
					}
				}
				.padding(.horizontal, 18)
			}
			.scrollIndicators(.hidden)
			.padding(.horizontal, -18)
		}
	}

	// MARK: Loading

	private func load() async {
		guard let source else { return }
		if let hit = Self.cache[source] {
			trailers = hit
			return
		}
		playing = nil
		let fetched = try? await source.videos()
		guard !Task.isCancelled else { return }
		let found = fetched.map(Trailers.ranked) ?? []
		// Only an answer is kept: a failed fetch tries again next time the page opens.
		if fetched != nil { Self.cache[source] = found }
		withAnimation(.easeOut(duration: 0.2)) { trailers = found }
	}
}

// MARK: - Player

/// YouTube's embedded player, playing inline as soon as it loads.
private struct YouTubePlayer: UIViewRepresentable {
	let key: String

	func makeUIView(context: Context) -> WKWebView {
		let config = WKWebViewConfiguration()
		config.allowsInlineMediaPlayback = true
		config.allowsPictureInPictureMediaPlayback = true
		config.mediaTypesRequiringUserActionForPlayback = []
		let view = WKWebView(frame: .zero, configuration: config)
		view.isOpaque = false
		view.backgroundColor = .clear
		view.scrollView.backgroundColor = .clear
		view.scrollView.isScrollEnabled = false
		view.scrollView.contentInsetAdjustmentBehavior = .never
		load(key, into: view)
		return view
	}

	func updateUIView(_ view: WKWebView, context: Context) {}

	/// YouTube refuses to play an embed that arrives with no Referer, so the
	/// page gets an https origin; the app's bundle id is what YouTube asks apps to use.
	private func load(_ key: String, into view: WKWebView) {
		let origin = "https://" + (Bundle.main.bundleIdentifier ?? "watchlist.app").lowercased()
		let html = """
		<!doctype html><html><head>
		<meta name="viewport" content="width=device-width,initial-scale=1">
		<style>html,body{margin:0;height:100%;background:transparent;overflow:hidden}
		iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style>
		</head><body>
		<iframe src="https://www.youtube.com/embed/\(key)?playsinline=1&autoplay=1&rel=0"
		 allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen
		 referrerpolicy="strict-origin-when-cross-origin"></iframe>
		</body></html>
		"""
		view.loadHTMLString(html, baseURL: URL(string: origin))
	}
}
