import Foundation
import SwiftData

enum TripsTabListMode: String, CaseIterable, Identifiable {
    case trips
    case travels

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trips: L10n.tripsSegmentTrips
        case .travels: L10n.tripsSegmentTravels
        }
    }
}

enum TravelJournalPage {
    static let pageSize = 50

    struct Filters: Equatable {
        var searchText: String = ""

        var isActive: Bool {
            !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func descriptor(filters: Filters, limit: Int) -> FetchDescriptor<TravelJournal> {
        let needle = filters.searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        var descriptor = FetchDescriptor<TravelJournal>(
            predicate: listPredicate(needle: needle),
            sortBy: [SortDescriptor(\.endedOn, order: .reverse)]
        )
        descriptor.fetchLimit = limit + 1
        return descriptor
    }

    private static func listPredicate(needle: String) -> Predicate<TravelJournal> {
        #Predicate<TravelJournal> { journal in
            needle.isEmpty
                || journal.searchIndex == nil
                || journal.searchIndex!.localizedStandardContains(needle)
        }
    }

    static func countDescriptor() -> FetchDescriptor<TravelJournal> {
        FetchDescriptor<TravelJournal>()
    }
}
