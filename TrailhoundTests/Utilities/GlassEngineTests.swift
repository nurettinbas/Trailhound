import SwiftUI
import XCTest
@testable import Trailhound

final class GlassEngineTests: XCTestCase {
    func testReduceTransparencyAlwaysSolid() {
        XCTAssertEqual(
            GlassEngineResolver.resolve(
                scheme: .light,
                reduceTransparency: true,
                frozen: false,
                allowsNative: true
            ),
            .solid
        )
        XCTAssertEqual(
            GlassEngineResolver.resolve(
                scheme: .dark,
                reduceTransparency: true,
                frozen: false
            ),
            .solid
        )
    }

    func testFrozenAlwaysSolid() {
        XCTAssertEqual(
            GlassEngineResolver.resolve(
                scheme: .light,
                reduceTransparency: false,
                frozen: true
            ),
            .solid
        )
    }

    func testDarkNeverUsesNative() {
        XCTAssertEqual(
            GlassEngineResolver.resolve(
                scheme: .dark,
                reduceTransparency: false,
                frozen: false,
                allowsNative: true
            ),
            .material
        )
    }

    func testListRowsDisallowNative() {
        let engine = GlassEngineResolver.resolve(
            scheme: .light,
            reduceTransparency: false,
            frozen: false,
            allowsNative: false
        )
        XCTAssertEqual(engine, .material)
    }

    func testLightAutoUsesNativeWhenAvailable() {
        let engine = GlassEngineResolver.resolve(
            scheme: .light,
            reduceTransparency: false,
            frozen: false,
            allowsNative: true
        )
        if GlassEngineResolver.isNativeAvailable {
            XCTAssertEqual(engine, .native)
        } else {
            XCTAssertEqual(engine, .material)
        }
    }

    func testHostBudgetConstant() {
        XCTAssertEqual(GlassHostBudget.maxNativeHostsPerScreen, 8)
    }
}
