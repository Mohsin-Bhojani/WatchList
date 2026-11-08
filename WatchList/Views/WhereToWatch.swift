//
//  WhereToWatch.swift
//  WatchList
//
//  A film's or show's trailer, and where it's streaming, renting and for sale
//  in the iPhone's own region — both from TMDb, the second from JustWatch's
//  data through TMDb. Fetched when a title page opens and kept for the
//  session; nothing is stored in the library.
//
//  The choices are made here, away from the views, so they can be tested:
//  which video is the trailer, and how the offers are grouped and ordered.
//

import SwiftUI
import WebKit
import WatchListCore
import WatchListLibrary

// MARK: - Choosing

enum TitleExtras {

	/// The video to play as the trailer: on YouTube, a Trailer before a Teaser,
	/// official before not, English before other languages, newest first. Nil
	/// when there's neither a trailer nor a teaser.
	static func trailer(from videos: [TMDbVideo]) -> TMDbVideo? {
		let playable = videos.filter { $0.site == "YouTube" && ($0.type == "Trailer" || $0.type == "Teaser") }
		return playable.min { a, b in
			let rankA = rank(a), rankB = rank(b)
			if rankA != rankB { return rankA < rankB }
			return (a.published_at ?? "") > (b.published_at ?? "")
		}
	}

	private static func rank(_ video: TMDbVideo) -> Int {
		(video.type == "Trailer" ? 0 : 4) + (video.official == true ? 0 : 2) + (video.iso_639_1 == "en" ? 0 : 1)
	}

	static func youtubeURL(_ video: TMDbVideo) -> URL? {
		URL(string: "https://www.youtube.com/watch?v=\(video.key)")
	}

	/// The region to show offers for: the iPhone's own, or the US without one.
	static var region: String { Locale.current.region?.identifier ?? "US" }

	/// One way to watch, and the services offering it.
	struct Offer: Equatable, Identifiable {
		enum Kind: String, CaseIterable { case stream = "Stream", free = "Free", rent = "Rent", buy = "Buy" }
		let kind: Kind
		let services: [Service]
		var id: Kind { kind }
	}

	struct Service: Equatable, Identifiable {
		let id: Int
		let name: String
		let logoURL: String
	}

	struct Availability: Equatable {
		let offers: [Offer]
		/// TMDb's page for the title in the region, which links on to each service.
		let link: URL?
	}

	/// Offers in `region`, grouped stream, free, rent, buy, each in TMDb's
	/// display order. Free counts both free and with-ads services, once each.
	/// Nil when the region has none.
	static func availability(_ providers: TMDbWatchProviders, region: String) -> Availability? {
		guard let here = providers.results?[region] else { return nil }
		let groups: [(Offer.Kind, [TMDbWatchProvider])] = [
			(.stream, here.flatrate ?? []),
			(.free, (here.free ?? []) + (here.ads ?? [])),
			(.rent, here.rent ?? []),
			(.buy, here.buy ?? []),
		]
		let offers = groups.compactMap { kind, list -> Offer? in
			var seen = Set<Int>()
			let services = list
				.sorted { ($0.display_priority ?? .max) < ($1.display_priority ?? .max) }
				.filter { seen.insert($0.provider_id).inserted }
				.map { Service(id: $0.provider_id, name: $0.provider_name ?? "Unknown", logoURL: TMDbConfig.logo($0.logo_path)) }
			return services.isEmpty ? nil : Offer(kind: kind, services: services)
		}
		guard !offers.isEmpty else { return nil }
		return Availability(offers: offers, link: here.link.flatMap(URL.init(string:)))
	}
}

// MARK: - Loading

/// Fetches each title's trailer and offers once a session.
@MainActor
enum TitleExtrasLoader {
	private struct Key: Hashable { let kind: MediaKind; let id: Int }
	private static var trailers: [Key: TMDbVideo?] = [:]
	private static var availability: [Key: TitleExtras.Availability?] = [:]

	static func trailer(_ kind: MediaKind, id: Int) async -> TMDbVideo? {
		let key = Key(kind: kind, id: id)
		if let cached = trailers[key] { return cached }
		guard let videos = try? await TMDbService.shared.videos(kind, id: id) else { return nil }
		let picked = TitleExtras.trailer(from: videos)
		trailers[key] = picked
		return picked
	}

