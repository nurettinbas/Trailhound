import SwiftUI
import UIKit

private struct GlassControlSchemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        if colorScheme == .dark || shellPalette.usesLightChrome(for: colorScheme) {
            content
        } else {
            content.environment(\.colorScheme, .dark)
        }
    }
}

private struct GlassToggleTintModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content.tint(GlassControlTint.toggle(for: colorScheme, palette: shellPalette))
    }
}

struct GlassSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

struct GlassSectionFooter: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

/// Nav-bar map control that matches the system back chip (light well + dark glyph
/// in Light). Ignores `glassControlScheme` flipping the environment to dark.
struct GlassNavCircleIcon: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.primary)
            .symbolRenderingMode(.monochrome)
            .frame(width: 36, height: 36)
            .background {
                Circle()
                    .fill(.ultraThinMaterial)
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(chipScheme == .dark ? 0.22 : 0.10), lineWidth: 1)
            }
            .environment(\.colorScheme, chipScheme)
    }

    /// Window / Settings appearance — not the flipped leaf `colorScheme`.
    private var chipScheme: ColorScheme {
        if let preferred = AppSettings.shared.appearanceMode.preferredColorScheme {
            return preferred
        }
        return UITraitCollection.current.userInterfaceStyle == .dark ? .dark : .light
    }
}

extension View {
    /// Forces leaf system controls (DatePicker / menu Picker / TextField) to draw light labels
    /// on the colored shell without flipping Material sampling for ancestors.
    func glassControlScheme() -> some View {
        modifier(GlassControlSchemeModifier())
    }

    func glassToggleStyle() -> some View {
        modifier(GlassToggleTintModifier())
    }

    func glassTextField() -> some View {
        glassInputField()
            .glassControlScheme()
    }

    func glassStepper() -> some View {
        glassControlScheme()
            .modifier(GlassStepperTintModifier())
    }
}

extension ToolbarContent {
    /// Drops the iOS 26 system toolbar platter when the control draws its own circle.
    @ToolbarContentBuilder
    func hideSharedToolbarBackgroundIfAvailable() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

private struct GlassStepperTintModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content.tint(shellPalette.shellTint(for: colorScheme))
    }
}
