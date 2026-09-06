import SwiftUI

private struct TrailhoundProminentButtonModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(
                LightChromeProminentButtonStyle(
                    chrome: shellPalette.chromeColor(for: .light),
                    tint: shellPalette.tintColor(for: .light),
                    reduceMotion: reduceMotion
                )
            )
        }
    }
}

/// Light wells + `glassProminent` + chrome tint read as a dark-mode pill.
private struct LightChromeProminentButtonStyle: ButtonStyle {
    var chrome: Color
    var tint: Color
    var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(chrome)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(LightGlassPalette.selectedChipFill)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(tint.opacity(0.16))
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                    }
            }
            .scaleEffect((configuration.isPressed && !reduceMotion) ? 0.97 : 1)
            .animation(reduceMotion ? nil : TrailhoundMotion.cardSpring, value: configuration.isPressed)
    }
}

private struct TrailhoundGlassButtonModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        if colorScheme == .dark {
            content.buttonStyle(.bordered)
        } else if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .tint(shellPalette.shellTint(for: .light))
        } else {
            content
                .buttonStyle(SoftPressBorderedButtonStyle(reduceMotion: reduceMotion))
                .tint(shellPalette.shellTint(for: .light))
        }
    }
}

private struct TrailhoundDestructiveButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Capsule(style: .continuous)
                    .fill(GlassSemantic.notificationBadge)
            }
            .compositingGroup()
    }
}

extension View {
    func trailhoundProminentButton() -> some View {
        modifier(TrailhoundProminentButtonModifier())
    }

    func trailhoundGlassButton() -> some View {
        modifier(TrailhoundGlassButtonModifier())
    }

    /// Solid system-red fill — never glass-prominent, never Appearance tint.
    func trailhoundDestructiveButton() -> some View {
        modifier(TrailhoundDestructiveButtonModifier())
    }
}
