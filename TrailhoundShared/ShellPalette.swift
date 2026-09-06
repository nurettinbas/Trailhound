import SwiftUI

public struct ShellRGB: Sendable, Equatable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public var color: Color {
        Color(red: r, green: g, blue: b)
    }

    public var relativeLuminance: Double {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}

public struct ShellAtmosphere: Sendable, Equatable {
    public var top: ShellRGB
    public var mid: ShellRGB
    public var bottom: ShellRGB
    /// Glass brand overlay, dark selected chips, widget accent.
    public var tint: ShellRGB
    /// Light-mode toggle / segmented / selected-chip text.
    public var chrome: ShellRGB
    public var glow: ShellRGB

    public var gradientColors: [Color] {
        [top.color, mid.color, bottom.color]
    }
}

/// Curated shell hues. One selection; Light and Dark resolve different shade families.
public enum ShellPalette: String, CaseIterable, Identifiable, Sendable {
    case sky
    case ocean
    case teal
    case mint
    case forest
    case lime
    case gold
    case sunset
    case orange
    case coral
    case rose
    case pink
    case magenta
    case purple
    case violet
    case indigo
    case slate
    case graphite
    case sand
    case ember

    public static let `default` = ShellPalette.sky
    public static let storageKey = "shellPalette"
    /// Mid-luminance above this uses dark text on the light shell.
    public static let lightChromeLuminanceThreshold = 0.68

    public var id: String { rawValue }

    public static func stored(in defaults: UserDefaults = RecordingControlBridge.sharedDefaults()) -> ShellPalette {
        guard let raw = defaults.string(forKey: storageKey),
              let palette = ShellPalette(rawValue: raw) else {
            return .sky
        }
        return palette
    }

    public func atmosphere(for scheme: ColorScheme) -> ShellAtmosphere {
        scheme == .dark ? Self.darkRecipes[self]! : Self.lightRecipes[self]!
    }

    public func tintColor(for scheme: ColorScheme) -> Color {
        atmosphere(for: scheme).tint.color
    }

    public func chromeColor(for scheme: ColorScheme) -> Color {
        atmosphere(for: scheme).chrome.color
    }

    public func glowColor(for scheme: ColorScheme) -> Color {
        atmosphere(for: scheme).glow.color
    }

    public func gradientColors(for scheme: ColorScheme) -> [Color] {
        atmosphere(for: scheme).gradientColors
    }

    /// Pale light atmospheres (gold / lime / sand) need dark type instead of white.
    public func usesLightChrome(for scheme: ColorScheme) -> Bool {
        guard scheme == .light else { return false }
        return atmosphere(for: .light).mid.relativeLuminance > Self.lightChromeLuminanceThreshold
    }

    public func shellForeground(for scheme: ColorScheme) -> Color {
        if scheme == .dark { return Color.primary }
        return usesLightChrome(for: .light) ? Color.primary : Color.white
    }

    public func shellTint(for scheme: ColorScheme) -> Color {
        if scheme == .dark { return tintColor(for: .dark) }
        // iOS 26 nav/tab wells are light glass. White glyphs vanish on them.
        return chromeColor(for: .light)
    }

    public func toolbarColorScheme(for scheme: ColorScheme) -> ColorScheme {
        if scheme == .dark { return .dark }
        return .light
    }
}

private extension ShellPalette {
    static func atm(
        _ top: ShellRGB,
        _ mid: ShellRGB,
        _ bottom: ShellRGB,
        tint: ShellRGB,
        chrome: ShellRGB,
        glow: ShellRGB
    ) -> ShellAtmosphere {
        ShellAtmosphere(top: top, mid: mid, bottom: bottom, tint: tint, chrome: chrome, glow: glow)
    }

