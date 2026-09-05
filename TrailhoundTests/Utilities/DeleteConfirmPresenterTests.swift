import XCTest
@testable import Trailhound

@MainActor
final class DeleteConfirmPresenterTests: XCTestCase {
    override func tearDown() {
        DeleteConfirmPresenter.shared.cancel()
        super.tearDown()
    }

    func testCancelDoesNotPerform() {
        var didRun = false
        DeleteConfirmPresenter.shared.confirm(.generic) {
            didRun = true
        }

        XCTAssertNotNil(DeleteConfirmPresenter.shared.request)
        DeleteConfirmPresenter.shared.cancel()
        XCTAssertFalse(didRun)
        XCTAssertNil(DeleteConfirmPresenter.shared.request)
    }

    func testConfirmPerformsAndClearsRequest() {
        var didRun = false
        DeleteConfirmPresenter.shared.confirm(.generic) {
            didRun = true
        }

        DeleteConfirmPresenter.shared.performConfirm()
        XCTAssertTrue(didRun)
        XCTAssertNil(DeleteConfirmPresenter.shared.request)
    }

    func testNewRequestReplacesOpenOneWithoutRunningIt() {
        var firstRan = false
        var secondRan = false
        DeleteConfirmPresenter.shared.confirm(.generic) {
            firstRan = true
        }
        DeleteConfirmPresenter.shared.confirm(.category) {
            secondRan = true
        }

        XCTAssertEqual(
            DeleteConfirmPresenter.shared.request?.title,
            DeleteConfirmKind.category.title
        )
        DeleteConfirmPresenter.shared.performConfirm()
        XCTAssertFalse(firstRan)
        XCTAssertTrue(secondRan)
    }

    func testKindCopyIsNonEmpty() {
        let kinds: [DeleteConfirmKind] = [
            .generic,
            .vehicle(isActivePaired: false),
            .vehicle(isActivePaired: true),
            .journalRemove,
            .category,
            .installmentPlan(count: 6),
            .vehiclePhoto,
            .notificationsAll
        ]

        for kind in kinds {
            XCTAssertFalse(kind.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(kind)")
            XCTAssertFalse(kind.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(kind)")
            XCTAssertFalse(kind.confirmTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, "\(kind)")
        }
    }

    func testVehicleKindUsesActiveCopyWhenPaired() {
        XCTAssertEqual(
            DeleteConfirmKind.vehicle(isActivePaired: false).message,
            L10n.pairingTabDeleteVehicleMessage
        )
        XCTAssertEqual(
            DeleteConfirmKind.vehicle(isActivePaired: true).message,
            L10n.pairingTabDeleteVehicleMessageActive
        )
        XCTAssertNotEqual(
            DeleteConfirmKind.vehicle(isActivePaired: false).message,
            DeleteConfirmKind.vehicle(isActivePaired: true).message
        )
    }

    func testJournalRemoveCopyDiffersFromGeneric() {
        XCTAssertNotEqual(DeleteConfirmKind.journalRemove.message, DeleteConfirmKind.generic.message)
        XCTAssertEqual(DeleteConfirmKind.journalRemove.confirmTitle, L10n.journalRemove)
    }
}
