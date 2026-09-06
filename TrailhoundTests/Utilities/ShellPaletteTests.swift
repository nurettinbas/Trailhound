import SwiftUI
import XCTest
@testable import Trailhound

final class ShellPaletteTests: XCTestCase {
    func testTwentyCuratedHues() {
        XCTAssertEqual(ShellPalette.allCases.count, 20)
        XCTAssertEqual(ShellPalette.default, .sky)
        XCTAssertEqual(ShellPalette.storageKey, "shellPalette")
    }

    func testSkyLightMatchesBrandAtmosphere() {
        let sky = ShellPalette.sky.atmosphere(for: .light)
        XCTAssertEqual(sky.top.color, TrailhoundBrandColors.atmosphereTop)
        XCTAssertEqual(sky.mid.color, TrailhoundBrandColors.atmosphereMid)
        XCTAssertEqual(sky.bottom.color, TrailhoundBrandColors.atmosphereBottom)
        XCTAssertEqual(sky.tint.color, TrailhoundBrandColors.brandBottom)
        XCTAssertEqual(sky.chrome.color, LightGlassPalette.controlTint)
    }

    func testSkyDarkKeepsLegacyNavy() {
        let sky = ShellPalette.sky.atmosphere(for: .dark)
        XCTAssertEqual(sky.top, ShellRGB(0.03, 0.07, 0.14))
        XCTAssertEqual(sky.mid, ShellRGB(0.07, 0.13, 0.24))
        XCTAssertEqual(sky.bottom, ShellRGB(0.04, 0.10, 0.20))
    }

    func testEveryPaletteResolvesBothSchemes() {
        for palette in ShellPalette.allCases {
            let light = palette.atmosphere(for: .light)
            let dark = palette.atmosphere(for: .dark)
            XCTAssertEqual(light.gradientColors.count, 3)
            XCTAssertEqual(dark.gradientColors.count, 3)
            XCTAssertLessThan(
                dark.mid.relativeLuminance,
                light.mid.relativeLuminance,
                "\(palette.rawValue) dark mid should be darker than light mid"
            )
            XCTAssertLessThan(dark.mid.relativeLuminance, 0.25, palette.rawValue)
        }
    }

    func testPaleLightHuesUseLightChrome() {
        XCTAssertTrue(ShellPalette.gold.usesLightChrome(for: .light))
        XCTAssertTrue(ShellPalette.lime.usesLightChrome(for: .light))
        XCTAssertTrue(ShellPalette.sand.usesLightChrome(for: .light))
        XCTAssertFalse(ShellPalette.sky.usesLightChrome(for: .light))
        XCTAssertFalse(ShellPalette.orange.usesLightChrome(for: .light))
        XCTAssertFalse(ShellPalette.gold.usesLightChrome(for: .dark))
    }

    func testStoredFallsBackToSky() {
        let suiteName = "test.trailhound.shellPalette.stored.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Could not create test defaults")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(ShellPalette.stored(in: defaults), .sky)
        defaults.set("not-a-color", forKey: ShellPalette.storageKey)
        XCTAssertEqual(ShellPalette.stored(in: defaults), .sky)
        defaults.set("ember", forKey: ShellPalette.storageKey)
        XCTAssertEqual(ShellPalette.stored(in: defaults), .ember)
    }

    func testOrangeLightIsNotNavy() {
        let orange = ShellPalette.orange.atmosphere(for: .light)
        XCTAssertNotEqual(orange.mid.color, TrailhoundBrandColors.atmosphereMid)
        XCTAssertGreaterThan(orange.mid.r, orange.mid.b)
    }

    func testDonutSliceLeadColorFollowsPaletteTint() {
        let forest = StatsChartTheme.sliceColor(
            forStableKey: "a",
            durationStyle: false,
            domainKeys: ["a"],
            palette: .forest,
            scheme: .light
        )
        let sky = StatsChartTheme.sliceColor(
            forStableKey: "a",
            durationStyle: false,
            domainKeys: ["a"],
            palette: .sky,
            scheme: .light
        )
        XCTAssertEqual(forest, ShellPalette.forest.tintColor(for: .light))
        XCTAssertEqual(sky, ShellPalette.sky.tintColor(for: .light))
        XCTAssertNotEqual(forest, sky)
    }

    func testTabBarSelectionFollowsPaletteTint() {
        let forest = TrailhoundTabBarTheme.selectedUIColor(palette: .forest, scheme: .light)
        let sunset = TrailhoundTabBarTheme.selectedUIColor(palette: .sunset, scheme: .light)
        let sky = TrailhoundTabBarTheme.selectedUIColor(palette: .sky, scheme: .light)
        XCTAssertNotEqual(forest, sunset)
        XCTAssertNotEqual(forest, sky)

        var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
        forest.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
        XCTAssertGreaterThan(fg, fr)
        XCTAssertGreaterThan(fg, fb)

        var sr: CGFloat = 0, sg: CGFloat = 0, sb: CGFloat = 0, sa: CGFloat = 0
        sunset.getRed(&sr, green: &sg, blue: &sb, alpha: &sa)
        XCTAssertGreaterThan(sr, sb)
    }

    func testLightShellTintIsChromeOnGlassWells() {
        XCTAssertEqual(
            ShellPalette.sky.shellTint(for: .light),
            ShellPalette.sky.chromeColor(for: .light)
        )
        XCTAssertEqual(
            ShellPalette.pink.shellTint(for: .light),
            ShellPalette.pink.chromeColor(for: .light)
        )
        XCTAssertEqual(ShellPalette.sky.toolbarColorScheme(for: .light), .light)
        XCTAssertEqual(ShellPalette.pink.toolbarColorScheme(for: .light), .light)
        XCTAssertEqual(ShellPalette.sky.toolbarColorScheme(for: .dark), .dark)
    }

    func testTabBarPagePlateFollowsAtmosphereMid() {
        let pink = TrailhoundTabBarTheme.pagePlateUIColor(palette: .pink, scheme: .light)
        let expected = TrailhoundTabBarTheme.uiColor(ShellPalette.pink.atmosphere(for: .light).mid)
        XCTAssertEqual(pink, expected)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        pink.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertGreaterThan(r, 0.5)
        XCTAssertGreaterThan((r + g + b) / 3, 0.4)
    }

    func testTabBarUnselectedUsesDarkInkInLight() {
        let gold = TrailhoundTabBarTheme.unselectedUIColor(palette: .gold, scheme: .light)
        let sky = TrailhoundTabBarTheme.unselectedUIColor(palette: .sky, scheme: .light)
        XCTAssertEqual(gold, sky)
        XCTAssertEqual(
            TrailhoundTabBarTheme.unselectedUIColor(palette: .sky, scheme: .dark),
            UIColor.secondaryLabel
        )
    }
}
