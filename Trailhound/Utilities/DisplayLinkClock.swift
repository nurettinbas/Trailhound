import Foundation
import QuartzCore

/// Thin `CADisplayLink` bridge that reports frame deltas on the main actor.
@MainActor
final class DisplayLinkClock {
    private final class Target: NSObject {
        var handler: ((CADisplayLink) -> Void)?

        @objc func step(_ link: CADisplayLink) {
            handler?(link)
        }
    }

    private let target = Target()
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    /// Called each display frame with a clamped `dt` in seconds.
    var onTick: ((TimeInterval) -> Void)?

    var isRunning: Bool { link != nil }

    func start() {
        guard link == nil else { return }
        lastTimestamp = 0
        let displayLink = CADisplayLink(target: target, selector: #selector(Target.step(_:)))
        target.handler = { [weak self] link in
            self?.handle(link)
        }
        displayLink.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        displayLink.add(to: .main, forMode: .common)
        self.link = displayLink
    }

    func stop() {
        link?.invalidate()
        link = nil
        lastTimestamp = 0
        target.handler = nil
    }

    private func handle(_ link: CADisplayLink) {
        let timestamp = link.timestamp
        let dt: TimeInterval
        if lastTimestamp > 0 {
            dt = min(max(timestamp - lastTimestamp, 0), LiveFollowCamera.maxTickDeltaSeconds)
        } else {
            dt = link.duration > 0 ? link.duration : (1.0 / 60.0)
        }
        lastTimestamp = timestamp
        onTick?(dt)
    }
}
