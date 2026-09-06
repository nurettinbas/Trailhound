import SwiftUI

private struct GlassEngineOverrideKey: EnvironmentKey {
    static let defaultValue: GlassEngineOverride = .auto
}

private struct ShellPaletteKey: EnvironmentKey {
    static let defaultValue: ShellPalette = .sky
}

extension EnvironmentValues {
    var glassEngineOverride: GlassEngineOverride {
        get { self[GlassEngineOverrideKey.self] }
        set { self[GlassEngineOverrideKey.self] = newValue }
    }

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
}

private struct GlassAccentForegroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content.foregroundStyle(GlassControlTint.link(for: colorScheme, palette: shellPalette))
    }
}
