import Foundation
import SwiftData

/// Builds the paged fetches behind the trip list.
///
/// The list used to hold every `Trip` in memory via an unfiltered `@Query`, which made both the
/// fetch and every body pass scale with total library size. These descriptors push what the store
/// can answer down into SQLite and cap each read to one page.
enum TripListPage {
    static let pageSize = 50

    struct Filters: Equatable {
        var searchText: String = ""
        var categoryID: String?
        var dateSection: TripDateSection?
        var label: String?

        var isActive: Bool {
            categoryID != nil
                || dateSection != nil
                || label != nil
                || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// A completed trip's `categoryID` is derived: legacy rows still store `"personal"` /
    /// `"business"` while newer ones store a UUID string. Both spellings must match the filter.
    static func acceptableCategoryRawValues(for categoryID: String) -> [String] {
        if categoryID == BuiltInCategory.personalID.uuidString {
            return [categoryID, TripCategory.personal.rawValue]
        }
        if categoryID == BuiltInCategory.businessID.uuidString {
            return [categoryID, TripCategory.business.rawValue]
        }
        return [categoryID]
    }

    /// Earliest `startedAt` a trip can have and still belong to `section`. Only a lower bound:
    /// the exact section is confirmed in memory, since the boundaries move with the wall clock.
    static func lowerBound(for section: TripDateSection?, calendar: Calendar = .current) -> Date {
        guard let section else { return .distantPast }
        let now = Date()
        switch section {
        case .today:
            return calendar.startOfDay(for: now)
        case .yesterday:
            return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
                ?? .distantPast
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? .distantPast
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now)?.start ?? .distantPast
        case .older:
            return .distantPast
        }
    }

    /// Fetches one page plus a probe row, so the caller can tell whether more pages exist without
    /// a second count query.
    static func descriptor(filters: Filters, limit: Int) -> FetchDescriptor<Trip> {
        let lowerBound = lowerBound(for: filters.dateSection)
        let needle = filters.searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let categoryRawValues = filters.categoryID.map(acceptableCategoryRawValues(for:))

        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { trip in
                trip.endedAt != nil
                    && trip.startedAt >= lowerBound
                    && (categoryRawValues == nil || categoryRawValues!.contains(trip.categoryRaw))
                    // A trip with no search index has not been backfilled yet, so let it through
                    // and let the in-memory pass decide.
                    && (needle.isEmpty
                        || trip.searchIndex == nil
                        || trip.searchIndex!.localizedStandardContains(needle))
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit + 1
        return descriptor
    }

    static func newestCompletedDescriptor() -> FetchDescriptor<Trip> {
        var descriptor = FetchDescriptor<Trip>(
            predicate: #Predicate { $0.endedAt != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    static func completedInDescriptor(from lowerBound: Date) -> FetchDescriptor<Trip> {
        FetchDescriptor<Trip>(
            predicate: #Predicate { $0.endedAt != nil && $0.startedAt >= lowerBound },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
    }

    static func completedCountDescriptor() -> FetchDescriptor<Trip> {
        FetchDescriptor<Trip>(predicate: #Predicate { $0.endedAt != nil })
    }

    static func descriptor(forIDs ids: Set<UUID>) -> FetchDescriptor<Trip> {
        let idList = Array(ids)
        return FetchDescriptor<Trip>(
            predicate: #Predicate { idList.contains($0.id) },
            sortBy: [SortDescriptor(\.startedAt, order: .forward)]
        )
    }
}
