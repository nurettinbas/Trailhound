import SwiftUI
import UIKit

enum OnboardingHeroKind: Equatable {
    case welcomeDrive
    case locationPin
    case shortcutsLink
}

/// Onboarding hero using the same road/car DNA as the recording card.
struct OnboardingHeroScene: View {
    var kind: OnboardingHeroKind
    var driveInProgress: CGFloat = 1
    /// Pin drop / Shortcuts link snap (0 → 1).
    var beatProgress: CGFloat = 1
    var isAnimating: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var metrics: TrailhoundRoadSceneMetrics { .hero }
    private var shouldAnimateRoad: Bool { isAnimating && !reduceMotion }
    private var animationInterval: TimeInterval {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? 1 / 12 : 1 / 30
    }

    var body: some View {
        Group {
            if shouldAnimateRoad {
                TimelineView(.animation(minimumInterval: animationInterval)) { timeline in
                    sceneDriver(
                        liveTime: timeline.date.timeIntervalSinceReferenceDate,
                        shouldAnimate: true
                    )
                }
            } else {
                sceneDriver(liveTime: nil, shouldAnimate: false)
            }
        }
        .frame(height: metrics.sceneHeight)
        .frame(maxWidth: .infinity)
        // No glass card — sit directly on AtmosphericBackground.
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func sceneDriver(liveTime: TimeInterval?, shouldAnimate: Bool) -> some View {
        OnboardingRoadSceneDriver(
            liveTime: liveTime,
            shouldAnimate: shouldAnimate,
            metrics: metrics,
            driveInProgress: driveInProgress,
            kind: kind,
            beatProgress: beatProgress,
            reduceMotion: reduceMotion
        )
    }
}

private struct OnboardingRoadSceneDriver: View {
    let liveTime: TimeInterval?
    let shouldAnimate: Bool
    let metrics: TrailhoundRoadSceneMetrics
    let driveInProgress: CGFloat
    let kind: OnboardingHeroKind
    let beatProgress: CGFloat
    let reduceMotion: Bool

    @State private var frozenRoadTime: TimeInterval = Date.timeIntervalSinceReferenceDate

    private var sceneTime: TimeInterval {
        if shouldAnimate, let liveTime {
            return liveTime
        }
        return frozenRoadTime
    }

    var body: some View {
        TrailhoundRoadDrivingScene(
            time: sceneTime,
            metrics: metrics,
            palette: .atmosphere,
            isPaused: false,
            driveInProgress: driveInProgress,
            showsPauseBadge: false
        ) { layout in
            OnboardingHeroOverlay(
                kind: kind,
                layout: layout,
                beatProgress: beatProgress,
                reduceMotion: reduceMotion
            )
        }
        .frame(height: metrics.sceneHeight)
        .onAppear {
            if let liveTime {
                frozenRoadTime = liveTime
            }
        }
        .onChange(of: shouldAnimate) { _, animating in
            if animating, let liveTime {
                frozenRoadTime = liveTime
            }
        }
        .onChange(of: liveTime) { _, newTime in
            if shouldAnimate, let newTime {
                frozenRoadTime = newTime
            }
        }
    }
}

private struct OnboardingHeroOverlay: View {
    let kind: OnboardingHeroKind
    let layout: TrailhoundRoadSceneLayout
    let beatProgress: CGFloat
    let reduceMotion: Bool

    var body: some View {
        switch kind {
        case .welcomeDrive:
            EmptyView()
        case .locationPin:
            locationPinOverlay
        case .shortcutsLink:
            shortcutsLinkOverlay
        }
    }

    private var locationPinOverlay: some View {
        let eased = TrailhoundRoadSceneMetrics.easeOutCubic(min(1, max(0, beatProgress)))
        let pinX = min(layout.size.width - 28, layout.carCenter.x + layout.carSize * 1.35)
        let settledY = layout.size.height - layout.roadHeight - 10
        let startY = settledY - 36
        let pinY = startY + (settledY - startY) * eased
        let pinOpacity = Double(0.2 + 0.8 * eased)

        return ZStack {
            SoftPulseRing(
                color: UIColor(TrailhoundBrandColors.brandBottom),
                isActive: eased > 0.85,
                reduceMotion: reduceMotion
            )
            .frame(width: 36, height: 36)
            .position(x: pinX, y: pinY)

            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white, TrailhoundBrandColors.brandBottom)
                .shadow(color: .black.opacity(0.28), radius: 3, y: 2)
                .scaleEffect(0.86 + 0.14 * eased)
                .opacity(pinOpacity)
                .position(x: pinX, y: pinY)
        }
        .allowsHitTesting(false)
    }

    private var shortcutsLinkOverlay: some View {
        let eased = TrailhoundRoadSceneMetrics.easeOutCubic(min(1, max(0, beatProgress)))
        let boltPoint = CGPoint(x: layout.size.width * 0.78, y: layout.size.height * 0.28)
        let carPoint = CGPoint(
            x: layout.carCenter.x + layout.carSize * 0.2,
            y: layout.carCenter.y - layout.carSize * 0.15
        )
        let mid = CGPoint(
            x: (boltPoint.x + carPoint.x) * 0.5,
            y: min(boltPoint.y, carPoint.y) - 18
        )

        return ZStack {
            Path { path in
                path.move(to: boltPoint)
                path.addQuadCurve(to: carPoint, control: mid)
            }
            .trim(from: 0, to: eased)
            .stroke(
                TrailhoundBrandColors.brandTop.opacity(0.95),
                style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
            )
            .shadow(color: TrailhoundBrandColors.brandBottom.opacity(0.45), radius: 4, y: 0)

            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.system(size: 28, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, TrailhoundBrandColors.brandBottom)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                .scaleEffect(0.9 + 0.1 * eased)
                .opacity(Double(0.35 + 0.65 * eased))
                .position(boltPoint)

            Circle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 7, height: 7)
                .shadow(color: TrailhoundBrandColors.brandBottom.opacity(0.6), radius: 3)
                .opacity(Double(eased))
                .position(carPoint)
        }
        .allowsHitTesting(false)
    }
}

#Preview("Welcome") {
    ZStack {
        AtmosphericBackground(style: .canvas)
        OnboardingHeroScene(kind: .welcomeDrive, driveInProgress: 1, beatProgress: 1)
            .padding()
    }
}

#Preview("Location") {
    ZStack {
        AtmosphericBackground(style: .canvas)
        OnboardingHeroScene(kind: .locationPin, driveInProgress: 1, beatProgress: 1)
            .padding()
    }
}

#Preview("Shortcuts") {
    ZStack {
        AtmosphericBackground(style: .canvas)
        OnboardingHeroScene(kind: .shortcutsLink, driveInProgress: 1, beatProgress: 1)
            .padding()
    }
}