	static func availability(_ kind: MediaKind, id: Int) async -> TitleExtras.Availability? {
		let key = Key(kind: kind, id: id)
		if let cached = availability[key] { return cached }
		guard let providers = try? await TMDbService.shared.watchProviders(kind, id: id) else { return nil }
		let found = TitleExtras.availability(providers, region: TitleExtras.region)
		availability[key] = found
		return found
	}
}

// MARK: - Views

/// The Trailer section, after design C of the second round: the title's
/// backdrop with a play button, and a tap turns the card itself into the
/// player — YouTube's own embedded player, playing where it sits, so the page
/// stays put. Scrolled away, the player goes and the backdrop comes back.
/// Under it, the trailer's name and a way to open it in YouTube instead.
/// Shows nothing until one's found, and nothing if none is.
struct TitleTrailerSection: View {
	let kind: MediaKind
	let tmdbID: Int?
	let backdropURL: String
	/// Film pages have no "Trailer" heading over it.
	var titled = true

	@State private var trailer: TMDbVideo?
	@State private var playing = false
	@Environment(\.openURL) private var openURL

	var body: some View {
		// A stack rather than a Group: an empty Group draws nothing, and its
		// task would never run to find the trailer.
		VStack(spacing: 0) {
			if let trailer, let url = TitleExtras.youtubeURL(trailer) {
				if titled {
					PageSection(title: "Trailer") { card(trailer, url) }
				} else {
					card(trailer, url)
				}
			}
		}
		.task(id: tmdbID) {
			guard let tmdbID else { return }
			trailer = await TitleExtrasLoader.trailer(kind, id: tmdbID)
		}
	}

	private func card(_ trailer: TMDbVideo, _ url: URL) -> some View {
		VStack(alignment: .leading, spacing: 10) {
			ZStack {
				if playing {
					YouTubePlayer(videoKey: trailer.key)
						.onDisappear { playing = false }
				} else {
					Button { withAnimation(Glass.smooth) { playing = true } } label: {
						PosterImage(urlString: backdropURL, systemPlaceholder: "film")
							.overlay { Color.black.opacity(0.25) }
							.overlay {
								Image(systemName: "play.fill")
									.font(.system(size: 18, weight: .bold))
									.foregroundStyle(.white)
									.frame(width: 52, height: 52)
									.glassEffect(.regular, in: Circle())
							}
					}
					.buttonStyle(.plain)
					.accessibilityLabel("Play trailer, \(trailer.name ?? "Trailer")")
				}
			}
			.aspectRatio(16 / 9, contentMode: .fit)
			.frame(maxWidth: .infinity)
			.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

			HStack(spacing: 10) {
				VStack(alignment: .leading, spacing: 1) {
					Text(trailer.name ?? "Trailer")
						.font(.system(size: 15, weight: .semibold))
						.lineLimit(1)
					Text(playing ? "Playing here · from YouTube" : "Plays here · from YouTube")
						.font(.system(size: 12, weight: .medium))
						.foregroundStyle(.secondary)
				}
				Spacer(minLength: 0)
				Button { playing = false; openURL(url) } label: {
					Image(systemName: "arrow.up.right.square")
						.font(.system(size: 17, weight: .semibold))
						.frame(width: 36, height: 36)
						.contentShape(Circle())
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Open in YouTube")
			}
			.padding(.horizontal, 6)
			.padding(.bottom, 4)
		}
		.padding(8)
		.glass(cornerRadius: 22)
	}
}

/// YouTube's embedded player for one video, playing inline as soon as it's
/// shown. Loaded through a small page of our own so YouTube sees where it's
/// embedded, which it needs before it will play.
struct YouTubePlayer: UIViewRepresentable {
	let videoKey: String

	func makeUIView(context: Context) -> WKWebView {
		let configuration = WKWebViewConfiguration()
		configuration.allowsInlineMediaPlayback = true
		configuration.mediaTypesRequiringUserActionForPlayback = []
		let view = WKWebView(frame: .zero, configuration: configuration)
		view.isOpaque = false
		view.backgroundColor = .black
		view.scrollView.isScrollEnabled = false
		view.loadHTMLString(Self.page(videoKey), baseURL: URL(string: "https://com.mohsin.watchlist"))
		return view
	}

