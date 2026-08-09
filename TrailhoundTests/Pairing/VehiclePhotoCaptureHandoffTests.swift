import XCTest
@testable import Trailhound

final class VehiclePhotoCaptureHandoffTests: XCTestCase {
    func testLibraryMapsToGalleryOverlay() {
        XCTAssertEqual(
            VehiclePhotoCaptureHandoff.pendingMode(after: .library),
            .gallery
        )
    }

    func testCameraMapsToCameraOverlay() {
        XCTAssertEqual(
            VehiclePhotoCaptureHandoff.pendingMode(after: .camera),
            .camera
        )
    }

    func testCancelClearsPendingMode() {
        XCTAssertNil(VehiclePhotoCaptureHandoff.pendingMode(after: .cancel))
    }

    func testSheetRouteIDsAreStableAndDistinct() {
        XCTAssertEqual(VehiclePhotoSheetRoute.source.id, "source")
        XCTAssertEqual(VehiclePhotoSheetRoute.capture(.gallery).id, "capture-gallery")
        XCTAssertEqual(VehiclePhotoSheetRoute.capture(.camera).id, "capture-camera")
        XCTAssertNotEqual(
            VehiclePhotoSheetRoute.capture(.gallery).id,
            VehiclePhotoSheetRoute.capture(.camera).id
        )
    }
}
