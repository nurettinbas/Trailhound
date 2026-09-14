import XCTest
@testable import Trailhound

@MainActor
final class AppNotificationStoreTests: XCTestCase {
    private let store = AppNotificationStore.shared

    override func setUp() {
        AppNotificationArchive.save([])
        store.reload()
        store.clearAll()
    }

    func testRecordIncrementsUnreadCount() {
        store.record(kind: .tripStarted, title: "Started", body: "Recording")

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.unreadCount, 1)
    }

    func testMarkReadDecrementsUnreadCount() {
        store.record(kind: .tripEnded, title: "Ended", body: "Done")
        let id = store.items[0].id

        store.markRead(id)

        XCTAssertEqual(store.unreadCount, 0)
        XCTAssertTrue(store.items[0].isRead)
    }

    func testDeleteRemovesItem() {
        store.record(kind: .tripDiscarded, title: "Discarded", body: "Removed")
        let id = store.items[0].id

        store.delete(id)

        XCTAssertTrue(store.items.isEmpty)
    }

    func testClearAllRemovesAllItems() {
        store.record(kind: .tripStarted, title: "A", body: "1")
        store.record(kind: .tripEnded, title: "B", body: "2")

        store.clearAll()

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(AppNotificationArchive.load().count, 0)
    }

    func testMarkAllReadClearsUnreadCount() {
        store.record(kind: .tripStarted, title: "A", body: "1")
        store.record(kind: .tripEnded, title: "B", body: "2")

        store.markAllRead()

        XCTAssertEqual(store.unreadCount, 0)
        XCTAssertTrue(store.items.allSatisfy(\.isRead))
    }

    func testArchiveRoundTrip() {
        let record = StoredAppNotification(
            kind: AppNotificationKind.pairingSuggestion.rawValue,
            title: "Pair",
            body: "Suggestion",
            action: TripNotificationService.openPairingAction,
            target: "pairing"
        )
        AppNotificationArchive.save([record])

        let loaded = AppNotificationArchive.load()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].title, "Pair")
        XCTAssertEqual(loaded[0].action, TripNotificationService.openPairingAction)
        XCTAssertEqual(loaded[0].target, "pairing")
    }

    func testArchiveDecodesLegacyPayloadWithoutAction() throws {
        let legacy = StoredAppNotification(
            kind: AppNotificationKind.tripEnded.rawValue,
            title: "Ended",
            body: "Done"
        )
        let data = try JSONEncoder().encode([legacy])
        let decoded = try JSONDecoder().decode([StoredAppNotification].self, from: data)
        XCTAssertNil(decoded[0].action)
        XCTAssertNil(decoded[0].target)
    }

    func testRecordSystemNotificationMapsAchievementAndRecap() {
        store.recordSystemNotification(
            title: "Badge unlocked",
            body: "First trip",
            identifier: "trailhound.achievement.first.trip"
        )
        XCTAssertEqual(store.kind(for: store.items[0]), .achievementUnlocked)
        XCTAssertEqual(store.items[0].action, TripNotificationService.openAchievementsAction)
        XCTAssertEqual(store.items[0].target, "first.trip")

        store.clearAll()
        store.recordSystemNotification(
            title: "Recap",
            body: "Ready",
            identifier: "trailhound.recap.2026"
        )
        XCTAssertEqual(store.kind(for: store.items[0]), .yearRecapReady)
        XCTAssertEqual(store.items[0].action, TripNotificationService.openRecapAction)
        XCTAssertEqual(store.items[0].target, "2026")
    }

    func testNotificationRouteResolvesActions() {
        XCTAssertEqual(
            NotificationRoute.resolve(
                action: TripNotificationService.openAchievementsAction,
                target: nil,
                tripID: nil
            ),
            .achievements
        )
        XCTAssertEqual(
            NotificationRoute.resolve(
                action: TripNotificationService.openRecapAction,
                target: "2026",
                tripID: nil
            ),
            .recap
        )
        let tripID = UUID()
        XCTAssertEqual(
            NotificationRoute.resolve(
                action: TripNotificationService.openTripAction,
                target: nil,
                tripID: tripID
            ),
            .trip(tripID)
        )
        let vehicleID = UUID()
        XCTAssertEqual(
            NotificationRoute.resolve(
                action: VehicleCareNotificationScheduler.openVehicleCareAction,
                target: vehicleID.uuidString,
                tripID: nil
            ),
            .vehicleCare(vehicleID)
        )
    }

    func testRecordCapsAtOneHundred() {
        for index in 0..<105 {
            store.record(kind: .tripEnded, title: "T\(index)", body: "B\(index)")
        }
        XCTAssertEqual(store.items.count, 100)
        XCTAssertEqual(store.items.first?.title, "T104")
    }

    func testUpdateTripStartedBodyPreservesIdentity() {
        let tripID = UUID()
        store.record(
            kind: .tripStarted,
            title: "Trip started",
            body: "Recording",
            tripID: tripID
        )
        let id = store.items[0].id

        XCTAssertTrue(store.updateTripStartedBody(tripID: tripID, body: "From Home"))

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].id, id)
        XCTAssertEqual(store.items[0].body, "From Home")
        XCTAssertEqual(store.items[0].tripID, tripID)
    }

    func testUpdateTripStartedBodyReturnsFalseWhenUnchangedOrMissing() {
        let tripID = UUID()
        store.record(
            kind: .tripStarted,
            title: "Trip started",
            body: "From Home",
            tripID: tripID
        )

        XCTAssertFalse(store.updateTripStartedBody(tripID: tripID, body: "From Home"))
        XCTAssertFalse(store.updateTripStartedBody(tripID: UUID(), body: "From Work"))
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].body, "From Home")
    }
}
