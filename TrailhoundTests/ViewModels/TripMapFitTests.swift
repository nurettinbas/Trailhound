import CoreLocation
import XCTest
@testable import Trailhound

@MainActor
final class TripMapFitTests: XCTestCase {
    func testPanelInsetZoomsOutMoreThanFullscreen() {
        // North–south route so latitude is the limiting axis once the panel shrinks the visible band.
        let coordinates = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            CLLocationCoordinate2D(latitude: 41.02, longitude: 29.002)
        ]

        let fullscreen = TripDetailViewModel.regionFitting(
            coordinates: coordinates,
            fit: .fullscreen
        )
        let withPanel = TripDetailViewModel.regionFitting(
            coordinates: coordinates,
            fit: .detailWithPanel
        )

        XCTAssertNotNil(fullscreen)
        XCTAssertNotNil(withPanel)
        XCTAssertGreaterThan(withPanel!.span.latitudeDelta, fullscreen!.span.latitudeDelta)
    }

    func testOverlayPanelFitShiftsRouteIntoUpperVisibleBand() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            CLLocationCoordinate2D(latitude: 41.01, longitude: 29.01)
        ]
        let midLat = 41.005
        let fit = TripDetailViewModel.MapFitContext.detailOverlay(
            panelFraction: 0.52,
            aspectWidthOverHeight: 0.46
        )
        let region = TripDetailViewModel.regionFitting(coordinates: coordinates, fit: fit)

        XCTAssertNotNil(region)
        // Center moves south so the route sits above the overlay panel (north = top of map).
        XCTAssertLessThan(region!.center.latitude, midLat)
        XCTAssertGreaterThan(fit.bottom, 0.52)
    }

    func testTallPanelStillKeepsUsableVisibleBand() {
        let fit = TripDetailViewModel.MapFitContext.detailOverlay(
            panelFraction: 0.78,
            aspectWidthOverHeight: 0.46
        )
        let visible = 1 - fit.top - fit.bottom
        XCTAssertGreaterThanOrEqual(visible, 0.16)

        let coordinates = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            CLLocationCoordinate2D(latitude: 41.02, longitude: 29.01)
        ]
        let region = TripDetailViewModel.regionFitting(coordinates: coordinates, fit: fit)
        XCTAssertNotNil(region)

        let balanced = TripDetailViewModel.regionFitting(
            coordinates: coordinates,
            fit: .detailOverlay(panelFraction: 0.52, aspectWidthOverHeight: 0.46)
        )
        XCTAssertNotNil(balanced)
        // Taller panel must zoom out more so the route still fits the thin strip.
        XCTAssertGreaterThan(region!.span.latitudeDelta, balanced!.span.latitudeDelta)
    }

    func testOverlayBottomIncludesLegendClearance() {
        let fit = TripDetailViewModel.MapFitContext.detailOverlay(
            panelFraction: 0.52,
            aspectWidthOverHeight: 0.46,
            topChromeFraction: 0.10
        )
        XCTAssertGreaterThanOrEqual(fit.bottom, 0.52 + 0.08)
    }

    func testAspectMatchedSpansAreNotSquareOnPortrait() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            CLLocationCoordinate2D(latitude: 41.01, longitude: 29.01)
        ]
        let region = TripDetailViewModel.regionFitting(
            coordinates: coordinates,
            fit: .detailOverlay(panelFraction: 0.52, aspectWidthOverHeight: 0.46)
        )
        XCTAssertNotNil(region)
        XCTAssertNotEqual(region!.span.latitudeDelta, region!.span.longitudeDelta, accuracy: 0.0001)
        XCTAssertLessThan(region!.span.longitudeDelta, region!.span.latitudeDelta)
    }

    func testShortRouteGetsReadableMinimumZoom() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            CLLocationCoordinate2D(latitude: 41.0004, longitude: 29.0004)
        ]

        let region = TripDetailViewModel.regionFitting(
            coordinates: coordinates,
            fit: .detailWithPanel
        )

        XCTAssertNotNil(region)
        XCTAssertGreaterThanOrEqual(region!.span.latitudeDelta, 0.0016)
    }

    func testLongRouteUsesSmallerRelativeMargin() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            CLLocationCoordinate2D(latitude: 41.08, longitude: 29.12)
        ]

        let short = TripDetailViewModel.regionFitting(
            coordinates: [
                CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
                CLLocationCoordinate2D(latitude: 41.002, longitude: 29.002)
            ],
            fit: .detailWithPanel
        )
        let long = TripDetailViewModel.regionFitting(
            coordinates: coordinates,
            fit: .detailWithPanel
        )

        XCTAssertNotNil(short)
        XCTAssertNotNil(long)
        let shortMarginRatio = short!.span.latitudeDelta / 0.002
        let longMarginRatio = long!.span.latitudeDelta / 0.08
        XCTAssertLessThan(longMarginRatio, shortMarginRatio)
    }

    func testPixelPaddingCentersRouteInUsableBand() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 41.0, longitude: 29.0),
            CLLocationCoordinate2D(latitude: 41.02, longitude: 29.01)
        ]
        let mapSize = CGSize(width: 390, height: 844)
        let panelHeight: CGFloat = 844 * 0.52
        let padding = UIEdgeInsets(top: 96, left: 24, bottom: panelHeight + 56, right: 24)
        let region = TripDetailViewModel.regionFitting(
            coordinates: coordinates,
            mapSize: mapSize,
            edgePadding: padding
        )

        XCTAssertNotNil(region)
        let midLat = 41.01
        // Route sits in the upper visible band → camera center shifts south.
        XCTAssertLessThan(region!.center.latitude, midLat)

        let tallPadding = UIEdgeInsets(top: 96, left: 24, bottom: 844 * 0.78 + 56, right: 24)
        let tall = TripDetailViewModel.regionFitting(
            coordinates: coordinates,
            mapSize: mapSize,
            edgePadding: tallPadding
        )
        XCTAssertNotNil(tall)
        XCTAssertGreaterThan(tall!.span.latitudeDelta, region!.span.latitudeDelta)
    }

    func testExpandedPaddingCentersRouteAboveTabBar() {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 38.36, longitude: 27.14),
            CLLocationCoordinate2D(latitude: 38.42, longitude: 27.16)
        ]
        let mapSize = CGSize(width: 390, height: 844)
        let top: CGFloat = 96 + 52
        let bottom: CGFloat = 83 + 36
        let padding = UIEdgeInsets(top: top, left: 24, bottom: bottom, right: 24)
        let region = TripDetailViewModel.regionFitting(
            coordinates: coordinates,
            mapSize: mapSize,
            edgePadding: padding
        )

        XCTAssertNotNil(region)
        let midLat = 38.39
        let midLon = 27.15
        // More top chrome than bottom → camera center sits slightly south of the route mid.
        XCTAssertLessThan(region!.center.latitude, midLat)
        XCTAssertEqual(region!.center.longitude, midLon, accuracy: 0.004)
        // Must stay wider than the raw route so start/end are not clipped by the tab bar.
        XCTAssertGreaterThan(region!.span.latitudeDelta, 0.06)
    }
}
