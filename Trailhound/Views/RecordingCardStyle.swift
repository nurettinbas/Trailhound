import SwiftUI

enum RecordingCardStyle {
    static let cornerRadius: CGFloat = GlassTokens.cardRadius

    static func fillColors(
        isPaused: Bool,
        palette: ShellPalette,
        scheme: ColorScheme
    ) -> [Color] {
        let atm = palette.atmosphere(for: scheme)
        if isPaused {
            return [atm.mid.color.opacity(0.72), atm.bottom.color.opacity(0.88)]
        }
        return [atm.glow.color, atm.tint.color]
    }

    static func background(
        isPaused: Bool,
        palette: ShellPalette,
        scheme: ColorScheme
    ) -> LinearGradient {
        LinearGradient(
            colors: fillColors(isPaused: isPaused, palette: palette, scheme: scheme),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Glass recording hero: material + palette tint.
    @ViewBuilder
    static func glassSurface(isPaused: Bool) -> some View {
        RecordingGlassSurface(isPaused: isPaused)
    }

    /// Scroll-friendly surface for the trips list (no live material blur).
    @ViewBuilder
    static func listSurface(isPaused: Bool) -> some View {
        RecordingListSurface(isPaused: isPaused)
    }
}

private struct RecordingGlassSurface: View {
    let isPaused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RecordingCardStyle.cornerRadius, style: .continuous)
        let wash = RecordingCardStyle.background(
            isPaused: isPaused,
            palette: shellPalette,
            scheme: colorScheme
        )
        ZStack {
            if reduceTransparency {
                wash
            } else {
                shape.fill(.ultraThinMaterial)
                wash.opacity(colorScheme == .dark ? 0.72 : 0.55)
                shape.fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.18))
                shape.strokeBorder(Color.white.opacity(colorScheme == .dark ? 0 : 0.30), lineWidth: 1)
            }
        }
    }
}

private struct RecordingListSurface: View {
    let isPaused: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        RoundedRectangle(cornerRadius: RecordingCardStyle.cornerRadius, style: .continuous)
            .fill(
                RecordingCardStyle.background(
                    isPaused: isPaused,
                    palette: shellPalette,
                    scheme: colorScheme
                )
            )
    }
}

#Preview {
    ZStack {
        AtmosphericBackground()
        RecordingCardStyle.glassSurface(isPaused: false)
            .frame(height: 140)
            .overlay {
                RecordingCarAnimationView()
                    .padding(.horizontal)
            }
            .clipShape(RoundedRectangle(cornerRadius: RecordingCardStyle.cornerRadius, style: .continuous))
            .padding()
    }
}
