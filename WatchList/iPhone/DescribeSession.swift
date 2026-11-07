//
//  DescribeSession.swift
//  WatchList
//
//  Describe's lookup: the query on TMDb, ranked by the library's taste and
//  held for Discover to deal from. Split out of DescribeSearch.swift.
//

import Foundation
import FoundationModels

// MARK: - Looking it up

@Observable
final class DescribeSession {
	enum Phase: Equatable {
		case idle, working, ready
		case failed(String)
	}

	private(set) var phase: Phase = .idle
	/// What was asked for, once read.
	private(set) var query: DescribedQuery?
	/// Whether Apple's on-device model read it, rather than the word list.
	private(set) var usedModel = false
	/// What TMDb sent, the taste's favourites first.
	private(set) var candidates: [Suggestion] = []
	/// How each candidate ends, as far as it's been judged.
	private(set) var endings: [String: EndingFeel] = [:]
	/// Whether endings are still being judged in the background.
	private(set) var isJudging = false
	/// How many candidates are judged before the first card is shown.
	static let judgedBeforeShowing = 6
	/// How many are judged in all.
	static let judgedInAll = 30

	@ObservationIgnored private var judging: Task<Void, Never>?
	/// Reads one candidate's ending; the on-device model unless a test says otherwise.
	@ObservationIgnored var judge: (Suggestion) async -> EndingFeel?

	init(judge: @escaping (Suggestion) async -> EndingFeel? = { await EndingJudge.judge($0) }) {
		self.judge = judge
	}

