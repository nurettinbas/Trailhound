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

    func testLightAtmosphereIsSoftenedWithoutWeakeningControls() {
        let sky = ShellPalette.sky.atmosphere(for: .light)
        XCTAssertEqual(sky.top.r, 0.5257, accuracy: 0.000_001)
        XCTAssertEqual(sky.mid.g, 0.6373, accuracy: 0.000_001)
        XCTAssertEqual(sky.bottom.b, 0.8047, accuracy: 0.000_001)
        XCTAssertEqual(sky.tint, ShellRGB(0.23, 0.56, 0.85))
        XCTAssertEqual(sky.chrome, ShellRGB(0.090, 0.294, 0.561))
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
            XCTAssertFalse(
                palette.usesLightChrome(for: .light),
                "\(palette.rawValue) light type is white on the saturated shell"
            )
        }
    }

    func testLightTypeIsWhiteOnEveryPalette() {
        XCTAssertEqual(ShellPalette.sky.shellForeground(for: .light), Color.white)
        XCTAssertEqual(ShellPalette.sand.shellForeground(for: .light), Color.white)
        XCTAssertEqual(ShellPalette.gold.shellForeground(for: .light), Color.white)
        XCTAssertEqual(ShellPalette.sky.shellTint(for: .light), Color.white)
        XCTAssertEqual(ShellPalette.sky.toolbarColorScheme(for: .light), .light)
        XCTAssertEqual(ShellPalette.sky.toolbarColorScheme(for: .dark), .dark)
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

    func testComplementaryInkOpposesWarmAndCoolPalettes() {
        let goldInk = ShellPalette.gold.atmosphere(for: .light).mid.complementaryInk(for: .light)
        XCTAssertGreaterThan(goldInk.b, goldInk.r)
        let skyInk = ShellPalette.sky.atmosphere(for: .light).mid.complementaryInk(for: .light)
        XCTAssertGreaterThan(skyInk.r, skyInk.b)
        XCTAssertNotEqual(goldInk, skyInk)
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

    func testVehicleSliceColorsDifferAcrossStableKeys() {
        let keys = ["puma", "vespa"]
        let puma = StatsChartTheme.sliceColor(
            forStableKey: "puma",
            durationStyle: false,
            domainKeys: keys,
            palette: .sky,
            scheme: .light
        )
        let vespa = StatsChartTheme.sliceColor(
            forStableKey: "vespa",
            durationStyle: false,
            domainKeys: keys,
            palette: .sky,
            scheme: .light
        )
        XCTAssertNotEqual(puma, vespa)
    }

    func testAppTabBarIndexMatchesTabViewOrder() {
        XCTAssertEqual(AppTab.trips.tabBarIndex, 0)
        XCTAssertEqual(AppTab.pairing.tabBarIndex, 1)
        XCTAssertEqual(AppTab.stats.tabBarIndex, 2)
        XCTAssertEqual(AppTab.year.tabBarIndex, 3)
        XCTAssertEqual(AppTab.settings.tabBarIndex, 4)
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

    func testTabBarPagePlateFollowsAtmosphereMid() {
        let pink = TrailhoundTabBarTheme.pagePlateUIColor(palette: .pink, scheme: .light)
        let expected = TrailhoundTabBarTheme.uiColor(ShellPalette.pink.atmosphere(for: .light).mid)
        XCTAssertEqual(pink, expected)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        pink.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertGreaterThan(r, 0.5)
        XCTAssertGreaterThan((r + g + b) / 3, 0.4)
    }

    func testHomeScreenIconFillMatchesAlternateIconRecipes() {
        XCTAssertEqual(
            ShellPalette.sand.homeScreenIconFillRGB(for: .light),
            ShellPalette.sand.atmosphere(for: .light).tint
        )
        XCTAssertEqual(
            ShellPalette.sand.homeScreenIconFillRGB(for: .dark),
            ShellPalette.sand.atmosphere(for: .dark).mid
        )
        XCTAssertEqual(
            ShellPalette.forest.homeScreenIconFillRGB(for: .light),
            ShellRGB(0.16, 0.48, 0.24)
        )
        XCTAssertEqual(
            ShellPalette.forest.homeScreenIconFillRGB(for: .dark),
            ShellRGB(0.07, 0.16, 0.08)
        )
        XCTAssertEqual(
            ShellPalette.sky.homeScreenIconFill(for: .light),
            TrailhoundBrandColors.brandBottom
        )
        XCTAssertGreaterThan(
            ShellPalette.orange.homeScreenIconFillRGB(for: .light).relativeLuminance,
            ShellPalette.orange.homeScreenIconFillRGB(for: .dark).relativeLuminance
        )
    }

    func testTabBarUnselectedIsWhiteInLight() {
        let gold = TrailhoundTabBarTheme.unselectedUIColor(palette: .gold, scheme: .light)
        let sky = TrailhoundTabBarTheme.unselectedUIColor(palette: .sky, scheme: .light)
        XCTAssertEqual(gold, sky)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        sky.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 1, accuracy: 0.01)
        XCTAssertEqual(g, 1, accuracy: 0.01)
        XCTAssertEqual(b, 1, accuracy: 0.01)
        XCTAssertEqual(a, 1, accuracy: 0.01)
        XCTAssertEqual(
            TrailhoundTabBarTheme.unselectedUIColor(palette: .sky, scheme: .dark),
            UIColor.white
        )
    }

    func testTabBarLightSelectedGlyphIsWhite() {
        XCTAssertEqual(
            TrailhoundTabBarTheme.selectedGlyphUIColor(palette: .sky, scheme: .light),
            .white
        )
        XCTAssertEqual(
            TrailhoundTabBarTheme.selectedGlyphUIColor(palette: .lime, scheme: .light),
            .white
        )
        XCTAssertEqual(
            TrailhoundTabBarTheme.selectedGlyphUIColor(palette: .lime, scheme: .dark),
            TrailhoundTabBarTheme.selectedUIColor(palette: .lime, scheme: .dark)
        )
    }

    func testTabBarSelectedBlobGlassIsDarkAtmosphereMid() {
        let coral = TrailhoundTabBarTheme.selectedBlobGlassUIColor(palette: .coral)
        let expected = TrailhoundTabBarTheme.uiColor(ShellPalette.coral.atmosphere(for: .dark).mid)
        XCTAssertEqual(coral, expected)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        coral.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertLessThan((r + g + b) / 3, 0.35)
        XCTAssertNotEqual(
            TrailhoundTabBarTheme.selectedBlobGlassUIColor(palette: .coral),
            UIColor.white
        )
    }

    func testTabBarLightSelectedMatchesDarkVividTint() {
        for palette in ShellPalette.allCases {
            XCTAssertEqual(
                TrailhoundTabBarTheme.selectedUIColor(palette: palette, scheme: .light),
                TrailhoundTabBarTheme.selectedUIColor(palette: palette, scheme: .dark),
                palette.rawValue
            )
        }
        let lime = TrailhoundTabBarTheme.selectedUIColor(palette: .lime, scheme: .light)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        lime.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertGreaterThan(g, r)
        XCTAssertGreaterThan(g, 0.5)
    }

    func testTabBarClearGlassTintMatchesCardFamilyAtLowerOpacity() {
        let pink = TrailhoundTabBarTheme.clearGlassTintUIColor(palette: .pink)
        let expected = TrailhoundTabBarTheme.uiColor(
            GlassContrast.nativeGlassTint(palette: .pink),
            alpha: CGFloat(GlassContrast.tabBarClearGlassTintOpacity)
        )
        XCTAssertEqual(pink, expected)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        pink.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(Double(a), GlassContrast.tabBarClearGlassTintOpacity, accuracy: 0.001)
        XCTAssertGreaterThan(r, b)
        XCTAssertNotEqual(
            TrailhoundTabBarTheme.clearGlassTintUIColor(palette: .pink),
            TrailhoundTabBarTheme.clearGlassTintUIColor(palette: .sky)
        )
    }

    func testRecapTabFillSymbolExists() {
        XCTAssertEqual(TrailhoundTabBarTheme.itemSymbols.count, 5)
        XCTAssertEqual(TrailhoundTabBarTheme.itemSymbols[3].outline, "star")
        XCTAssertEqual(TrailhoundTabBarTheme.itemSymbols[3].fill, "star.fill")
        XCTAssertNotNil(UIImage(systemName: "star.fill"))
        for symbol in TrailhoundTabBarTheme.itemSymbols {
            XCTAssertNotNil(UIImage(systemName: symbol.outline), symbol.outline)
            XCTAssertNotNil(UIImage(systemName: symbol.fill), symbol.fill)
        }
    }
}
