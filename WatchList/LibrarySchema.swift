//
//  LibrarySchema.swift
//  WatchList
//
//  The library store's schema, versioned, so the day a model changes in a way
//  SwiftData can't migrate by itself — a renamed field, a type that changes,
//  values to work out from old ones — there's a migration plan to put the step
//  in rather than a store that won't open.
//
//  Version 1 is the store as it has always been: the models in Models.swift,
//  unchanged, so an existing library opens exactly as before.
//
//  To change a model later:
//    1. Copy the models as they are now into `LibrarySchemaV1` as nested types,
//       so version 1 keeps describing the store already on people's phones.
//    2. Make the change in Models.swift and add `LibrarySchemaV2` listing them.
//    3. Add V2 to `schemas`, and a stage from V1 to V2 to `stages` — lightweight
//       when SwiftData can infer it, custom when values need working out.
//  Adding a field with a default value needs none of this (that's how
//  `likedAspects` arrived); it still migrates in place.
//

import Foundation
import SwiftData

enum LibrarySchemaV1: VersionedSchema {
	static let versionIdentifier = Schema.Version(1, 0, 0)

	static var models: [any PersistentModel.Type] {
		[Show.self, Season.self, Episode.self, Film.self, TitleCollection.self, SuggestionDecision.self]
	}
}

enum LibraryMigrationPlan: SchemaMigrationPlan {
	static var schemas: [any VersionedSchema.Type] { [LibrarySchemaV1.self] }
	static var stages: [MigrationStage] { [] }
}

enum LibraryStore {
	/// The app's one container: the default store, opened through the plan.
	static func makeContainer() -> ModelContainer {
		do {
			return try open()
		} catch {
			// The store failing to open would otherwise show an empty library
			// that looks like everything was lost; stop loudly instead.
			fatalError("Couldn't open the library store: \(error)")
		}
	}

	/// Opens the store at `url` — the default store when nil — through the plan.
	static func open(at url: URL? = nil) throws -> ModelContainer {
		let schema = Schema(versionedSchema: LibrarySchemaV1.self)
		let configuration = url.map { ModelConfiguration(schema: schema, url: $0) } ?? ModelConfiguration(schema: schema)
		return try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self,
		                          configurations: [configuration])
	}
}
