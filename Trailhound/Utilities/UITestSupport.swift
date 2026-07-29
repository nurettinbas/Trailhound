import Foundation
import SwiftData

enum UITestSupport {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-UITesting")
    }

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
        guard existing.isEmpty else { return }

        let trip = PreviewData.sampleTrip
        context.insert(trip)
        for point in trip.points {
            context.insert(point)
        }
        try? context.save()
    }
}
