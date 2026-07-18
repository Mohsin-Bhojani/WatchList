//
//  ShowDetailView.swift
//  WatchList
//
//  A Show's page: backdrop/poster header, synopsis, series trivia, and the
//  list of seasons (each links to its own page). Seasons can be added manually.
//

import SwiftUI
import SwiftData

struct ShowDetailView: View {
	@Environment(\.modelContext) private var ctx
	@Bindable var show: Show

	@State private var loadingTrivia = false
	@State private var showingAddSeason = false

	/// Setting a show to "Watched" optionally cascades to every season and
	/// episode. Controlled by the "Mark All Episodes Watched" toggle in the iOS
	/// Settings app (default on).
	private var watchedCascadeBinding: Binding<WatchStatus> {
		Binding(
			get: { show.status },
			set: { newValue in
				show.status = newValue
				guard newValue == .watched,
				      UserDefaults.standard.bool(forKey: "autoMarkEpisodesWatched")
				else { return }
				withAnimation(Glass.pop) {
					for season in show.seasons {
						season.status = .watched
						for episode in season.episodes { episode.status = .watched }
					}
				}
			}
		)
	}

	var body: some View {
		ZStack {
			GlassBackground()
			ScrollView {
				VStack(alignment: .leading, spacing: 20) {
					DetailHeader(
						posterURL: show.posterURL,
						backdropURL: show.backdropURL,
						title: show.title,
						subtitle: [show.firstAirYear, show.genre].filter { !$0.isEmpty }.joined(separator: "  ·  "),
						meta: show.subtitle,
						imdbID: show.imdbID,
						placeholder: "tv"
					)

					VStack(alignment: .leading, spacing: 10) {
						SectionLabel(text: "Status")
						StatusPicker(status: watchedCascadeBinding)
					}

					SynopsisSection(text: show.overview)

					// Seasons
					VStack(alignment: .leading, spacing: 12) {
						HStack {
							SectionLabel(text: "Seasons", systemImage: "rectangle.stack.fill")
							Spacer()
							Button { showingAddSeason = true } label: {
								Image(systemName: "plus.circle.fill")
									.font(.system(size: 20, weight: .semibold))
									.foregroundStyle(Glass.accent)
							}
						}
						if show.seasons.isEmpty {
							Text("No seasons yet. Tap + to add one, or import via an IMDb link.")
								.font(.system(size: 14, weight: .medium, design: .rounded))
								.foregroundStyle(.secondary)
								.frame(maxWidth: .infinity, alignment: .leading)
								.padding(16).glass(cornerRadius: 18)
						} else {
							ForEach(show.sortedSeasons) { season in
								NavigationLink { SeasonDetailView(season: season) } label: {
									GlassRow(
										title: season.displayName,
										subtitle: "\(season.episodes.count) episodes · \(season.watchedCount) watched",
										thumbURL: season.posterURL.isEmpty ? show.posterURL : season.posterURL,
										thumbPlaceholder: "tv",
										status: season.status
									)
								}
								.buttonStyle(.pressable)
								.contextMenu {
									Button(role: .destructive) { withAnimation { ctx.delete(season) } } label: {
										Label("Delete Season", systemImage: "trash")
									}
								}
							}
						}
					}

					TriviaSection(trivia: show.trivia, isLoading: loadingTrivia,
					              hasIMDb: !(show.imdbID ?? "").isEmpty)

					Color.clear.frame(height: 20)
				}
				.padding(18)
			}
		}
		.navigationTitle(show.title)
		.navigationBarTitleDisplayMode(.inline)
		.toolbarBackground(.hidden, for: .navigationBar)
		.sheet(isPresented: $showingAddSeason) {
			AddSeasonSheet(show: show)
		}
		.task {
			guard !show.triviaFetched else { return }
			loadingTrivia = true
			await TriviaLoader.loadIfNeeded(for: show)
			loadingTrivia = false
		}
	}
}

// MARK: - Add Season sheet

struct AddSeasonSheet: View {
	@Environment(\.modelContext) private var ctx
	@Environment(\.dismiss) private var dismiss
	@Bindable var show: Show

	@State private var number = ""
	@State private var name = ""
	@State private var overview = ""

	private var suggestedNumber: Int { (show.seasons.map { $0.seasonNumber }.max() ?? 0) + 1 }

	var body: some View {
		NavigationStack {
			ZStack {
				GlassBackground()
				ScrollView {
					VStack(alignment: .leading, spacing: 16) {
						SectionLabel(text: "Season number")
						TextField("\(suggestedNumber)", text: $number)
							.keyboardType(.numberPad)
							.font(.system(size: 15, weight: .medium, design: .rounded))
							.padding(15).glass(cornerRadius: 16)
						SectionLabel(text: "Name (optional)")
						TextField("Season \(suggestedNumber)", text: $name)
							.font(.system(size: 15, weight: .medium, design: .rounded))
							.padding(15).glass(cornerRadius: 16)
						SectionLabel(text: "Overview (optional)")
						TextField("What happens this season?", text: $overview, axis: .vertical)
							.lineLimit(3...6)
							.font(.system(size: 15, weight: .medium, design: .rounded))
							.padding(15).glass(cornerRadius: 16)

						Button {
							let n = Int(number) ?? suggestedNumber
							let season = Season(seasonNumber: n, name: name, overview: overview)
							season.show = show
							ctx.insert(season)
							Haptics.success(); dismiss()
						} label: {
							Text("Add Season").font(.system(size: 16, weight: .bold, design: .rounded))
								.foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 15)
								.background(Capsule().fill(LinearGradient(colors: [Glass.accent, Glass.accent2],
								                                         startPoint: .leading, endPoint: .trailing)))
						}
						.buttonStyle(.pressable)
					}
					.padding(18)
				}
			}
			.navigationTitle("New Season")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
		}
	}
}
