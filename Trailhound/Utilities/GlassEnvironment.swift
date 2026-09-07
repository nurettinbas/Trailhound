import SwiftUI

private struct ShellPaletteKey: EnvironmentKey {
    static let defaultValue: ShellPalette = .sky
}

extension EnvironmentValues {
    var shellPalette: ShellPalette {
        get { self[ShellPaletteKey.self] }
        set { self[ShellPaletteKey.self] = newValue }
    }
}

private struct OnGlassShellModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content
        } else {
            content
                .foregroundStyle(shellPalette.shellForeground(for: .light))
                .tint(shellPalette.shellTint(for: .light))
                .toolbarColorScheme(shellPalette.toolbarColorScheme(for: .light), for: .navigationBar, .tabBar)
        }
    }
}

extension View {
    /// Light glass shell: hierarchical text/icons and a matching toolbar color scheme.
    /// Dark is a no-op so the existing recipe is unchanged.
    func onGlassShell() -> some View {
        modifier(OnGlassShellModifier())
    }

    /// Palette accent in dark; white (or chrome tint) on the light glass shell.
    func glassAccentForeground() -> some View {
        modifier(GlassAccentForegroundModifier())
    }

    func glassPrimaryInk() -> some View {
        modifier(GlassPrimaryInkModifier())
    }

    func glassSecondaryInk() -> some View {
        modifier(GlassSecondaryInkModifier())
    }

    func glassTertiaryInk() -> some View {
        modifier(GlassTertiaryInkModifier())
    }

    /// Palette chrome on Light glass; secondary in Dark. Use for row `>` chevrons.
    func glassDisclosureInk() -> some View {
        modifier(GlassDisclosureInkModifier())
    }

    /// Drops the system NavigationLink `>` so a `GlassDisclosureChevron` can own the color.
    func glassHidesNavigationLinkIndicator() -> some View {
        modifier(GlassHidesNavigationLinkIndicator())
    }
}

private struct GlassPrimaryInkModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.foregroundStyle(GlassText.primary(for: colorScheme))
    }
}

private struct GlassSecondaryInkModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.foregroundStyle(GlassText.secondary(for: colorScheme))
    }
}

private struct GlassTertiaryInkModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.foregroundStyle(GlassText.tertiary(for: colorScheme))
    }
}

private struct GlassDisclosureInkModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content.foregroundStyle(GlassControlTint.disclosure(for: colorScheme, palette: shellPalette))
    }
}

private struct GlassHidesNavigationLinkIndicator: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.navigationLinkIndicatorVisibility(.hidden)
        } else {
            content
        }
    }
}

private struct GlassAccentForegroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content.foregroundStyle(GlassControlTint.link(for: colorScheme, palette: shellPalette))
    }
}