	/// The matches: the candidates when no ending was asked for; otherwise those
	/// that don't end the opposite way, the best fits first and the taste's order
	/// among equals.
	var results: [Suggestion] {
		guard let wanted = query?.ending else { return candidates }
		let ranked = candidates.enumerated().compactMap { index, suggestion -> (Int, Int, Suggestion)? in
			EndingFit.rank(wanted: wanted, judged: endings[suggestion.id]).map { ($0, index, suggestion) }
		}
		return ranked.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }.map(\.2)
	}

	/// Fills the session without going to TMDb, for tests.
	func setForTesting(candidates: [Suggestion], query: DescribedQuery) {
		self.candidates = candidates
		self.query = query
		phase = .ready
	}

	/// "Reads as a happy ending", for a card whose ending has been judged.
	func endingNote(for suggestion: Suggestion) -> String? {
		endings[suggestion.id].map { "reads as a \($0.rawValue) ending" }
	}

	var isActive: Bool { phase != .idle }

	func clear() {
		judging?.cancel()
		judging = nil
		isJudging = false
		phase = .idle
		query = nil
		candidates = []
		endings = [:]
	}

	/// Reads `text`, looks it up and ranks the matches. `kind` and `picked` are
	/// the filter's own type and genres, which narrow it further.
	func run(_ text: String, kind: BrowseKind, picked: Set<String>, taste: TasteProfile) async {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { clear(); return }
		judging?.cancel()
		judging = nil
		isJudging = false
		phase = .working
		candidates = []
		endings = [:]
		guard TMDbConfig.isConfigured else { phase = .failed("No TMDb key."); return }

		let tv = (try? await TMDbService.shared.tvGenres()) ?? []
		let movie = (try? await TMDbService.shared.movieGenres()) ?? []
		// One list for the model, so a genre isn't offered twice: film's names, and
		// TV's where film has no match (Kids, Reality). Joint names like "Action &
		// Adventure" are film's Action and Adventure already.
		let filmNames = movie.compactMap(\.name)
		let filmSets = Similarity.genreSet(filmNames)
		let tvOnly = tv.compactMap(\.name).filter { name in
			!name.contains("&") && Similarity.genreSet([name]).isDisjoint(with: filmSets)
		}
		var (read, model) = await DescribeInterpreter.interpret(trimmed, genreNames: filmNames + tvOnly)
		for genre in picked.sorted() where !read.genres.contains(genre) { read.genres.append(genre) }
		usedModel = model

		// "Like The Gentlemen": the titles TMDb knows by those names, kept under
		// the names TMDb gives them. A name TMDb doesn't know is dropped.
		var references: [ReferenceTitle] = []
		for typed in read.references.prefix(2) {
			if let found = await ReferenceTitle.find(typed) { references.append(found) }
		}
		read.references = references.map(\.title)
		// The genres asked for in words; with none, the first title's own stand in.
		let askedGenres = read.genres
		if askedGenres.isEmpty, let first = references.first {
			let allowed = filmNames + tvOnly
			var taken = Set<String>()
			for name in first.genres {
				let set = Similarity.genreSet([name])
				guard taken.isDisjoint(with: set), let match = allowed.first(where: {
					!Similarity.genreSet([$0]).isDisjoint(with: set)
				}) else { continue }
				taken.formUnion(set)
				read.genres.append(match)
				if read.genres.count == 2 { break }
			}
		}
		query = read

		var kinds: [MediaKind] = []
		switch kind {
		case .shows: kinds = [.show]
		case .films: kinds = [.film]
		case .all:   kinds = read.kind.map { [$0] } ?? references.first.map { [$0.kind] } ?? [.film, .show]
		}

		var keywordIDs: [Int] = []
		for word in read.keywords.prefix(3) {
			if let id = try? await TMDbService.shared.keywordID(for: word) { keywordIDs.append(id) }
		}
		keywordIDs += references.first?.keywordIDs.prefix(4) ?? []

		var found: [[Suggestion]] = []
		var reached = false
		for kind in kinds {
			let table = Dictionary((kind == .show ? tv : movie).compactMap { genre in
				genre.name.map { (genre.id, $0) }
			}, uniquingKeysWith: { first, _ in first })
			func ids(_ wanted: [String]) -> [Int] {
				wanted.compactMap { name in
					let set = Similarity.genreSet([name])
					return table.filter { !Similarity.genreSet([$0.value]).isDisjoint(with: set) }.keys.min()
				}
			}
			let genreIDs = ids(read.genres)
			// TV has no Romance, say: leaving the genre out would hand back
			// everything, so this type has nothing to offer for it.
			guard genreIDs.count == read.genres.count else { reached = true; continue }
			// Every genre and the keywords; failing that, enough to go on with —
			// first without the keywords, then with only the first genre.
			let attempts: [(genres: [Int], keywords: [Int])] = [
				(genreIDs, keywordIDs), (genreIDs, []), (Array(genreIDs.prefix(1)), []),
			]
			var best: [Suggestion] = []
			for attempt in attempts {
				guard let titles = try? await TMDbService.shared.discover(
					kind, genreIDs: attempt.genres, withoutGenreIDs: ids(read.avoidGenres),
					keywordIDs: attempt.keywords) else { continue }
				reached = true
				best = titles.compactMap { Suggestion($0, kind: kind, genreNames: table) }
				if best.count >= 8 { break }
			}
			found.append(best)
		}
		guard reached else { phase = .failed("Couldn\u{2019}t reach TMDb."); return }

		// Alternate films and shows when both were asked for.
		var merged: [Suggestion] = []
		let longest = found.map(\.count).max() ?? 0
		for index in 0..<longest { for list in found where index < list.count { merged.append(list[index]) } }
		// What TMDb recommends for the titles named come first — people who liked
		// them went on to watch these — as long as they fit the rest of the
		// sentence; then the matches for its genres and keywords.
		let avoided = Similarity.genreSet(read.avoidGenres)
		let wantedGenres = Similarity.genreSet(askedGenres)
		var recommended: [Suggestion] = []
		for reference in references {
			let table = Dictionary((reference.kind == .show ? tv : movie).compactMap { genre in
				genre.name.map { (genre.id, $0) }
			}, uniquingKeysWith: { first, _ in first })
			for title in reference.recommendations {
				guard let suggestion = Suggestion(title, kind: reference.kind, genreNames: table),
				      kind.includes(suggestion.kind),
				      !recommended.contains(where: { $0.id == suggestion.id }) else { continue }
				let genres = Similarity.genreSet(suggestion.genres)
				guard genres.isDisjoint(with: avoided), wantedGenres.isEmpty || !genres.isDisjoint(with: wantedGenres)
				else { continue }
				recommended.append(suggestion)
			}
		}
		let named = Set(references.map { $0.kind.key(tmdbID: $0.id) })
		let taken = Set(recommended.map(\.id)).union(named)
		candidates = taste.ranked(recommended) + taste.ranked(merged.filter { !taken.contains($0.id) })
		await judgeEndings(wanted: read.ending)
		phase = .ready
	}

	/// With an ending asked for, reads the first candidates' endings before any
	/// card is shown, so the first cards are already the right ones, and the rest
	/// in the background as the viewer swipes.
	func judgeEndings(wanted: EndingFeel?) async {
		guard wanted != nil else { return }
		let toJudge = Array(candidates.prefix(Self.judgedInAll))
		let now = Array(toJudge.prefix(Self.judgedBeforeShowing))
		let later = Array(toJudge.dropFirst(Self.judgedBeforeShowing))
		for suggestion in now {
			guard !Task.isCancelled else { return }
			if let feel = await judge(suggestion) { endings[suggestion.id] = feel }
		}
		guard !later.isEmpty else { return }
		isJudging = true
		judging = Task { [weak self] in
			for suggestion in later {
				guard !Task.isCancelled, let self else { return }
				if let feel = await self.judge(suggestion) { self.endings[suggestion.id] = feel }
			}
			self?.isJudging = false
		}
	}
}
