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
        content
            .tint(GlassControlTint.toggle(for: colorScheme, palette: shellPalette))
            // Keep the system switch on the real Light/Dark chrome. A dark-scheme
            // switch on a light grouped row is a white pill with no track.
            .environment(\.colorScheme, colorScheme)
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

/// Palette-colored nav control used over maps where neutral system glass can clash
/// with the selected shell appearance.
struct GlassNavCircleIcon: View {
    let systemName: String
    var isLoading: Bool = false

    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemName)
                    .font(.body.weight(.semibold))
                    .symbolRenderingMode(.monochrome)
            }
        }
        .foregroundStyle(Color.white)
        .tint(Color.white)
        .frame(width: 36, height: 36)
        .background {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                Circle()
                    .fill(controlFill.opacity(chipScheme == .dark ? 0.72 : 0.88))
            }
        }
        .overlay {
            Circle()
                .strokeBorder(Color.white.opacity(0.34), lineWidth: 1)
        }
        .environment(\.colorScheme, chipScheme)
    }

    private var controlFill: Color {
        chipScheme == .dark
            ? shellPalette.tintColor(for: .dark)
            : shellPalette.chromeColor(for: .light)
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
