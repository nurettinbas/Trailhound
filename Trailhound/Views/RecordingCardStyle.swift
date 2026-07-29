import SwiftUI

enum RecordingCardStyle {
    static let activeGradient = TrailhoundBrandColors.activeGradient
    static let pausedGradient = TrailhoundBrandColors.pausedGradient
    static let cornerRadius: CGFloat = GlassTokens.cardRadius

    static func background(isPaused: Bool) -> LinearGradient {
        isPaused ? pausedGradient : activeGradient
    }

    /// Glass recording hero: material + brand tint (preserves white-on-blue controls).
    @ViewBuilder
    static func glassSurface(isPaused: Bool) -> some View {
        RecordingGlassSurface(isPaused: isPaused)
    }

    /// Scroll-friendly surface for the trips list (no live material blur).
    @ViewBuilder
    static func listSurface(isPaused: Bool) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(background(isPaused: isPaused))
    }
}

private struct RecordingGlassSurface: View {
    let isPaused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: RecordingCardStyle.cornerRadius, style: .continuous)
        ZStack {
            if reduceTransparency {
                RecordingCardStyle.background(isPaused: isPaused)
            } else {
                shape.fill(.ultraThinMaterial)
                RecordingCardStyle.background(isPaused: isPaused)
                    .opacity(0.72)
                shape.fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.12))
            }
        }
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
