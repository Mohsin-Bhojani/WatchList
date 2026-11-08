//
//  PersonPage.swift
//  WatchList
//
//  A cast member's page, after design D of the second round — like an artist
//  page in Music: their round portrait and name, how much of their work is in
//  your library, then a switch between your titles with them and everything
//  they've acted in, and their full page on TMDb.
//

import SwiftUI
import SwiftData
import WatchListCore
import WatchListLibrary

struct PersonPage: View {
	let personID: Int
	/// Shown while the page loads: what the cast row already knew.
	let name: String
	let profileURL: String

	enum Shelf: String, CaseIterable, Identifiable {
		case yours = "In your library"
		case all = "All titles"
		var id: String { rawValue }
	}

	@Query private var shows: [Show]
	@Query private var films: [Film]
	@State private var person: TMDbPerson?
	@State private var credits: [TMDbPersonCredit] = []
	@State private var loaded = false
	@State private var shelf: Shelf = .yours

	/// A credit that's in your library, with the title it matched.
	struct Owned: Identifiable {
		let credit: TMDbPersonCredit
		let show: Show?
		let film: Film?
		var id: String { "\(credit.media_type ?? "")-\(credit.id)" }
		var status: WatchStatus { show?.status ?? film?.status ?? .toWatch }
	}

	private var owned: [Owned] {
		credits.compactMap { credit in
			switch credit.kind {
			case .show:
				return shows.first { $0.tmdbID == credit.id }.map { Owned(credit: credit, show: $0, film: nil) }
			case .film:
				return films.first { $0.tmdbID == credit.id }.map { Owned(credit: credit, show: nil, film: $0) }
			}
		}
	}

	var body: some View {
		let owned = owned
		ScrollView {
			VStack(spacing: 16) {
				header(owned: owned)
				Picker("Show", selection: $shelf.animation(Glass.smooth)) {
					ForEach(Shelf.allCases) { Text($0.rawValue).tag($0) }
				}
				.pickerStyle(.segmented)

				switch shelf {
				case .yours: yours(owned)
				case .all: everything(owned)
				}

				Link(destination: URL(string: "https://www.themoviedb.org/person/\(personID)")!) {
					Label("Open the full page on TMDb", systemImage: "arrow.up.right")
						.font(.system(size: 15, weight: .semibold))
						.frame(maxWidth: .infinity, minHeight: GlassControl.height)
				}
				.buttonStyle(.glass)
			}
			.padding(.horizontal, 18)
			.padding(.bottom, 24)
		}
		.background(GlassBackground())
		// Named for the back button's menu; the page shows the name itself.
		.navigationTitle(person?.name ?? name)
		.toolbar(removing: .title)
		.task(id: personID) { await load() }
	}

	private func header(owned: [Owned]) -> some View {
		let watching = owned.filter { $0.status == .watching }.count
		let line = [
			person?.known_for_department,
			loaded ? "\(owned.count) in your library" : nil,
			watching > 0 ? "\(watching) watching" : nil,
		].compactMap { $0 }.joined(separator: " · ")
		return VStack(spacing: 8) {
			PersonAvatar(urlString: person.map { TMDbConfig.profile($0.profile_path) } ?? profileURL, name: name)
				.frame(width: 120, height: 120)
				.overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 3))
				.shadow(color: .black.opacity(0.35), radius: 16, y: 8)
				.padding(.top, 12)
			Text(person?.name ?? name)
				.font(.system(size: 28, weight: .heavy))
				.multilineTextAlignment(.center)
			if !line.isEmpty {
				Text(line)
					.font(.system(size: 13, weight: .medium))
					.foregroundStyle(.secondary)
			}
		}
		.frame(maxWidth: .infinity)
	}

	@ViewBuilder private func yours(_ owned: [Owned]) -> some View {
		if !loaded {
			ProgressView().padding(.vertical, 30)
		} else if owned.isEmpty {
			Text("Nothing of theirs in your library yet. All titles has everything they've acted in.")
				.font(.system(size: 14, weight: .medium))
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.padding(18)
				.frame(maxWidth: .infinity)
				.glass(cornerRadius: 18)
		} else {
			list(owned.map { item in
				Row(credit: item.credit, status: item.status) {
					if let show = item.show { PhoneShowDetailView(show: show) }
					else if let film = item.film { PhoneFilmDetailView(film: film) }
				}
			})
		}
	}

	@ViewBuilder private func everything(_ owned: [Owned]) -> some View {
		if !loaded {
			ProgressView().padding(.vertical, 30)
		} else {
			let mine = Dictionary(owned.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
			list(credits.map { credit in
				let item = mine["\(credit.media_type ?? "")-\(credit.id)"]
				return Row(credit: credit, status: item?.status) {
					if let show = item?.show { PhoneShowDetailView(show: show) }
					else if let film = item?.film { PhoneFilmDetailView(film: film) }
				}
			})
		}
	}

	private func list(_ rows: [Row]) -> some View {
		LazyVStack(spacing: 0) {
			ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
				if index > 0 { PageRowDivider(inset: 48) }
				row
			}
		}
		.padding(.horizontal, 14)
		.glass(cornerRadius: 20)
	}

	/// One title they're in: its poster, name, who they play and the year. A
	/// title in your library opens its page and shows its status.
	struct Row: View {
		let credit: TMDbPersonCredit
		let status: WatchStatus?
		let destination: AnyView?

		init<Destination: View>(credit: TMDbPersonCredit, status: WatchStatus?,
		                        @ViewBuilder destination: () -> Destination) {
			self.credit = credit
			self.status = status
			self.destination = status == nil ? nil : AnyView(destination())
		}

		var body: some View {
			if let destination {
				NavigationLink { destination } label: { content }
					.buttonStyle(.plain)
			} else {
				content
			}
		}

		private var content: some View {
			HStack(spacing: 12) {
				PosterImage(urlString: TMDbConfig.poster(credit.poster_path),
				            systemPlaceholder: credit.kind == .show ? "tv" : "film")
					.frame(width: 34, height: 51)
					.clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
				VStack(alignment: .leading, spacing: 2) {
					Text(credit.displayTitle)
						.font(.system(size: 15, weight: .semibold))
						.lineLimit(2)
					Text([credit.character?.isEmpty == false ? credit.character : nil, credit.year]
						.compactMap { $0 }.joined(separator: " · "))
						.font(.system(size: 12, weight: .medium))
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}
				Spacer(minLength: 0)
				if let status {
					HStack(spacing: 5) {
						Circle().fill(Glass.tint(status)).frame(width: 7, height: 7)
						Text(status.rawValue)
							.font(.system(size: 12, weight: .semibold))
							.foregroundStyle(.secondary)
					}
					Image(systemName: "chevron.right")
						.font(.system(size: 12, weight: .bold))
						.foregroundStyle(.tertiary)
				}
			}
			.padding(.vertical, 9)
			.contentShape(Rectangle())
		}
	}

	private func load() async {
		async let who = try? TMDbService.shared.person(personID)
		async let work = try? TMDbService.shared.personCredits(personID)
		let (found, all) = await (who, work)
		person = found
		credits = TMDbPersonCredit.titles(all?.cast ?? [])
		loaded = true
		// With nothing of theirs in the library, start on everything.
		if owned.isEmpty { shelf = .all }
	}
}
