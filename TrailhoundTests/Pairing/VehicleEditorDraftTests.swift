import SwiftData
import XCTest
@testable import Trailhound

@MainActor
final class VehicleEditorDraftTests: XCTestCase {
    func testInitFromVehicleCopiesFields() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let vehicle = VehicleProfile(
            name: "Roadster",
            fuelType: .electric,
            consumption: 18.5,
            chargePricePerKWh: 9.2,
            isDefault: true,
            iconName: VehicleIconOption.electric.rawValue
        )
        context.insert(vehicle)

        let draft = VehicleEditorDraft(from: vehicle)

        XCTAssertEqual(draft.name, "Roadster")
        XCTAssertEqual(draft.fuelType, .electric)
        XCTAssertEqual(draft.consumption, 18.5)
        XCTAssertEqual(draft.chargePricePerKWh, 9.2)
        XCTAssertEqual(draft.iconName, VehicleIconOption.electric.rawValue)
        XCTAssertTrue(draft.wantsDefault)
    }

    func testApplyWritesModelWithoutChangingID() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let vehicle = VehicleProfile(name: "Before", fuelType: .petrol, consumption: 7.0)
        context.insert(vehicle)
        try context.save()
        let originalID = vehicle.id

        var draft = VehicleEditorDraft(from: vehicle)
        draft.name = "After"
        draft.fuelType = .diesel
        draft.consumption = 6.2
        draft.iconName = VehicleIconOption.suv.rawValue

        let defaults = UserDefaults(suiteName: "test.trailhound.draft.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)

        try draft.apply(to: vehicle, allVehicles: [vehicle], in: context, settings: settings)

        XCTAssertEqual(vehicle.id, originalID)
        XCTAssertEqual(vehicle.name, "After")
        XCTAssertEqual(vehicle.fuelType, .diesel)
        XCTAssertEqual(vehicle.consumption, 6.2)
        XCTAssertEqual(vehicle.iconName, VehicleIconOption.suv.rawValue)
    }

    func testApplyDefaultVehicleCallsPairingServiceBehavior() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let first = VehicleProfile(name: "First")
        let second = VehicleProfile(name: "Second")
        context.insert(first)
        context.insert(second)
        first.isDefault = true
        try context.save()

        let defaults = UserDefaults(suiteName: "test.trailhound.draft.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)

        var draft = VehicleEditorDraft(from: second)
        draft.wantsDefault = true
        try draft.apply(to: second, allVehicles: [first, second], in: context, settings: settings)

        XCTAssertFalse(first.isDefault)
        XCTAssertTrue(second.isDefault)
        XCTAssertEqual(settings.recordingVehicleID, second.id)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: TrailhoundSchemaV7.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
