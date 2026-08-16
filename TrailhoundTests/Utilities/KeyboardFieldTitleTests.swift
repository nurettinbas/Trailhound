import XCTest
@testable import Trailhound

/// Accessory bar labels come from these focus enums — catch empty / wrong L10n regressions.
final class KeyboardFieldTitleTests: XCTestCase {
    func testSettingsFocusedFieldTitlesMatchL10n() {
        XCTAssertEqual(SettingsFocusedField.newCategory.title, L10n.categoryNewPlaceholder)
        XCTAssertEqual(SettingsFocusedField.fuelPrice.title, L10n.settingsFuelPrice)
        XCTAssertEqual(SettingsFocusedField.privacyRadius.title, L10n.settingsPrivacyRadius)

        for field in [SettingsFocusedField.newCategory, .fuelPrice, .privacyRadius] {
            XCTAssertFalse(field.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    func testPairingVehicleFocusedFieldTitles() {
        XCTAssertEqual(
            PairingVehicleFocusedField.name.title(consumptionLabel: "L/100 km"),
            L10n.pairingTabVehicleName
        )
        XCTAssertEqual(
            PairingVehicleFocusedField.consumption.title(consumptionLabel: "kWh/100 km"),
            "kWh/100 km"
        )
        XCTAssertEqual(
            PairingVehicleFocusedField.chargePrice.title(consumptionLabel: "ignored"),
            L10n.pairingTabChargePrice
        )

        for field: PairingVehicleFocusedField in [.name, .consumption, .chargePrice] {
            XCTAssertFalse(
                field.title(consumptionLabel: "x")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
            )
        }
    }
}
