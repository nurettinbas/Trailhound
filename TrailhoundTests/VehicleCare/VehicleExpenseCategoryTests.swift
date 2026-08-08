import XCTest
@testable import Trailhound

final class VehicleExpenseCategoryTests: XCTestCase {
    func testPickerHasSevenCases() {
        XCTAssertEqual(VehicleExpenseCategory.allCases.count, 7)
        XCTAssertEqual(
            VehicleExpenseCategory.allCases.map(\.rawValue),
            ["fuel", "casco", "service", "inspection", "repair", "accessory", "other"]
        )
    }

    func testLegacyRawValuesResolve() {
        XCTAssertEqual(VehicleExpenseCategory.resolved(fromRaw: "parts"), .accessory)
        XCTAssertEqual(VehicleExpenseCategory.resolved(fromRaw: "insurance"), .other)
        XCTAssertEqual(VehicleExpenseCategory.resolved(fromRaw: "tax"), .other)
        XCTAssertEqual(VehicleExpenseCategory.resolved(fromRaw: "parking"), .other)
        XCTAssertEqual(VehicleExpenseCategory.resolved(fromRaw: "fuel"), .fuel)
        XCTAssertEqual(VehicleExpenseCategory.resolved(fromRaw: "repair"), .repair)
        XCTAssertEqual(VehicleExpenseCategory.resolved(fromRaw: "unknown"), .other)
    }

    func testCostBuckets() {
        XCTAssertEqual(VehicleExpenseCategory.fuel.costBucket, .fuel)
        XCTAssertEqual(VehicleExpenseCategory.service.costBucket, .service)
        XCTAssertEqual(VehicleExpenseCategory.repair.costBucket, .service)
        XCTAssertEqual(VehicleExpenseCategory.casco.costBucket, .casco)
        XCTAssertEqual(VehicleExpenseCategory.accessory.costBucket, .other)
        XCTAssertEqual(VehicleExpenseCategory.inspection.costBucket, .other)
    }

    func testSuggestedForScheduleKind() {
        XCTAssertEqual(VehicleExpenseCategory.suggested(for: .service), .service)
        XCTAssertEqual(VehicleExpenseCategory.suggested(for: .inspection), .inspection)
        XCTAssertEqual(VehicleExpenseCategory.suggested(for: .casco), .casco)
        XCTAssertEqual(VehicleExpenseCategory.suggested(for: .trafficInsurance), .other)
    }
}
