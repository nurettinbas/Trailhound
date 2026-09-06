import XCTest
@testable import Trailhound

final class AppIconSyncTests: XCTestCase {
    func testSkyUsesPrimaryIcon() {
        XCTAssertNil(AppIconSync.alternateIconName(for: .sky))
    }

    func testEveryOtherPaletteHasAUniqueAlternateName() {
        let names = AppIconSync.alternateIconNames
        XCTAssertEqual(names.count, ShellPalette.allCases.count - 1)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertEqual(AppIconSync.alternateIconName(for: .forest), "AppIconForest")
        XCTAssertEqual(AppIconSync.alternateIconName(for: .sunset), "AppIconSunset")
        XCTAssertFalse(names.contains("AppIconSky"))
    }

    func testEveryAlternateHasAnIconComposerBundle() {
        let icons = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Trailhound/AppIcons", isDirectory: true)
        for name in AppIconSync.alternateIconNames {
            let json = icons.appendingPathComponent("\(name).icon/icon.json")
            XCTAssertTrue(FileManager.default.fileExists(atPath: json.path), name)
        }
    }
}
