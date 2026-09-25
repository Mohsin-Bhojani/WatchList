//
//  WhereToWatch.swift
//  WatchList
//
//  Where a show or film streams, rents and sells in your chosen country: the
//  services' logos in Stream / Rent / Buy lines. TMDb's data comes from
//  JustWatch, and says which services carry a title but not where in them, so
//  a logo opens the service itself — its search for the title where the
//  service has a search link, otherwise its home — and a service this doesn't
//  know opens TMDb's watch page for the title, which links on to it.
//
//  The country is Settings' Where to Watch choice, the phone's region until
//  one is picked.
//

import SwiftUI

/// The country Where to watch lists services for.
enum WatchRegion {
	/// UserDefaults key. Empty means "the phone's region".
	static let key = "watchRegion"

	static var phone: String { Locale.current.region?.identifier ?? "US" }

	static func resolved(_ stored: String) -> String { stored.isEmpty ? phone : stored }

	static func name(_ code: String) -> String {
		Locale.current.localizedString(forRegionCode: code) ?? code
	}
}

/// One service offering a title, and where tapping its logo goes.
struct WatchOffer: Identifiable, Equatable {
	let providerID: Int
	let name: String
	let logoURL: String
	let url: URL?

	var id: Int { providerID }
}

/// One country's offers, grouped the way the page shows them.
struct WatchOptions: Equatable {
	var stream: [WatchOffer] = []
	var rent: [WatchOffer] = []
	var buy: [WatchOffer] = []

	var isEmpty: Bool { stream.isEmpty && rent.isEmpty && buy.isEmpty }
}

enum WhereToWatch {
	/// A country's offers. Subscription, free and with-ads all count as
	/// Stream; each line keeps JustWatch's order and lists a service once.
	static func options(_ region: TMDbProviderRegion?, title: String) -> WatchOptions {
		guard let region else { return WatchOptions() }
		let fallback = region.link.flatMap(URL.init(string:))
		func line(_ groups: [TMDbProvider]?...) -> [WatchOffer] {
			var seen = Set<Int>()
			return groups.compactMap { $0 }.joined()
				.sorted { ($0.display_priority ?? .max) < ($1.display_priority ?? .max) }
				.compactMap { provider in
					guard let id = provider.provider_id, let name = provider.provider_name,
					      seen.insert(id).inserted else { return nil }
					return WatchOffer(providerID: id, name: name, logoURL: TMDbConfig.logo(provider.logo_path),
					                  url: link(providerID: id, name: name, title: title) ?? fallback)
				}
		}
		return WatchOptions(stream: line(region.flatrate, region.free, region.ads),
		                    rent: line(region.rent), buy: line(region.buy))
	}

	/// A service's own link for a title: a search where it has one, its home
	/// where it doesn't. Nil for a service this doesn't know. Web links, which
	/// open the service's app when it's installed.
	static func link(providerID: Int, name: String, title: String) -> URL? {
		let lowered = name.lowercased()
		// Channels sold inside Prime Video and Apple TV are watched there.
		let service = services.first { $0.ids.contains(providerID) }
			?? (lowered.contains("amazon channel") ? primeVideo : nil)
			?? (lowered.contains("apple tv channel") ? appleTV : nil)
		guard let service else { return nil }
		guard let search = service.search,
		      let query = title.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed),
		      !title.isEmpty else { return URL(string: service.home) }
		return URL(string: search.replacingOccurrences(of: "{q}", with: query))
	}

	private struct Service {
		let ids: Set<Int>
		let home: String
		/// With `{q}` where the title goes.
		var search: String?
	}

	private static let primeVideo = Service(ids: [9, 10, 119, 613], home: "https://www.primevideo.com",
	                                        search: "https://www.primevideo.com/search?phrase={q}")
	private static let appleTV = Service(ids: [2, 350], home: "https://tv.apple.com",
	                                     search: "https://tv.apple.com/search?term={q}")

	/// TMDb provider ids, from its provider lists for the US, UK, UAE and India.
	private static let services: [Service] = [
		Service(ids: [8, 175, 1796], home: "https://www.netflix.com", search: "https://www.netflix.com/search?q={q}"),
		primeVideo,
		appleTV,
		Service(ids: [337], home: "https://www.disneyplus.com", search: "https://www.disneyplus.com/search?q={q}"),
		Service(ids: [15], home: "https://www.hulu.com", search: "https://www.hulu.com/search?q={q}"),
		Service(ids: [384, 1899], home: "https://play.hbomax.com", search: "https://play.hbomax.com/search?q={q}"),
		Service(ids: [531, 2303, 2616], home: "https://www.paramountplus.com"),
		Service(ids: [386, 387], home: "https://www.peacocktv.com"),
		Service(ids: [192], home: "https://www.youtube.com", search: "https://www.youtube.com/results?search_query={q}"),
		Service(ids: [3], home: "https://play.google.com/store/movies",
		        search: "https://play.google.com/store/search?q={q}&c=movies"),
		Service(ids: [283], home: "https://www.crunchyroll.com", search: "https://www.crunchyroll.com/search?q={q}"),
		Service(ids: [11], home: "https://mubi.com"),
		Service(ids: [73], home: "https://tubitv.com"),
		Service(ids: [38], home: "https://www.bbc.co.uk/iplayer", search: "https://www.bbc.co.uk/iplayer/search?q={q}"),
		Service(ids: [103], home: "https://www.channel4.com"),
		Service(ids: [41], home: "https://www.itv.com/watch"),
		Service(ids: [629], home: "https://osnplus.com"),
		Service(ids: [1715], home: "https://shahid.mbc.net"),
		Service(ids: [630], home: "https://starzplay.com"),
		Service(ids: [232], home: "https://www.zee5.com"),
		Service(ids: [2336], home: "https://www.hotstar.com"),
		Service(ids: [237], home: "https://www.sonyliv.com"),
	]
}

