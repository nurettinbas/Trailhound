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
                override: .native,
                allowsNative: true
            ),
            .solid
        )
        XCTAssertEqual(
            GlassEngineResolver.resolve(
                scheme: .dark,
                reduceTransparency: true,
                frozen: false,
                override: .auto
            ),
            .solid
        )
    }

    func testFrozenAlwaysSolid() {
        XCTAssertEqual(
            GlassEngineResolver.resolve(
                scheme: .light,
                reduceTransparency: false,
                frozen: true,
                override: .auto
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
                override: .native,
                allowsNative: true
            ),
            .material
        )
    }

    func testLightMaterialOverrideWins() {
        XCTAssertEqual(
            GlassEngineResolver.resolve(
                scheme: .light,
                reduceTransparency: false,
                frozen: false,
                override: .material,
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
            override: .auto,
            allowsNative: false
        )
        XCTAssertEqual(engine, .material)
    }

    func testLightAutoUsesNativeWhenAvailable() {
        let engine = GlassEngineResolver.resolve(
            scheme: .light,
            reduceTransparency: false,
            frozen: false,
            override: .auto,
            allowsNative: true
        )
        if GlassEngineResolver.isNativeAvailable {
            XCTAssertEqual(engine, .native)
        } else {
            XCTAssertEqual(engine, .material)
        }
    }
}
