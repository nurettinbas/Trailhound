import SwiftUI

/// Compact running-hound mark for the trip-list Start control.
/// Timeline-driven gallop + speed streaks so theme / parent transactions
/// cannot hijack mid-flight offsets (the classic “streak jump” on appearance change).
struct TrailhoundRunningHoundIcon: View {
    var size: CGFloat = 30
    var reduceMotion: Bool = false

    private var shouldAnimate: Bool {
        !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    private var accent: Color { TrailhoundBrandColors.start }
    /// Hound + speed streaks sit at 80% so the gallop lift clears the glass capsule edge.
    private let markScale: CGFloat = 0.968

    /// Full gallop up/down cycle — matches original easeInOut(0.36) × 2.
    private let gallopPeriod: TimeInterval = 0.72
    /// One seamless lane-width scroll — original default speed.
    private let streakPeriod: TimeInterval = 0.48
    private var tickInterval: TimeInterval {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? 1 / 10 : 1 / 20
    }

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: tickInterval,
                paused: !shouldAnimate
            )
        ) { context in
            let phases = motionPhases(at: context.date)
            mark(gallopPhase: phases.gallop, streakPhase: phases.streak)
        }
        .frame(minWidth: size)
        .fixedSize()
        .accessibilityHidden(true)
    }

    private func mark(gallopPhase: CGFloat, streakPhase: CGFloat) -> some View {
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

                    speedStreaks(phase: streakPhase)
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
    }

    /// Single dash under the hound; duplicated and scrolled for a seamless drift.
    private func speedStreaks(phase: CGFloat) -> some View {
        let laneWidth = size * 0.78
        return ZStack {
            streakDash
                .offset(x: shouldAnimate ? -phase * laneWidth : 0)
            streakDash
                .offset(x: shouldAnimate ? (1 - phase) * laneWidth : laneWidth)
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

    private func motionPhases(at date: Date) -> (gallop: CGFloat, streak: CGFloat) {
        guard shouldAnimate else { return (0, 0) }
        let t = date.timeIntervalSinceReferenceDate
        // Ease in/out gallop via a raised cosine (0→1→0).
        let gallopUnit = t.truncatingRemainder(dividingBy: gallopPeriod) / gallopPeriod
        let gallop = CGFloat(0.5 - 0.5 * cos(gallopUnit * 2 * .pi))
        let streak = CGFloat(t.truncatingRemainder(dividingBy: streakPeriod) / streakPeriod)
        return (gallop, streak)
    }
}

#Preview {
    HStack(spacing: 24) {
        TrailhoundRunningHoundIcon(reduceMotion: true)
        TrailhoundRunningHoundIcon(reduceMotion: false)
    }
    .padding()
}
