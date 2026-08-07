import SwiftUI

struct ToastView: View {
    let kind: ToastKind

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var iconBounceToken = 0
    @State private var settled = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: kind.systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(kind.tint)
                .symbolEffect(.bounce, value: iconBounceToken)
                .scaleEffect(settled ? 1 : 0.72)
                .accessibilityHidden(true)
            Text(kind.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: 280, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(settled ? 1 : 0.72)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .fixedSize()
        .glassChrome(cornerRadius: GlassTokens.chipRadius)
        .shadow(
            color: .black.opacity(settled ? 0.14 : 0.04),
            radius: settled ? 14 : 6,
            y: settled ? 5 : 2
        )
        .scaleEffect(settled ? 1 : 0.96)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(kind.message)
        .onAppear {
            guard !reduceMotion else {
                settled = true
                return
            }
            withAnimation(TrailhoundMotion.pinPop) {
                settled = true
            }
            // Slight beat after the chip lands so the icon bounce reads clearly.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(90))
                iconBounceToken += 1
            }
        }
        .onChange(of: kind) { _, _ in
            guard !reduceMotion else { return }
            settled = false
            withAnimation(TrailhoundMotion.pinPop) {
                settled = true
            }
            iconBounceToken += 1
        }
    }
}