	func updateUIView(_ view: WKWebView, context: Context) {}

	static func dismantleUIView(_ view: WKWebView, coordinator: ()) {
		// Stops the sound with the player.
		view.loadHTMLString("", baseURL: nil)
	}

	static func page(_ key: String) -> String {
		let safe = key.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
		return """
		<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
		<style>html,body{margin:0;height:100%;background:#000}iframe{border:0;width:100%;height:100%}</style>
		</head><body><iframe src="https://www.youtube-nocookie.com/embed/\(safe)?playsinline=1&autoplay=1&rel=0&modestbranding=1"
		allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen
		referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>
		"""
	}
}

// MARK: - Your services

/// The streaming services you use, in your order — set in Settings. Where to
/// watch puts the first of them that has a title on top.
enum StreamingServices {
	struct Saved: Codable, Equatable, Identifiable {
		let id: Int
		let name: String
		let logoURL: String
	}

	private static let key = "myStreamingServices"

	static var saved: [Saved] {
		get {
			UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode([Saved].self, from: $0) } ?? []
		}
		set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
	}
}

extension TitleExtras {
	/// The one way to watch to put first: the first of your services, in your
	/// order, that streams it or has it free; else the first it streams on, by
	/// TMDb's order; else the first anywhere. Nil when there are no offers.
	static func best(_ availability: Availability, yours: [Int]) -> (kind: Offer.Kind, service: Service)? {
		let watchable = availability.offers.filter { $0.kind == .stream || $0.kind == .free }
		for id in yours {
			for offer in watchable {
				if let service = offer.services.first(where: { $0.id == id }) { return (offer.kind, service) }
			}
		}
		if let offer = availability.offers.first, let service = offer.services.first { return (offer.kind, service) }
		return nil
	}

	/// "Stream on Apple TV", "Free on…", "Rent on…", "Buy on…".
	static func verb(_ kind: Offer.Kind) -> String {
		switch kind {
		case .stream: return "Stream on"
		case .free:   return "Free on"
		case .rent:   return "Rent on"
		case .buy:    return "Buy on"
		}
	}
}

/// Where to watch, after design B of the alternatives: one clear way in — the
/// first of your services that has it, else TMDb's best — as a large button,
/// the other ways folded under it, and JustWatch credited. Nothing when there
/// are no offers in the iPhone's region.
struct WhereToWatchSection: View {
	let kind: MediaKind
	let tmdbID: Int?

	@State private var availability: TitleExtras.Availability?
	@State private var showingMore = false
	@Environment(\.openURL) private var openURL

