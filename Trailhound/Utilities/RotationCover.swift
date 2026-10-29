import UIKit

enum RotationCoverPolicy {
    /// Share of the turn the old screen takes to fade. Gone well before it ends up
    /// sideways, so its edges never read as a card in the middle of the new screen.
    static let fadeShare: Double = 0.6
}

/// The screen as it was when the turn began. It rotates with the window and fades
/// into the new layout underneath, the system crossfade. No blur, no plate.
@MainActor
final class RotationCover {
    static let shared = RotationCover()

    private var snapshot: UIImageView?
    private var token = 0

    /// Captures the window before UIKit resizes it. A failed capture leaves the turn uncovered.
    func arm(on window: UIWindow?) {
        token += 1
        clear()
        guard let window, let image = capture(window) else { return }

        let view = UIImageView(image: image)
        view.frame = window.bounds
        view.autoresizingMask = []
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        window.addSubview(view)
        snapshot = view
    }

    /// Runs inside the coordinator's animation, so the fade follows the system turn curve.
    func track(targetSize: CGSize, duration: TimeInterval) {
        guard let snapshot, targetSize.width > 1, targetSize.height > 1 else { return }
        snapshot.superview?.bringSubviewToFront(snapshot)
        snapshot.center = CGPoint(x: targetSize.width / 2, y: targetSize.height / 2)
        UIView.animateKeyframes(withDuration: duration, delay: 0, options: [.calculationModeCubic]) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: RotationCoverPolicy.fadeShare) {
                snapshot.alpha = 0
            }
        }
    }

    /// Faded by now on a finished turn. A cancelled turn keeps the old layout, so nothing fades back.
    func finish() {
        clear()
    }

    private func capture(_ window: UIWindow) -> UIImage? {
        let bounds = window.bounds
        guard bounds.width > 1, bounds.height > 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.windowScene?.screen.scale ?? 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: bounds, format: format)
        var drew = false
        let image = renderer.image { _ in
            drew = window.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
        guard drew, image.size.width > 1, image.size.height > 1 else { return nil }
        return image
    }

    private func clear() {
        snapshot?.layer.removeAllAnimations()
        snapshot?.removeFromSuperview()
        snapshot = nil
    }
}
