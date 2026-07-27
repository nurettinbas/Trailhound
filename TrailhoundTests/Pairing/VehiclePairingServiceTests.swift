import SwiftData
import XCTest
@testable import Trailhound

@MainActor
final class VehiclePairingServiceTests: XCTestCase {
    func testSetDefaultVehicleMarksSingleDefault() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: TrailhoundSchemaV7.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let first = VehicleProfile(name: "First")
        let second = VehicleProfile(name: "Second")
        context.insert(first)
        context.insert(second)
        first.isDefault = true

        VehiclePairingService.setDefaultVehicle(second, in: context)

        XCTAssertFalse(first.isDefault)
        XCTAssertTrue(second.isDefault)
    }

    func testDeleteVehiclePromotesNextDefault() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: TrailhoundSchemaV7.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let first = VehicleProfile(name: "First")
        let second = VehicleProfile(name: "Second")
        context.insert(first)
        context.insert(second)
        first.isDefault = true

        VehiclePairingService.deleteVehicle(first, in: context)

        let remaining = try context.fetch(FetchDescriptor<VehicleProfile>())
        XCTAssertEqual(remaining.count, 1)
        XCTAssertTrue(remaining.first?.isDefault == true)
        XCTAssertEqual(remaining.first?.name, "Second")
    }

    func testMigrateLegacyBluetoothAutoStartClearsVehicleBindings() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: TrailhoundSchemaV7.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let vehicle = VehicleProfile(
            name: "Ford Puma",
            autoStartEnabled: true,
            pairedRouteUID: "legacy-uid",
            pairedRouteName: "Ford Puma"
        )
        context.insert(vehicle)
        try context.save()

        VehiclePairingService.migrateLegacyBluetoothAutoStart(in: context)

        XCTAssertFalse(vehicle.autoStartEnabled)
        XCTAssertNil(vehicle.pairedRouteUID)
        XCTAssertNil(vehicle.pairedRouteName)
    }
}

@MainActor
final class VehicleResolverTests: XCTestCase {
    func testResolvePrefersRecordingVehicleIDOverDefault() throws {
        let container = try ModelContainer(
            for: Schema(versionedSchema: TrailhoundSchemaV7.self),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let defaults = UserDefaults(suiteName: "test.trailhound.vehicle.\(UUID().uuidString)")!
        let settings = AppSettings(userDefaults: defaults)

        let defaultVehicle = VehicleProfile(name: "Default", isDefault: true)
        let other = VehicleProfile(name: "Other")
        context.insert(defaultVehicle)
        context.insert(other)
        settings.recordingVehicleID = other.id

        let resolved = VehicleResolver.resolveActiveVehicle(in: context, settings: settings)
        XCTAssertEqual(resolved?.id, other.id)
    }
}
