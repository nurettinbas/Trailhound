import SwiftUI

/// Light-theme liquid glass tokens. Dark keeps the existing GlassStyle recipe.
enum LightGlassPalette {
    static let atmosphereTop = ShellPalette.sky.atmosphere(for: .light).top.color
    static let atmosphereMid = ShellPalette.sky.atmosphere(for: .light).mid.color
    static let atmosphereBottom = ShellPalette.sky.atmosphere(for: .light).bottom.color

    static let panelFillOpacity = 0.10
    static let panelRimOpacity = 0.22
    static let panelSheenOpacity = 0.10
    static let chromeFillOpacity = 0.08
    static let chromeRimOpacity = 0.20
    static let fieldFillOpacity = 0.12
    static let formPanelFillOpacity = 0.12
    static let nativeGlassTintOpacity = 0.18

    static let selectedChipFill = Color.white.opacity(0.92)
    static let unselectedChipFill = Color.white.opacity(0.58)
    static let selectedChipText = Color(red: 0.122, green: 0.373, blue: 0.686)
    static let badgeFill = Color.white.opacity(0.92)
    static let badgeText = Color(red: 0.122, green: 0.373, blue: 0.686)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.74)
    static let textTertiary = Color.white.opacity(0.52)
    static let textPlaceholder = Color.white.opacity(0.50)
    static let textDisabled = Color.white.opacity(0.38)

    static let controlTint = Color(red: 0.090, green: 0.294, blue: 0.561)
    static let nativeGlassTint = Color.white.opacity(0.08)

    static func nativeTint(for palette: ShellPalette) -> Color {
        palette.tintColor(for: .light).opacity(nativeGlassTintOpacity)
    }

    static let increasedContrastPanelFill = 0.32
    static let contrastDarken = 0.15

    static let recording = Color(red: 1.00, green: 0.420, blue: 0.420)
    static let paused = Color(red: 1.00, green: 0.702, blue: 0.361)
    static let success = Color(red: 0.482, green: 0.894, blue: 0.584)
    static let destructive = Color(red: 1.00, green: 0.478, blue: 0.478)

    static func darkened(_ color: Color) -> Color {
        color.opacity(1 - contrastDarken)
    }
}

enum GlassText {
    static func primary(for scheme: ColorScheme, palette: ShellPalette = .sky) -> Color {
        if scheme == .dark { return Color.primary }
        return palette.usesLightChrome(for: .light) ? Color.primary : LightGlassPalette.textPrimary
    }

    static func secondary(for scheme: ColorScheme, palette: ShellPalette = .sky) -> Color {
        if scheme == .dark { return Color.secondary }
        return palette.usesLightChrome(for: .light)
            ? Color.secondary
            : LightGlassPalette.textSecondary
    }

    static func tertiary(for scheme: ColorScheme, palette: ShellPalette = .sky) -> Color {
        if scheme == .dark { return Color.secondary.opacity(0.8) }
        return palette.usesLightChrome(for: .light)
            ? Color.secondary.opacity(0.8)
            : LightGlassPalette.textTertiary
    }

    static func placeholder(for scheme: ColorScheme, palette: ShellPalette = .sky) -> Color {
        if scheme == .dark { return Color.secondary.opacity(0.7) }
        return palette.usesLightChrome(for: .light)
            ? Color.secondary.opacity(0.7)
            : LightGlassPalette.textPlaceholder
    }

    static func disabled(for scheme: ColorScheme, palette: ShellPalette = .sky) -> Color {
        if scheme == .dark { return Color.primary.opacity(0.28) }
        return palette.usesLightChrome(for: .light)
            ? Color.primary.opacity(0.28)
            : LightGlassPalette.textDisabled
    }
}

enum GlassSemantic {
    static func recording(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.red : LightGlassPalette.recording
    }

    static func paused(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.orange : LightGlassPalette.paused
    }

    static func success(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.green : LightGlassPalette.success
    }

    static func destructive(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.red : LightGlassPalette.destructive
    }

    /// Unread count on the trips bell. Always iOS system red (`#FF3B30`); never follows Appearance or glass tint.
    static let notificationBadge = Color(red: 1.0, green: 0.231, blue: 0.188)
}

enum GlassControlTint {
    static func toggle(for scheme: ColorScheme, palette: ShellPalette = .sky) -> Color {
        scheme == .dark ? palette.tintColor(for: .dark) : palette.chromeColor(for: .light)
    }

    static func control(for scheme: ColorScheme, palette: ShellPalette = .sky) -> Color {
        palette.shellTint(for: scheme)
    }

    static func segmented(for scheme: ColorScheme, palette: ShellPalette = .sky) -> Color {
        palette.tintColor(for: scheme)
    }

    static func link(for scheme: ColorScheme, palette: ShellPalette = .sky) -> Color {
        palette.shellTint(for: scheme)
    }
}
