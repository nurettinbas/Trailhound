import XCTest
@testable import Trailhound

final class TravelJournalMapFitTests: XCTestCase {
    private let mapSize = CGSize(width: 500, height: 360)

    func testSplitIgnoresBottomSheet() {
        let split = TravelJournalMapFit.padding(
            style: .split,
            mapExpanded: false,
            mapSize: mapSize,
            topChrome: 44,
            bottomChrome: 200,
            sheetHeight: 400,
            trailingCover: 59,
            homeIndicator: 21
        )
        let sheet = TravelJournalMapFit.padding(
            style: .overlay,
            mapExpanded: false,
            mapSize: mapSize,
            topChrome: 44,
            bottomChrome: 200,
            sheetHeight: 400,
            trailingCover: 59,
            homeIndicator: 21
        )

        XCTAssertEqual(split.bottom, 21, accuracy: 0.5)
        XCTAssertGreaterThan(sheet.bottom, 400)
        XCTAssertEqual(split.right, split.left + 59, accuracy: 0.5)
    }

    func testExpandedSplitDoesNotKeepTheSheetInset() {
        let expanded = TravelJournalMapFit.padding(
            style: .split,
            mapExpanded: true,
            mapSize: mapSize,
            topChrome: 44,
            bottomChrome: 90,
            sheetHeight: 400,
            trailingCover: 59,
            homeIndicator: 21
        )
        XCTAssertLessThan(expanded.bottom, 200)
        XCTAssertEqual(expanded.left, expanded.right, accuracy: 0.5)
    }
}
