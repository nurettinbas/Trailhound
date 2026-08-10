import SwiftUI

/// Compact running-hound mark for the trip-list Start control.
/// Transform-only gallop + two soft speed streaks — no TimelineView wake-ups.
struct TrailhoundRunningHoundIcon: View {
    var size: CGFloat = 30
    var reduceMotion: Bool = false

    @State private var gallopPhase: CGFloat = 0
    @State private var streakPhase: CGFloat = 0

    private var shouldAnimate: Bool {
        !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private var taskID: String {
        "\(shouldAnimate)"
    }

    private var accent: Color { TrailhoundBrandColors.start }
    /// Hound + speed streaks sit at 80% so the gallop lift clears the glass capsule edge.
    private let markScale: CGFloat = 0.968

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                // Room above for gallop lift so the layout box doesn't grow/shrink.
                Color.clear.frame(height: size * 0.62)

                VStack(spacing: 1) {
                    Image("TrailhoundHound")
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .frame(width: size * 0.92, height: size * 0.48)
                        .scaleEffect(
                            x: 1.02 + gallopPhase * 0.06,
                            y: 0.97 - gallopPhase * 0.07,
                            anchor: .bottom
                        )
                        .rotationEffect(.degrees(Double(gallopPhase) * -4.5), anchor: .bottom)
                        .offset(
                            x: gallopPhase * 0.5,
                            y: gallopPhase * -1.4
                        )
                        .foregroundStyle(accent)

                    speedStreaks
                }
                .scaleEffect(markScale, anchor: .bottom)
            }
            .frame(width: size, height: size * 0.62)

            Text(L10n.string("action.start"))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(accent)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: true)
                .padding(.top, 1)
        }
        .frame(minWidth: size)
        .fixedSize()
        .accessibilityHidden(true)
        .task(id: taskID) {
            await runMotion()
        }
    }

    /// Single dash under the hound; duplicated and scrolled for a seamless drift.
    private var speedStreaks: some View {
        let laneWidth = size * 0.78
        return ZStack {
            streakDash
                .offset(x: shouldAnimate ? -streakPhase * laneWidth : 0)
            streakDash
                .offset(x: shouldAnimate ? (1 - streakPhase) * laneWidth : laneWidth)
        }
        .frame(width: laneWidth, height: 2, alignment: .leading)
        .clipped()
        .opacity(shouldAnimate ? 0.9 : 0.35)
        .mask {
            LinearGradient(
                colors: [.clear, .black.opacity(0.85), .black, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var streakDash: some View {
        Capsule(style: .continuous)
            .fill(accent.opacity(0.42))
            .frame(width: size * 0.42, height: 1.35)
            .frame(width: size * 0.78, alignment: .leading)
    }

    @MainActor
    private func runMotion() async {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            gallopPhase = 0
            streakPhase = 0
        }

        guard shouldAnimate else { return }

        let gallopCycle: Double = 0.36
        withAnimation(.easeOut(duration: gallopCycle / 2)) {
            gallopPhase = 1
        }
        try? await Task.sleep(for: .seconds(gallopCycle / 2))
        guard !Task.isCancelled else { return }

        withAnimation(.easeInOut(duration: gallopCycle).repeatForever(autoreverses: true)) {
            gallopPhase = 0
        }
        // Linear 0→1 loop: twin streak pairs make the wrap seamless.
        withAnimation(.linear(duration: 0.48).repeatForever(autoreverses: false)) {
            streakPhase = 1
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        TrailhoundRunningHoundIcon(reduceMotion: true)
        TrailhoundRunningHoundIcon(reduceMotion: false)
    }
    .padding()
}
