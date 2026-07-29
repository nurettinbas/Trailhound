import Foundation

/// Performance-oriented rules for trip detail route reveal animation.
enum TripDetailRevealPolicy {
    static let shortRouteMaxPoints = 300
    static let animatedRouteMaxPoints = 1500

    struct AnimationPlan: Equatable {
        let shouldAnimate: Bool
        let tickCount: Int
        let stepSleepMilliseconds: Int
        /// When true, map uses flat elevation and a single polyline stroke during reveal.
        let useCheapMapDuringReveal: Bool
    }

    static func animationPlan(pointCount: Int, reduceMotion: Bool) -> AnimationPlan {
        if reduceMotion || pointCount > animatedRouteMaxPoints {
            return AnimationPlan(
                shouldAnimate: false,
                tickCount: 0,
                stepSleepMilliseconds: 0,
                useCheapMapDuringReveal: true
            )
        }

        if pointCount <= shortRouteMaxPoints {
            return AnimationPlan(
                shouldAnimate: true,
                tickCount: 16,
                stepSleepMilliseconds: 40,
                useCheapMapDuringReveal: false
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