    static let lightRecipes: [ShellPalette: ShellAtmosphere] = [
        .sky: atm(
            ShellRGB(0.49, 0.74, 0.96),
            ShellRGB(0.31, 0.61, 0.90),
            ShellRGB(0.18, 0.45, 0.79),
            tint: ShellRGB(0.23, 0.56, 0.85),
            chrome: ShellRGB(0.090, 0.294, 0.561),
            glow: ShellRGB(0.45, 0.88, 0.98)
        ),
        .ocean: atm(
            ShellRGB(0.40, 0.78, 0.92),
            ShellRGB(0.22, 0.62, 0.82),
            ShellRGB(0.10, 0.42, 0.70),
            tint: ShellRGB(0.12, 0.52, 0.72),
            chrome: ShellRGB(0.06, 0.32, 0.48),
            glow: ShellRGB(0.40, 0.90, 0.96)
        ),
        .teal: atm(
            ShellRGB(0.42, 0.82, 0.82),
            ShellRGB(0.22, 0.64, 0.66),
            ShellRGB(0.10, 0.44, 0.50),
            tint: ShellRGB(0.10, 0.52, 0.54),
            chrome: ShellRGB(0.05, 0.32, 0.34),
            glow: ShellRGB(0.45, 0.92, 0.90)
        ),
        .mint: atm(
            ShellRGB(0.62, 0.90, 0.82),
            ShellRGB(0.38, 0.76, 0.64),
            ShellRGB(0.20, 0.56, 0.46),
            tint: ShellRGB(0.16, 0.58, 0.46),
            chrome: ShellRGB(0.08, 0.36, 0.28),
            glow: ShellRGB(0.70, 0.96, 0.88)
        ),
        .forest: atm(
            ShellRGB(0.48, 0.78, 0.52),
            ShellRGB(0.28, 0.58, 0.34),
            ShellRGB(0.14, 0.40, 0.22),
            tint: ShellRGB(0.16, 0.48, 0.24),
            chrome: ShellRGB(0.08, 0.30, 0.14),
            glow: ShellRGB(0.55, 0.90, 0.60)
        ),
        .lime: atm(
            ShellRGB(0.78, 0.90, 0.42),
            ShellRGB(0.62, 0.78, 0.22),
            ShellRGB(0.42, 0.58, 0.10),
            tint: ShellRGB(0.48, 0.62, 0.10),
            chrome: ShellRGB(0.28, 0.38, 0.04),
            glow: ShellRGB(0.88, 0.96, 0.50)
        ),
        .gold: atm(
            ShellRGB(0.96, 0.84, 0.42),
            ShellRGB(0.90, 0.70, 0.22),
            ShellRGB(0.78, 0.52, 0.10),
            tint: ShellRGB(0.82, 0.56, 0.08),
            chrome: ShellRGB(0.52, 0.32, 0.04),
            glow: ShellRGB(1.00, 0.92, 0.55)
        ),
        .sunset: atm(
            ShellRGB(0.98, 0.70, 0.48),
            ShellRGB(0.92, 0.48, 0.32),
            ShellRGB(0.78, 0.28, 0.22),
            tint: ShellRGB(0.86, 0.36, 0.18),
            chrome: ShellRGB(0.56, 0.18, 0.10),
            glow: ShellRGB(1.00, 0.78, 0.55)
        ),
        .orange: atm(
            ShellRGB(0.98, 0.72, 0.42),
            ShellRGB(0.94, 0.52, 0.22),
            ShellRGB(0.82, 0.36, 0.10),
            tint: ShellRGB(0.90, 0.42, 0.10),
            chrome: ShellRGB(0.58, 0.24, 0.04),
            glow: ShellRGB(1.00, 0.82, 0.48)
        ),
        .coral: atm(
            ShellRGB(0.98, 0.62, 0.55),
            ShellRGB(0.90, 0.42, 0.38),
            ShellRGB(0.76, 0.26, 0.26),
            tint: ShellRGB(0.84, 0.30, 0.26),
            chrome: ShellRGB(0.56, 0.14, 0.14),
            glow: ShellRGB(1.00, 0.72, 0.66)
        ),
        .rose: atm(
            ShellRGB(0.96, 0.62, 0.70),
            ShellRGB(0.86, 0.40, 0.52),
            ShellRGB(0.70, 0.22, 0.38),
            tint: ShellRGB(0.78, 0.24, 0.40),
            chrome: ShellRGB(0.52, 0.12, 0.26),
            glow: ShellRGB(1.00, 0.74, 0.80)
        ),
        .pink: atm(
            ShellRGB(0.96, 0.70, 0.82),
            ShellRGB(0.88, 0.48, 0.66),
            ShellRGB(0.72, 0.28, 0.50),
            tint: ShellRGB(0.80, 0.30, 0.52),
            chrome: ShellRGB(0.54, 0.14, 0.34),
            glow: ShellRGB(1.00, 0.80, 0.88)
        ),
        .magenta: atm(
            ShellRGB(0.90, 0.55, 0.88),
            ShellRGB(0.76, 0.32, 0.72),
            ShellRGB(0.58, 0.16, 0.56),
            tint: ShellRGB(0.70, 0.20, 0.64),
            chrome: ShellRGB(0.46, 0.08, 0.40),
            glow: ShellRGB(0.96, 0.68, 0.94)
        ),
        .purple: atm(
            ShellRGB(0.78, 0.58, 0.94),
            ShellRGB(0.58, 0.36, 0.82),
            ShellRGB(0.42, 0.20, 0.66),
            tint: ShellRGB(0.52, 0.26, 0.74),
            chrome: ShellRGB(0.34, 0.12, 0.50),
            glow: ShellRGB(0.86, 0.70, 1.00)
        ),
        .violet: atm(
            ShellRGB(0.70, 0.58, 0.96),
            ShellRGB(0.48, 0.38, 0.86),
            ShellRGB(0.32, 0.22, 0.70),
            tint: ShellRGB(0.42, 0.28, 0.78),
            chrome: ShellRGB(0.26, 0.14, 0.52),
            glow: ShellRGB(0.78, 0.70, 1.00)
        ),
        .indigo: atm(
            ShellRGB(0.58, 0.62, 0.96),
            ShellRGB(0.36, 0.40, 0.86),
            ShellRGB(0.22, 0.24, 0.68),
            tint: ShellRGB(0.30, 0.32, 0.76),
            chrome: ShellRGB(0.16, 0.16, 0.50),
            glow: ShellRGB(0.68, 0.72, 1.00)
        ),
        .slate: atm(
            ShellRGB(0.62, 0.70, 0.80),
            ShellRGB(0.42, 0.52, 0.64),
            ShellRGB(0.26, 0.34, 0.46),
            tint: ShellRGB(0.32, 0.42, 0.54),
            chrome: ShellRGB(0.18, 0.24, 0.34),
            glow: ShellRGB(0.78, 0.84, 0.92)
        ),
        .graphite: atm(
            ShellRGB(0.58, 0.62, 0.68),
            ShellRGB(0.40, 0.44, 0.50),
            ShellRGB(0.24, 0.26, 0.32),
            tint: ShellRGB(0.32, 0.34, 0.40),
            chrome: ShellRGB(0.18, 0.20, 0.24),
            glow: ShellRGB(0.74, 0.76, 0.80)
        ),
        .sand: atm(
            ShellRGB(0.94, 0.86, 0.70),
            ShellRGB(0.84, 0.70, 0.48),
            ShellRGB(0.68, 0.52, 0.32),
            tint: ShellRGB(0.72, 0.52, 0.28),
            chrome: ShellRGB(0.46, 0.30, 0.14),
            glow: ShellRGB(1.00, 0.92, 0.76)
        ),
        .ember: atm(
            ShellRGB(0.90, 0.48, 0.48),
            ShellRGB(0.74, 0.28, 0.30),
            ShellRGB(0.56, 0.14, 0.18),
            tint: ShellRGB(0.68, 0.18, 0.22),
            chrome: ShellRGB(0.46, 0.08, 0.10),
            glow: ShellRGB(0.98, 0.62, 0.58)
        )
    ]

