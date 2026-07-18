//
//  SeasonDetailView.swift
//  WatchList
//
//  A Season's page: overview + the list of episodes (each links to its own
//  page). Episodes can be added manually.
//

import SwiftUI
import SwiftData

struct SeasonDetailView: View {
	@Environment(\.modelContext) private var ctx
	@Bindable var season: Season

	@State private var showingAddEpisode = false

	private var posterURL: String { season.posterURL.isEmpty ? (season.show?.posterURL ?? "") : season.posterURL }

	var body: some View {
		ZStack {
			GlassBackground()
			ScrollView {
				VStack(alignment: .leading, spacing: 20) {
					DetailHeader(
						posterURL: posterURL,
						backdropURL: season.show?.backdropURL ?? "",
						title: season.displayName,
						subtitle: season.show?.title ?? "",
						meta: "\(season.episodes.count) episodes · \(season.watchedCount) watched",
						imdbID: nil,
						placeholder: "tv"
					)

					VStack(alignment: .leading, spacing: 10) {
						SectionLabel(text: "Status")
						StatusPicker(status: $season.status)
					}

					if !season.overview.isEmpty {
						SynopsisSection(text: season.overview)
					}

					VStack(alignment: .leading, spacing: 12) {
						HStack {
							SectionLabel(text: "Episodes", systemImage: "list.and.film")
							Spacer()
							Button { showingAddEpisode = true } label: {
								Image(systemName: "plus.circle.fill")
									.font(.system(size: 20, weight: .semibold))
									.foregroundStyle(Glass.accent)
							}
						}
						if season.episodes.isEmpty {
							Text("No episodes yet. Tap + to add one.")
								.font(.system(size: 14, weight: .medium, design: .rounded))
								.foregroundStyle(.secondary)
								.frame(maxWidth: .infinity, alignment: .leading)
								.padding(16).glass(cornerRadius: 18)
						} else {
							ForEach(season.sortedEpisodes) { ep in
								NavigationLink { EpisodeDetailView(episode: ep) } label: {
									GlassRow(
										title: "\(ep.episodeNumber). \(ep.displayTitle)",
										subtitle: ep.synopsis,
										thumbURL: ep.stillURL,
										thumbPlaceholder: "film",
										status: ep.status
									)
								}
								.buttonStyle(.pressable)
								.contextMenu {
									Button { ep.status = .watched } label: { Label("Mark Watched", systemImage: "checkmark.circle") }
									Button(role: .destructive) { withAnimation { ctx.delete(ep) } } label: { Label("Delete", systemImage: "trash") }
								}
							}
						}
					}

					Color.clear.frame(height: 20)
				}
				.padding(18)
			}
		}
		.navigationTitle(season.displayName)
		.navigationBarTitleDisplayMode(.inline)
		.toolbarBackground(.hidden, for: .navigationBar)
		.sheet(isPresented: $showingAddEpisode) { AddEpisodeSheet(season: season) }
	}
}

// MARK: - Add Episode sheet

struct AddEpisodeSheet: View {
	@Environment(\.modelContext) private var ctx
	@Environment(\.dismiss) private var dismiss
	@Bindable var season: Season

	@State private var number = ""
	@State private var title = ""
	@State private var synopsis = ""
	@State private var imdb = ""

	private var suggestedNumber: Int { (season.episodes.map { $0.episodeNumber }.max() ?? 0) + 1 }

	var body: some View {
		NavigationStack {
			ZStack {
				GlassBackground()
				ScrollView {
					VStack(alignment: .leading, spacing: 16) {
						SectionLabel(text: "Episode number")
						TextField("\(suggestedNumber)", text: $number)
							.keyboardType(.numberPad)
							.font(.system(size: 15, weight: .medium, design: .rounded))
							.padding(15).glass(cornerRadius: 16)
						SectionLabel(text: "Title")
						TextField("Episode title", text: $title)
							.font(.system(size: 15, weight: .medium, design: .rounded))
							.padding(15).glass(cornerRadius: 16)
						SectionLabel(text: "Synopsis (optional)")
						TextField("What happens?", text: $synopsis, axis: .vertical)
							.lineLimit(3...6)
							.font(.system(size: 15, weight: .medium, design: .rounded))
							.padding(15).glass(cornerRadius: 16)
						SectionLabel(text: "Episode IMDb link/id (optional, for trivia)")
						TextField("tt...", text: $imdb)
							.textInputAutocapitalization(.never).autocorrectionDisabled()
							.font(.system(size: 15, weight: .medium, design: .rounded))
							.padding(15).glass(cornerRadius: 16)

						Button {
							let n = Int(number) ?? suggestedNumber
							let ep = Episode(episodeNumber: n, seasonNumber: season.seasonNumber,
							                 title: title, synopsis: synopsis, imdbID: IMDb.id(from: imdb))
							ep.season = season
							ctx.insert(ep)
							Haptics.success(); dismiss()
						} label: {
							Text("Add Episode").font(.system(size: 16, weight: .bold, design: .rounded))
								.foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 15)
								.background(Capsule().fill(LinearGradient(colors: [Glass.accent, Glass.accent2],
								                                         startPoint: .leading, endPoint: .trailing)))
						}
						.buttonStyle(.pressable)
						.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
						.opacity(title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
					}
					.padding(18)
				}
			}
			.navigationTitle("New Episode")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
		}
	}
}