private extension CharacterSet {
	/// What may stand unescaped in a query value — not `&`, `=`, `+` or `#`.
	static let urlQueryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#?"))
}

/// The Stream / Rent / Buy lines for a title page, for the country in Settings.
struct WhereToWatchList: View {
	let source: TitleSource
	/// Searched for in the service a logo opens.
	let title: String

	@AppStorage(WatchRegion.key) private var storedRegion = ""
	@Environment(\.openURL) private var openURL

	/// Nil until loaded; every country's offers, so changing country needs no fetch.
	@State private var regions: [String: TMDbProviderRegion]?
	@State private var failed = false

	/// Fetched once a session per title.
	private static var cache: [TitleSource: [String: TMDbProviderRegion]] = [:]

	init(source: TitleSource, title: String) {
		self.source = source
		self.title = title
		_regions = State(initialValue: Self.cache[source])
	}

	private var region: String { WatchRegion.resolved(storedRegion) }

	var body: some View {
		VStack(alignment: .leading, spacing: 8) {
			if let regions {
				let options = WhereToWatch.options(regions[region], title: title)
				if options.isEmpty {
					note("Not streaming, for rent or for sale in \(WatchRegion.name(region)).")
				} else {
					line("Stream", options.stream)
					line("Rent", options.rent)
					line("Buy", options.buy)
				}
				Text("\(WatchRegion.name(region)) · Data from JustWatch")
					.font(.system(size: 10, weight: .medium))
					.foregroundStyle(.white.opacity(0.45))
			} else {
				note(failed ? "Couldn't load where to watch." : "Looking…")
			}
		}
		.task(id: source) { await load() }
	}

	@ViewBuilder
	private func line(_ label: String, _ offers: [WatchOffer]) -> some View {
		if !offers.isEmpty {
			HStack(spacing: 10) {
				Text(label)
					.font(.system(size: 12, weight: .semibold))
					.foregroundStyle(.white.opacity(0.6))
					.frame(width: 46, alignment: .leading)
				ScrollView(.horizontal) {
					HStack(spacing: 8) {
						ForEach(offers) { offer in
							Button {
								if let url = offer.url { openURL(url) }
							} label: {
								PosterImage(urlString: offer.logoURL, systemPlaceholder: "tv")
									.frame(width: 36, height: 36)
									.clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
									.overlay {
										RoundedRectangle(cornerRadius: 9, style: .continuous)
											.strokeBorder(.white.opacity(0.15), lineWidth: 1)
									}
							}
							.buttonStyle(.plain)
							.disabled(offer.url == nil)
							.accessibilityLabel("\(label) on \(offer.name)")
							.accessibilityHint("Opens \(offer.name)")
						}
					}
				}
				.scrollIndicators(.hidden)
			}
		}
	}

	private func note(_ text: String) -> some View {
		Text(text)
			.font(.system(size: 14, weight: .semibold))
			.foregroundStyle(.white)
	}

	private func load() async {
		if let hit = Self.cache[source] {
			regions = hit
			return
		}
		failed = false
		do {
			let fetched = try await source.watchProviders()
			guard !Task.isCancelled else { return }
			Self.cache[source] = fetched
			regions = fetched
		} catch {
			if !Task.isCancelled { failed = true }
		}
	}
}