    static let darkRecipes: [ShellPalette: ShellAtmosphere] = [
        .sky: atm(
            ShellRGB(0.03, 0.07, 0.14),
            ShellRGB(0.07, 0.13, 0.24),
            ShellRGB(0.04, 0.10, 0.20),
            tint: ShellRGB(0.23, 0.56, 0.85),
            chrome: ShellRGB(0.42, 0.71, 0.93),
            glow: ShellRGB(0.42, 0.71, 0.93)
        ),
        .ocean: atm(
            ShellRGB(0.02, 0.08, 0.14),
            ShellRGB(0.05, 0.16, 0.24),
            ShellRGB(0.03, 0.10, 0.18),
            tint: ShellRGB(0.18, 0.58, 0.78),
            chrome: ShellRGB(0.40, 0.80, 0.92),
            glow: ShellRGB(0.18, 0.58, 0.78)
        ),
        .teal: atm(
            ShellRGB(0.02, 0.10, 0.12),
            ShellRGB(0.05, 0.18, 0.20),
            ShellRGB(0.03, 0.12, 0.14),
            tint: ShellRGB(0.16, 0.62, 0.64),
            chrome: ShellRGB(0.42, 0.82, 0.82),
            glow: ShellRGB(0.16, 0.62, 0.64)
        ),
        .mint: atm(
            ShellRGB(0.03, 0.12, 0.10),
            ShellRGB(0.06, 0.20, 0.16),
            ShellRGB(0.04, 0.14, 0.12),
            tint: ShellRGB(0.22, 0.70, 0.56),
            chrome: ShellRGB(0.50, 0.86, 0.74),
            glow: ShellRGB(0.22, 0.70, 0.56)
        ),
        .forest: atm(
            ShellRGB(0.03, 0.10, 0.05),
            ShellRGB(0.07, 0.16, 0.08),
            ShellRGB(0.04, 0.12, 0.06),
            tint: ShellRGB(0.28, 0.62, 0.34),
            chrome: ShellRGB(0.48, 0.78, 0.52),
            glow: ShellRGB(0.28, 0.62, 0.34)
        ),
        .lime: atm(
            ShellRGB(0.08, 0.12, 0.03),
            ShellRGB(0.14, 0.20, 0.05),
            ShellRGB(0.08, 0.14, 0.03),
            tint: ShellRGB(0.62, 0.78, 0.22),
            chrome: ShellRGB(0.78, 0.90, 0.42),
            glow: ShellRGB(0.62, 0.78, 0.22)
        ),
        .gold: atm(
            ShellRGB(0.12, 0.09, 0.03),
            ShellRGB(0.20, 0.14, 0.04),
            ShellRGB(0.12, 0.08, 0.03),
            tint: ShellRGB(0.90, 0.70, 0.22),
            chrome: ShellRGB(0.96, 0.84, 0.42),
            glow: ShellRGB(0.90, 0.70, 0.22)
        ),
        .sunset: atm(
            ShellRGB(0.14, 0.06, 0.04),
            ShellRGB(0.22, 0.10, 0.07),
            ShellRGB(0.14, 0.06, 0.05),
            tint: ShellRGB(0.92, 0.48, 0.32),
            chrome: ShellRGB(0.98, 0.70, 0.48),
            glow: ShellRGB(0.92, 0.48, 0.32)
        ),
        .orange: atm(
            ShellRGB(0.14, 0.07, 0.02),
            ShellRGB(0.24, 0.12, 0.04),
            ShellRGB(0.14, 0.07, 0.03),
            tint: ShellRGB(0.94, 0.52, 0.22),
            chrome: ShellRGB(0.98, 0.72, 0.42),
            glow: ShellRGB(0.94, 0.52, 0.22)
        ),
        .coral: atm(
            ShellRGB(0.14, 0.05, 0.05),
            ShellRGB(0.22, 0.08, 0.08),
            ShellRGB(0.14, 0.05, 0.06),
            tint: ShellRGB(0.90, 0.42, 0.38),
            chrome: ShellRGB(0.98, 0.62, 0.55),
            glow: ShellRGB(0.90, 0.42, 0.38)
        ),
        .rose: atm(
            ShellRGB(0.14, 0.04, 0.08),
            ShellRGB(0.22, 0.08, 0.12),
            ShellRGB(0.14, 0.05, 0.09),
            tint: ShellRGB(0.86, 0.40, 0.52),
            chrome: ShellRGB(0.96, 0.62, 0.70),
            glow: ShellRGB(0.86, 0.40, 0.52)
        ),
        .pink: atm(
            ShellRGB(0.14, 0.05, 0.10),
            ShellRGB(0.22, 0.08, 0.16),
            ShellRGB(0.14, 0.05, 0.12),
            tint: ShellRGB(0.88, 0.48, 0.66),
            chrome: ShellRGB(0.96, 0.70, 0.82),
            glow: ShellRGB(0.88, 0.48, 0.66)
        ),
        .magenta: atm(
            ShellRGB(0.12, 0.04, 0.12),
            ShellRGB(0.20, 0.06, 0.18),
            ShellRGB(0.12, 0.04, 0.14),
            tint: ShellRGB(0.76, 0.32, 0.72),
            chrome: ShellRGB(0.90, 0.55, 0.88),
            glow: ShellRGB(0.76, 0.32, 0.72)
        ),
        .purple: atm(
            ShellRGB(0.08, 0.04, 0.14),
            ShellRGB(0.14, 0.07, 0.22),
            ShellRGB(0.08, 0.04, 0.16),
            tint: ShellRGB(0.58, 0.36, 0.82),
            chrome: ShellRGB(0.78, 0.58, 0.94),
            glow: ShellRGB(0.58, 0.36, 0.82)
        ),
        .violet: atm(
            ShellRGB(0.07, 0.04, 0.14),
            ShellRGB(0.12, 0.07, 0.24),
            ShellRGB(0.07, 0.04, 0.16),
            tint: ShellRGB(0.48, 0.38, 0.86),
            chrome: ShellRGB(0.70, 0.58, 0.96),
            glow: ShellRGB(0.48, 0.38, 0.86)
        ),
        .indigo: atm(
            ShellRGB(0.05, 0.05, 0.16),
            ShellRGB(0.10, 0.10, 0.26),
            ShellRGB(0.06, 0.06, 0.18),
            tint: ShellRGB(0.36, 0.40, 0.86),
            chrome: ShellRGB(0.58, 0.62, 0.96),
            glow: ShellRGB(0.36, 0.40, 0.86)
        ),
        .slate: atm(
            ShellRGB(0.06, 0.08, 0.12),
            ShellRGB(0.12, 0.14, 0.18),
            ShellRGB(0.07, 0.09, 0.13),
            tint: ShellRGB(0.42, 0.52, 0.64),
            chrome: ShellRGB(0.62, 0.70, 0.80),
            glow: ShellRGB(0.42, 0.52, 0.64)
        ),
        .graphite: atm(
            ShellRGB(0.06, 0.06, 0.07),
            ShellRGB(0.12, 0.12, 0.14),
            ShellRGB(0.07, 0.07, 0.08),
            tint: ShellRGB(0.40, 0.44, 0.50),
            chrome: ShellRGB(0.58, 0.62, 0.68),
            glow: ShellRGB(0.40, 0.44, 0.50)
        ),
        .sand: atm(
            ShellRGB(0.12, 0.09, 0.05),
            ShellRGB(0.20, 0.15, 0.08),
            ShellRGB(0.12, 0.09, 0.05),
            tint: ShellRGB(0.84, 0.70, 0.48),
            chrome: ShellRGB(0.94, 0.86, 0.70),
            glow: ShellRGB(0.84, 0.70, 0.48)
        ),
        .ember: atm(
            ShellRGB(0.12, 0.04, 0.05),
            ShellRGB(0.20, 0.06, 0.08),
            ShellRGB(0.12, 0.04, 0.06),
            tint: ShellRGB(0.74, 0.28, 0.30),
            chrome: ShellRGB(0.90, 0.48, 0.48),
            glow: ShellRGB(0.74, 0.28, 0.30)
        )
    ]
}
