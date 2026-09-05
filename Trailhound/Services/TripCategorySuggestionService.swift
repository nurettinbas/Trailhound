import Foundation
import SwiftData

enum TripCategorySuggestionService {
    /// Writes or clears the pending suggestion on a completed trip. Never changes `categoryID`.
    static func refreshPending(
        on trip: Trip,
        among trips: [Trip],
        places: [SavedPlace],
        enabled: Bool,
        workHours: TripCategoryWorkHours = .default,
        calendar: Calendar = .current
    ) {
        guard trip.endedAt != nil else { return }

        guard enabled else {
            trip.clearPendingSuggestion()
            return
        }

        let histogram = FrequentRoutesService.categoryHistogram(from: trips, excluding: trip.id)
        if let suggestion = TripCategorySuggester.suggestion(
            for: trip,
            places: places,
            histogram: histogram,
            workHours: workHours,
            calendar: calendar
        ) {
            trip.pendingSuggestedCategoryID = suggestion.categoryID
            trip.pendingSuggestionReasonRaw = suggestion.reason.rawValue
        } else {
            trip.clearPendingSuggestion()
        }
    }

    /// Applies the pending suggestion. Updates daily rollups to the new category.
    @MainActor
    static func acceptPending(_ trip: Trip, in context: ModelContext) {
        guard let categoryID = trip.pendingSuggestedCategoryID else { return }
        applyCategory(categoryID, to: trip, origin: .accepted, in: context)
    }

    /// User picked a category from the menu or trip detail. Clears any pending suggestion.
    @MainActor
    static func applyUserCategory(_ categoryID: String, to trip: Trip, in context: ModelContext) {
        applyCategory(categoryID, to: trip, origin: .user, in: context)
    }

    @MainActor
    static func applyCategory(
        _ categoryID: String,
        to trip: Trip,
        origin: TripCategoryOrigin,
        in context: ModelContext
    ) {
        let previous = TripRollupService.snapshot(of: trip)
        trip.categoryID = categoryID
        trip.categoryOrigin = origin
        trip.clearPendingSuggestion()
        TripRollupService.update(trip, from: previous, in: context)
    }
}
