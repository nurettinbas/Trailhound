import Foundation
import SwiftData

enum TrailhoundSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Trip.self, TripPoint.self, SavedPlace.self, TripStop.self, UserCategory.self, MatchedRoutePoint.self]
    }
}

/// Legacy in-memory / test schema before connection fields on vehicles.
enum TrailhoundSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Trip.self, TripPoint.self, SavedPlace.self, TripStop.self, UserCategory.self, MatchedRoutePoint.self, VehicleProfile.self]
    }
}

enum TrailhoundSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(8, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Trip.self, TripPoint.self, SavedPlace.self, TripStop.self, UserCategory.self, MatchedRoutePoint.self, VehicleProfile.self]
    }
}

/// Adds precomputed derived fields on `Trip` (night distance, start/end coordinates, search index).
/// All are optional and additive, so existing rows open with `nil` and are backfilled at runtime by
/// `TripDerivedBackfillService`. No property is removed or renamed.
enum TrailhoundSchemaV10: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(10, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Trip.self, TripPoint.self, SavedPlace.self, TripStop.self, UserCategory.self, MatchedRoutePoint.self, VehicleProfile.self]
    }
}

/// Adds the `TripDailyRollup` aggregate table. Purely additive: a brand new entity, no change to
/// any existing one, so nothing a user recorded is touched. The table is derived data and is
/// populated by `TripRollupService.rebuildAll` on first launch after the upgrade.
enum TrailhoundSchemaV11: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(11, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Trip.self,
            TripPoint.self,
            SavedPlace.self,
            TripStop.self,
            UserCategory.self,
            MatchedRoutePoint.self,
            VehicleProfile.self,
            TripDailyRollup.self,
        ]
    }
}

/// Adds optional `VehicleProfile.photoFileName` (disk thumb path key). Additive only.
enum TrailhoundSchemaV12: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(12, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Trip.self,
            TripPoint.self,
            SavedPlace.self,
            TripStop.self,
            UserCategory.self,
            MatchedRoutePoint.self,
            VehicleProfile.self,
            TripDailyRollup.self,
        ]
    }
}

/// Schema history used by in-memory migration tests.
/// Do not pass `TrailhoundMigrationPlan` to a runtime disk `ModelContainer` — SwiftData aborts with
/// "Duplicate version checksums detected" when multiple enums reference the same live `@Model` types.
/// Tip schema must be a single live-model enum (V12); V11 stays for older in-memory test containers.
enum TrailhoundMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TrailhoundSchemaV5.self, TrailhoundSchemaV12.self]
    }

    static var stages: [MigrationStage] {
        [migrateV5toV12]
    }

    static let migrateV5toV12 = MigrationStage.lightweight(
        fromVersion: TrailhoundSchemaV5.self,
        toVersion: TrailhoundSchemaV12.self
    )
}
