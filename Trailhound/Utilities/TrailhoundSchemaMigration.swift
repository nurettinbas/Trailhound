import Foundation
import SwiftData

enum TrailhoundSchemaV5: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(5, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Trip.self, TripPoint.self, SavedPlace.self, TripStop.self, UserCategory.self, MatchedRoutePoint.self, TravelJournal.self]
    }
}

/// Legacy in-memory / test schema before connection fields on vehicles.
/// Care models are listed because live `VehicleProfile` relationships require them in the same schema.
enum TrailhoundSchemaV6: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(6, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Trip.self, TripPoint.self, SavedPlace.self, TripStop.self, UserCategory.self,
            MatchedRoutePoint.self, VehicleProfile.self, VehicleSchedule.self, VehicleExpense.self, TravelJournal.self,
        ]
    }
}

enum TrailhoundSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(8, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Trip.self, TripPoint.self, SavedPlace.self, TripStop.self, UserCategory.self,
            MatchedRoutePoint.self, VehicleProfile.self, VehicleSchedule.self, VehicleExpense.self, TravelJournal.self,
        ]
    }
}

/// Adds precomputed derived fields on `Trip` (night distance, start/end coordinates, search index).
/// All are optional and additive, so existing rows open with `nil` and are backfilled at runtime by
/// `TripDerivedBackfillService`. No property is removed or renamed.
enum TrailhoundSchemaV10: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(10, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [
            Trip.self, TripPoint.self, SavedPlace.self, TripStop.self, UserCategory.self,
            MatchedRoutePoint.self, VehicleProfile.self, VehicleSchedule.self, VehicleExpense.self, TravelJournal.self,
        ]
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
            VehicleSchedule.self,
            VehicleExpense.self,
            TravelJournal.self,
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
            VehicleSchedule.self,
            VehicleExpense.self,
            TravelJournal.self,
        ]
    }
}

/// Adds vehicle care schedules/expenses and optional `currentOdometerKm`. Purely additive.
enum TrailhoundSchemaV13: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(13, 0, 0) }

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
            VehicleSchedule.self,
            VehicleExpense.self,
            TravelJournal.self,
        ]
    }
}

/// Adds optional installment fields on `VehicleExpense` (`installmentGroupID`, index, count, total).
/// Additive only: existing one-shot rows stay `nil` and keep their amount/date.
enum TrailhoundSchemaV14: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(14, 0, 0) }

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
            VehicleSchedule.self,
            VehicleExpense.self,
            TravelJournal.self,
        ]
    }
}

/// Adds cruise / stop derived fields on `Trip` and matching totals on `TripDailyRollup`.
/// All additive: existing trips open with `nil` cruise/stop and are backfilled at runtime;
/// rollup columns default to 0 until `TripRollupService` rebuilds.
enum TrailhoundSchemaV15: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(15, 0, 0) }

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
            VehicleSchedule.self,
            VehicleExpense.self,
            TravelJournal.self,
        ]
    }
}

/// Adds optional per-trip fuel estimate inputs on `Trip` (`fuelConsumptionPer100`, `fuelUnitPrice`).
/// Additive only: existing rows open with `nil` and keep their stored `estimatedFuelCost`.
enum TrailhoundSchemaV16: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(16, 0, 0) }

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
            VehicleSchedule.self,
            VehicleExpense.self,
            TravelJournal.self,
        ]
    }
}

/// Adds optional `Trip.mostCommonSpeedKmh` and matching weight/product totals on
/// `TripDailyRollup`. Additive only: existing trips open with `nil` and are backfilled;
/// rollup columns default to 0 until `TripRollupService` rebuilds.
enum TrailhoundSchemaV17: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(17, 0, 0) }

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
            VehicleSchedule.self,
            VehicleExpense.self,
            TravelJournal.self,
        ]
    }
}

/// Adds optional `Trip.dynamicFuelCost` and matching total on `TripDailyRollup`.
/// Additive only: existing trips open with `nil` and are backfilled; rollup column defaults
/// to 0 until `TripRollupService` rebuilds. Does not rewrite `estimatedFuelCost` (avg fuel).
enum TrailhoundSchemaV18: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(18, 0, 0) }

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
            VehicleSchedule.self,
            VehicleExpense.self,
            TravelJournal.self,
        ]
    }
}

/// Adds `TravelJournal` and optional `Trip.journalID`. Additive only: existing trips open
/// unassigned (`journalID == nil`).
enum TrailhoundSchemaV19: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(19, 0, 0) }

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
            VehicleSchedule.self,
            VehicleExpense.self,
            TravelJournal.self,
        ]
    }
}

/// Schema history used by in-memory migration tests.
/// Do not pass `TrailhoundMigrationPlan` to a runtime disk `ModelContainer` — SwiftData aborts with
/// "Duplicate version checksums detected" when multiple enums reference the same live `@Model` types.
/// Tip schema must be a single live-model enum (V19); V11–V18 stay for older in-memory test containers.
enum TrailhoundMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TrailhoundSchemaV5.self, TrailhoundSchemaV19.self]
    }

    static var stages: [MigrationStage] {
        [migrateV5toV19]
    }

    static let migrateV5toV19 = MigrationStage.lightweight(
        fromVersion: TrailhoundSchemaV5.self,
        toVersion: TrailhoundSchemaV19.self
    )
}
