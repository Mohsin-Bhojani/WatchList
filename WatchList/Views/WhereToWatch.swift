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

/// The Trailer section: the title's backdrop with a play button that opens the
/// trailer on YouTube. Shows nothing until one's found, and nothing if none is.
struct TitleTrailerSection: View {
	let kind: MediaKind
	let tmdbID: Int?
	let backdropURL: String
	/// Film pages have no "Trailer" heading over it.
	var titled = true

	@State private var trailer: TMDbVideo?
	@Environment(\.openURL) private var openURL

	var body: some View {
		Group {
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
		Button { openURL(url) } label: {
			PosterImage(urlString: backdropURL, systemPlaceholder: "film")
				.aspectRatio(16 / 9, contentMode: .fit)
				.frame(maxWidth: .infinity)
				.overlay { Color.black.opacity(0.25) }
				.overlay {
					Image(systemName: "play.fill")
						.font(.system(size: 18, weight: .bold))
						.foregroundStyle(.white)
						.frame(width: 48, height: 48)
						.glassEffect(.regular, in: Circle())
				}
				.overlay(alignment: .bottomLeading) {
					Text(trailer.name ?? "Trailer")
						.font(.system(size: 12, weight: .semibold))
						.foregroundStyle(.white)
						.lineLimit(1)
						.padding(.horizontal, 10)
						.padding(.vertical, 5)
						.background(.black.opacity(0.45), in: Capsule())
						.padding(10)
				}
				.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
		}
		.buttonStyle(.plain)
		.accessibilityLabel("Play trailer, \(trailer.name ?? "Trailer"), on YouTube")
	}
}

/// Where to watch: the services streaming, free, renting and selling the title
/// in the iPhone's region. Shows nothing when there are none.
struct WhereToWatchSection: View {
	let kind: MediaKind
	let tmdbID: Int?

	@State private var availability: TitleExtras.Availability?
	@Environment(\.openURL) private var openURL

	var body: some View {
		Group {
			if let availability {
				PageSection(title: "Where to watch") {
					VStack(alignment: .leading, spacing: 14) {
						ForEach(availability.offers) { offer($0) }
						HStack {
							Text("Data from JustWatch")
								.font(.system(size: 11, weight: .medium))
								.foregroundStyle(.white.opacity(0.5))
							Spacer()
							if let link = availability.link {
								Button("See all") { openURL(link) }
									.font(.system(size: 12, weight: .semibold))
									.foregroundStyle(.white)
							}
						}
					}
					.padding(14)
					.liquidCard(cornerRadius: 20)
				}
			}
		}
		.task(id: tmdbID) {
			guard let tmdbID else { return }
			availability = await TitleExtrasLoader.availability(kind, id: tmdbID)
		}
	}

	private func offer(_ offer: TitleExtras.Offer) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			PageSmallCaps(text: offer.kind.rawValue)
			ScrollView(.horizontal, showsIndicators: false) {
				HStack(spacing: 10) {
					ForEach(offer.services) { service in
						PosterImage(urlString: service.logoURL, systemPlaceholder: "play.tv")
							.frame(width: 44, height: 44)
							.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
							.accessibilityLabel(service.name)
					}
				}
			}
		}
		.accessibilityElement(children: .contain)
		.accessibilityLabel("\(offer.kind.rawValue): \(offer.services.map(\.name).joined(separator: ", "))")
	}
}
