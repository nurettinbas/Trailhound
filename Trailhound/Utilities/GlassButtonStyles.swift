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
                    chrome: shellPalette.glassReadabilityTint(for: .light),
                    tint: shellPalette.tintColor(for: .light),
                    reduceMotion: reduceMotion
                )
            )
        }
    }
}

/// Saturated shell: tint pill + white label.
private struct LightChromeProminentButtonStyle: ButtonStyle {
    var chrome: Color
    var tint: Color
    var reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(tint)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                    }
            }
            .scaleEffect((configuration.isPressed && !reduceMotion) ? 0.97 : 1)
            .animation(reduceMotion ? nil : TrailhoundMotion.cardSpring, value: configuration.isPressed)
    }
}

/// Intrinsic-width tint capsule for in-card CTAs (recap Play). Same recipe in Light and Dark.
private struct TrailhoundCompactProminentChromeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .fixedSize(horizontal: true, vertical: false)
            .background {
                Capsule(style: .continuous)
                    .fill(shellPalette.tintColor(for: colorScheme))
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.72), lineWidth: 1)
                    }
            }
            .contentShape(Capsule())
            .padding(6)
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
            .frame(maxWidth: .infinity, minHeight: 34)
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

    /// Compact tint capsule (~32 pt visual, 44 pt hit). Intrinsic width — never truncates.
    func trailhoundCompactProminentButton() -> some View {
        modifier(TrailhoundCompactProminentChromeModifier())
    }

    func trailhoundGlassButton() -> some View {
        modifier(TrailhoundGlassButtonModifier())
    }

    /// Solid system-red fill — never glass-prominent, never Appearance tint.
    func trailhoundDestructiveButton() -> some View {
        modifier(TrailhoundDestructiveButtonModifier())
    }

    /// Scale-press for a whole glass / Stats card. Not a second chrome recipe.
    func trailhoundCardPress() -> some View {
        buttonStyle(.trailhoundCardPress)
    }
}

/// Soft 0.96 press on a tappable card. Reduce Motion keeps scale at 1.
struct TrailhoundCardPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : TrailhoundMotion.snappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == TrailhoundCardPressButtonStyle {
    static var trailhoundCardPress: TrailhoundCardPressButtonStyle {
        TrailhoundCardPressButtonStyle()
    }
}