	var body: some View {
		// A stack, not a Group, so its task runs while there's nothing to show.
		VStack(spacing: 0) {
			if let availability {
				let yours = StreamingServices.saved.map(\.id)
				let best = TitleExtras.best(availability, yours: yours)
				let others = availability.offers.flatMap { offer in
					offer.services.filter { $0.id != best?.service.id || offer.kind != best?.kind }
						.map { (offer.kind, $0) }
				}
				PageSection(title: "Where to watch") {
					VStack(alignment: .leading, spacing: 10) {
						if let best {
							Button { if let link = availability.link { openURL(link) } } label: {
								HStack(spacing: 12) {
									PosterImage(urlString: best.service.logoURL, systemPlaceholder: "play.tv")
										.frame(width: 34, height: 34)
										.clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
									VStack(alignment: .leading, spacing: 1) {
										Text("\(TitleExtras.verb(best.kind)) \(best.service.name)")
											.font(.system(size: 16, weight: .bold))
											.lineLimit(1)
										if best.kind == .stream {
											Text(yours.contains(best.service.id) ? "One of your services" : "With a subscription")
												.font(.system(size: 12, weight: .medium))
												.foregroundStyle(.black.opacity(0.6))
										}
									}
									Spacer(minLength: 0)
									Image(systemName: "arrow.up.right")
										.font(.system(size: 14, weight: .bold))
								}
								.foregroundStyle(.black)
								.padding(.horizontal, 14)
								.frame(minHeight: 58)
								.background(.white, in: Capsule())
							}
							.buttonStyle(.pressable)
						}
						if !others.isEmpty {
							VStack(alignment: .leading, spacing: 10) {
								Button {
									withAnimation(Glass.smooth) { showingMore.toggle() }
								} label: {
									HStack {
										Text("\(others.count) more way\(others.count == 1 ? "" : "s") to watch")
											.font(.system(size: 14, weight: .semibold))
										Spacer()
										Image(systemName: "chevron.down")
											.font(.system(size: 12, weight: .bold))
											.rotationEffect(.degrees(showingMore ? 180 : 0))
									}
									.foregroundStyle(.white)
									.contentShape(Rectangle())
								}
								.buttonStyle(.plain)
								if showingMore {
									ForEach(Array(others.enumerated()), id: \.offset) { _, entry in
										HStack(spacing: 10) {
											PosterImage(urlString: entry.1.logoURL, systemPlaceholder: "play.tv")
												.frame(width: 28, height: 28)
												.clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
											Text(entry.1.name)
												.font(.system(size: 14, weight: .medium))
												.foregroundStyle(.white)
											Spacer()
											Text(entry.0.rawValue)
												.font(.system(size: 12, weight: .medium))
												.foregroundStyle(.white.opacity(0.6))
										}
										.accessibilityElement(children: .combine)
									}
								}
							}
							.padding(14)
							.liquidCard(cornerRadius: 18)
						}
						Text("Data from JustWatch")
							.font(.system(size: 11, weight: .medium))
							.foregroundStyle(.white.opacity(0.5))
					}
				}
			}
		}
		.task(id: tmdbID) {
			guard let tmdbID else { return }
			availability = await TitleExtrasLoader.availability(kind, id: tmdbID)
		}
	}
}

// MARK: - Settings: your services

/// Your streaming services, in order: drag to reorder, swipe to remove, and
/// add from every service TMDb lists in the iPhone's region.
struct StreamingServicesView: View {
	@State private var saved = StreamingServices.saved
	@State private var all: [TitleExtras.Service] = []
	@State private var loading = true

	var body: some View {
		List {
			Section {
				if saved.isEmpty {
					Text("None yet. Add the ones you pay for, and Where to watch puts them first.")
						.foregroundStyle(.secondary)
				}
				ForEach(saved) { service in
					row(name: service.name, logo: service.logoURL)
				}
				.onMove { saved.move(fromOffsets: $0, toOffset: $1); StreamingServices.saved = saved }
				.onDelete { saved.remove(atOffsets: $0); StreamingServices.saved = saved }
			} header: {
				Text("Yours, in order")
			} footer: {
				Text("Where to watch offers the first of these that has a title.")
			}
			Section("Add") {
				if loading { ProgressView() }
				ForEach(all.filter { service in !saved.contains { $0.id == service.id } }) { service in
					Button {
						Haptics.selection()
						saved.append(.init(id: service.id, name: service.name, logoURL: service.logoURL))
						StreamingServices.saved = saved
					} label: {
						HStack {
							row(name: service.name, logo: service.logoURL)
							Spacer()
							Image(systemName: "plus.circle.fill").foregroundStyle(Glass.accent)
						}
					}
					.buttonStyle(.plain)
				}
			}
		}
		.scrollContentBackground(.hidden)
		.background(GlassBackground())
		.navigationTitle("Your services")
		.toolbar { EditButton() }
		.task {
			// Films' and shows' lists together, each service once, TMDb's order.
			let region = TitleExtras.region
			async let films = try? TMDbService.shared.watchProviderList(.film, region: region)
			async let shows = try? TMDbService.shared.watchProviderList(.show, region: region)
			var seen = Set<Int>()
			all = ((await films ?? []) + (await shows ?? []))
				.sorted { ($0.display_priority ?? .max) < ($1.display_priority ?? .max) }
				.filter { seen.insert($0.provider_id).inserted }
				.map { TitleExtras.Service(id: $0.provider_id, name: $0.provider_name ?? "Unknown",
				                           logoURL: TMDbConfig.logo($0.logo_path)) }
			loading = false
		}
	}

	private func row(name: String, logo: String) -> some View {
		HStack(spacing: 12) {
			PosterImage(urlString: logo, systemPlaceholder: "play.tv")
				.frame(width: 32, height: 32)
				.clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
			Text(name)
		}
	}
}
