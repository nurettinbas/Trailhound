import Foundation

/// Performance-oriented rules for trip detail route reveal animation.
enum TripDetailRevealPolicy {
    static let shortRouteMaxPoints = 300
    static let animatedRouteMaxPoints = 1500

    struct AnimationPlan: Equatable {
        let shouldAnimate: Bool
        let tickCount: Int
        let stepSleepMilliseconds: Int
        /// Always true for trip detail: flat elevation + solid-only stroke during reveal.
        let useCheapMapDuringReveal: Bool
    }

    static func animationPlan(pointCount: Int, reduceMotion: Bool) -> AnimationPlan {
        // Medium and long display paths settle instantly — ticking 60×2 MapPolylines
        // while the sheet rises is what made detail open hitch.
        if reduceMotion || pointCount > shortRouteMaxPoints {
            return AnimationPlan(
                shouldAnimate: false,
                tickCount: 0,
                stepSleepMilliseconds: 0,
                useCheapMapDuringReveal: true
            )
        }

        return AnimationPlan(
            shouldAnimate: true,
            tickCount: 12,
            stepSleepMilliseconds: 40,
            useCheapMapDuringReveal: true
        )
    }

    static func quantizedProgress(rawProgress: Double, tick: Int, tickCount: Int) -> Double {
        guard tickCount > 0 else { return min(1, max(0, rawProgress)) }
        let clampedTick = min(tickCount, max(0, tick))
        return Double(clampedTick) / Double(tickCount)
    }
}
