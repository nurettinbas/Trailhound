import Foundation
import SwiftData

enum UITestSupport {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting")
    }

    static var seedsSmartCategory: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting.smartCategorySeed")
    }

    static let smartCategorySeedTripID = UUID(uuidString: "aaaaaaaa-0000-4000-8000-0000000000ca")!

    /// `TrailhoundTests` runs inside the app process (`TEST_HOST`); side effects must not touch host UI.
    static var isUnitTesting: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    @MainActor
    static func configureAppIfNeeded() {
        guard isEnabled else { return }
        let settings = AppSettings.shared
        settings.completeOnboarding()
        settings.skipCarSetup()
        settings.appLockEnabled = false
        settings.developerModeEnabled = false
        settings.smartCategorySuggestionsEnabled = true
        AppNotificationArchive.save([])
        AppNotificationStore.shared.reload()
        AppNotificationStore.shared.clearAll()
    }

    @MainActor
    static func seedSampleTripIfNeeded(container: ModelContainer) {
        guard isEnabled else { return }
        let context = container.mainContext
        var descriptor = FetchDescriptor<Trip>()
        descriptor.fetchLimit = 1
        let existing = (try? context.fetch(descriptor)) ?? []
        if existing.isEmpty {
            let trip = PreviewData.sampleTrip
            context.insert(trip)
            for point in trip.points {
                context.insert(point)
            }
        }
        if seedsSmartCategory {
            seedSmartCategoryFixtures(in: context)
        }
        try? context.save()
    }

    @MainActor
    private static func seedSmartCategoryFixtures(in context: ModelContext) {
        let seedID = smartCategorySeedTripID
        var existingSeed = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == seedID })
        existingSeed.fetchLimit = 1
        if let trip = try? context.fetch(existingSeed).first {
            trip.categoryID = BuiltInCategory.personalID.uuidString
            trip.categoryOriginRaw = nil
            trip.pendingSuggestedCategoryID = BuiltInCategory.businessID.uuidString
            trip.pendingSuggestionReasonRaw = TripCategorySuggestionReason.place.rawValue
            return
        }

        let home = SavedPlace(
            name: "Home",
            latitude: 41.0,
            longitude: 29.0,
            radiusMeters: 300,
            kind: .home
        )
        let work = SavedPlace(
            name: "Work",
            latitude: 41.1,
            longitude: 29.1,
            radiusMeters: 300,
            kind: .work
        )
        context.insert(home)
        context.insert(work)

        let startedAt = Date().addingTimeInterval(-1_800)
        let endedAt = Date().addingTimeInterval(-300)
        let trip = Trip(
            id: seedID,
            startedAt: startedAt,
            endedAt: endedAt,
            distanceMeters: 8_000,
            category: .personal,
            startPlaceName: "Home",
            endPlaceName: "Work"
        )
        trip.startLatitude = home.latitude
        trip.startLongitude = home.longitude
        trip.endLatitude = work.latitude
        trip.endLongitude = work.longitude
        trip.pendingSuggestedCategoryID = BuiltInCategory.businessID.uuidString
        trip.pendingSuggestionReasonRaw = TripCategorySuggestionReason.place.rawValue
        context.insert(trip)
    }
}
