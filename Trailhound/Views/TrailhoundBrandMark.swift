import SwiftUI

/// App icon mark + Trailhound wordmark for onboarding cold-open.
struct TrailhoundBrandMark: View {
    var showsWordmark: Bool = true
    var symbolSize: CGFloat = 88

    var body: some View {
        VStack(spacing: 14) {
            Image("TrailhoundLogo")
                .resizable()
                .scaledToFit()
                .frame(width: symbolSize, height: symbolSize)
                .clipShape(RoundedRectangle(cornerRadius: symbolSize * 0.22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: symbolSize * 0.22, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                }
                .shadow(color: TrailhoundBrandColors.brandBottom.opacity(0.28), radius: 16, y: 8)
                .accessibilityHidden(true)

            if showsWordmark {
                Text("Trailhound")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trailhound")
    }
}

#Preview {
    ZStack {
        AtmosphericBackground(style: .canvas)
        TrailhoundBrandMark()
    }
}
