import CoreLocation
import SwiftUI
import UIKit

enum TrailhoundMotion {
    static let snappy = Animation.snappy(duration: 0.28)
    /// Tab bar content switch — keep snappy so tab taps don't feel laggy.
    static let tabSwitch = Animation.easeOut(duration: 0.15)
    /// Notifications playback switch thumb — short snappy slide, no mush.
    static let recordingToggle = Animation.spring(response: 0.22, dampingFraction: 0.86)
    static let gentle = Animation.easeInOut(duration: 0.22)
    static let cardSpring = Animation.spring(response: 0.32, dampingFraction: 0.86)
    /// Recording card ↔ list row morph / stop settle.
    static let recordingMorph = Animation.spring(response: 0.26, dampingFraction: 0.9)
    /// Recording card entrance — card rise + car drive-in.
    static let coldOpenFade = Animation.spring(response: 0.28, dampingFraction: 0.88)
    /// Soft sheet rise for TripDetail panel.
    static let sheetRise = Animation.spring(response: 0.55, dampingFraction: 0.88)
    /// Map clarity / dark→clear open.
    static let mapClear = Animation.easeOut(duration: 0.9)
    /// Pin pop with a bit of overshoot.
    static let pinPop = Animation.spring(response: 0.36, dampingFraction: 0.72)
    /// Toast chip drop-in — soft overshoot, matches pinPop energy.
    static let toastSpring = Animation.spring(response: 0.42, dampingFraction: 0.78)
    /// Toast chip exit — quick ease up/fade.
    static let toastDismiss = Animation.easeIn(duration: 0.22)
    /// Vehicle photo framing settle (rotate / expand inline controls).
    static let photoSettle = Animation.spring(response: 0.34, dampingFraction: 0.86)
    /// Side actions spawn from the photo hero.
    static let photoActionsReveal = Animation.spring(response: 0.34, dampingFraction: 0.86)
    /// Source dialog → camera/gallery: sheet stretches upward as one filled surface.
    static let photoSheetExpand = Animation.spring(response: 1.1, dampingFraction: 0.86)
    /// Gallery/camera fade inside the grown card.
    static let photoSheetReveal = Animation.easeOut(duration: 0.56)
    /// Pure fade — no offset (offset reads as a new sheet rising).
    static var photoSheetRevealTransition: AnyTransition { .opacity }
    /// Avatar remove → empty add control (soft shrink out / rise in).
    static let photoRemove = Animation.spring(response: 0.4, dampingFraction: 0.84)

    /// Soft rise (fade + slight upward settle).
    static var softRiseTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 12)),
            removal: .opacity
        )
    }

    /// Soft slide in from the leading edge.
    static var softSlideFromLeadingTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(x: -28)),
            removal: .opacity
        )
    }

    /// Scale in 0.92 → 1 (no overshoot).
    static var softScaleInTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.92)),
            removal: .opacity
        )
    }

    /// Rise from below (buttons / bottom chrome).
    static var softRiseFromBottomTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 16)),
            removal: .opacity
        )
    }

    /// Photo hero swap: remove shrinks away; empty add rises in.
    static var photoHeroTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.88))
                .combined(with: .offset(y: 10)),
            removal: .opacity
                .combined(with: .scale(scale: 0.82))
                .combined(with: .offset(y: -8))
        )
    }

    /// Edit / Change / Delete spawn from the photo (leading = toward hero).
    static var photoActionsTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .scale(scale: 0.55))
                .combined(with: .offset(x: -18)),
            removal: .opacity
                .combined(with: .scale(scale: 0.7))
                .combined(with: .offset(x: -12))
        )
    }

    static func photoActionsRevealAnimation(delay: Double, reduceMotion: Bool) -> Animation? {
        if reduceMotion {
            return .easeOut(duration: 0.12).delay(delay * 0.25)
        }
        return photoActionsReveal.delay(delay)
    }

    /// Curtain / clip-reveal transition (progress 0 → 1).
    static func clipRevealTransition(edge: Edge = .top) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: ClipRevealEffect(progress: 0, edge: edge),
                identity: ClipRevealEffect(progress: 1, edge: edge)
            ),
            removal: .opacity
        )
    }

    static func cardAppearTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .move(edge: .top))
                .combined(with: .scale(scale: 0.98)),
            removal: .opacity
                .combined(with: .move(edge: .top))
                .combined(with: .scale(scale: 0.96))
        )
    }

    static func fadeScaleTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .identity }
        return .opacity.combined(with: .scale(scale: 0.98))
    }

    /// Toast chip: drop from above + scale settle; leave upward with fade.
    static func toastTransition(reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: -18))
                .combined(with: .scale(scale: 0.88)),
            removal: .opacity
                .combined(with: .offset(y: -10))
                .combined(with: .scale(scale: 0.94))
        )
    }
}

@MainActor
enum TrailhoundHaptics {
    static func recordingStarted() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func recordingPaused() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func recordingResumed() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func recordingStopped() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func pairingSucceeded() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func destructive() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }
}

private struct NumericTextAnimationModifier<V: Equatable>: ViewModifier {
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(.numericText())
            .animation(reduceMotion ? nil : TrailhoundMotion.snappy, value: value)
    }
}

private struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.35),
                                Color.white.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 0.6)
                        .offset(x: -geometry.size.width + phase * geometry.size.width * 2)
                        .onAppear {
                            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                                phase = 1
                            }
                        }
                    }
                }
            }
    }
}

/// One-shot diagonal sun/glint for vehicle photo hero — overlay removed when finished.
private struct PhotoEntranceGlintModifier: ViewModifier {
    let cornerRadius: CGFloat
    let glintID: String
    var onFinished: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0
    @State private var finished = false
    @State private var playedID: String?

    private let duration: TimeInterval = 0.85

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion, !finished {
                    GeometryReader { geometry in
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.45),
                                Color.white.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(width: geometry.size.width * 0.42, height: geometry.size.height * 1.55)
                        .rotationEffect(.degrees(22))
                        .offset(x: -geometry.size.width + phase * geometry.size.width * 2.15)
                        .allowsHitTesting(false)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
                }
            }
            .onAppear(perform: playIfNeeded)
            .onChange(of: glintID) { _, _ in
                finished = false
                phase = 0
                playedID = nil
                playIfNeeded()
            }
    }

    private func playIfNeeded() {
        guard !reduceMotion else {
            finished = true
            onFinished?()
            return
        }
        guard playedID != glintID else { return }
        playedID = glintID
        finished = false
        phase = 0

        Task { @MainActor in
            withAnimation(.easeOut(duration: duration)) {
                phase = 1
            }
            try? await Task.sleep(for: .milliseconds(Int(duration * 1000) + 40))
            finished = true
            phase = 0
            onFinished?()
        }
    }
}

/// Curtain wipe — reveals content by expanding a clip from an edge.
struct ClipRevealEffect: ViewModifier, Animatable {
    var progress: CGFloat
    var edge: Edge

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let clamped = min(1, max(0, progress))
        let p = max(clamped, 0.001)
        let horizontal = (edge == .leading || edge == .trailing)
        content
            .mask(alignment: clipAlignment) {
                Rectangle()
                    .scaleEffect(
                        x: horizontal ? p : 1,
                        y: horizontal ? 1 : p,
                        anchor: clipAnchor
                    )
            }
            .opacity(Double(min(1, clamped * 1.2)))
    }

    private var clipAnchor: UnitPoint {
        switch edge {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        @unknown default: .top
        }
    }

    private var clipAlignment: Alignment {
        switch edge {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        @unknown default: .top
        }
    }
}

extension View {
    func clipReveal(progress: CGFloat, edge: Edge = .top) -> some View {
        modifier(ClipRevealEffect(progress: progress, edge: edge))
    }

    func numericTextAnimation<V: Equatable>(value: V) -> some View {
        modifier(NumericTextAnimationModifier(value: value))
    }

    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }

    /// One-shot entrance glint; overlay is removed after the sweep finishes.
    func photoEntranceGlint(
        cornerRadius: CGFloat,
        id: String,
        onFinished: (() -> Void)? = nil
    ) -> some View {
        modifier(
            PhotoEntranceGlintModifier(
                cornerRadius: cornerRadius,
                glintID: id,
                onFinished: onFinished
            )
        )
    }

    func trailhoundCardTransition(reduceMotion: Bool) -> some View {
        transition(TrailhoundMotion.cardAppearTransition(reduceMotion: reduceMotion))
    }

    @ViewBuilder
    func matchedGeometryEffectIfAvailable(
        id: UUID?,
        namespace: Namespace.ID?,
        isSource: Bool
    ) -> some View {
        if let id, let namespace {
            matchedGeometryEffect(id: id, in: namespace, properties: .frame, isSource: isSource)
        } else {
            self
        }
    }

    @ViewBuilder
    func matchedGeometryEffectIfAvailable(
        stringID: String?,
        namespace: Namespace.ID?,
        isSource: Bool
    ) -> some View {
        if let stringID, let namespace {
            matchedGeometryEffect(id: stringID, in: namespace, properties: .frame, isSource: isSource)
        } else {
            self
        }
    }
}

/// Soft press feedback for bordered controls (Pause / Resume, etc.).
struct SoftPressBorderedButtonStyle: PrimitiveButtonStyle {
    var reduceMotion: Bool = false
    var pressedScale: CGFloat = 0.96

    func makeBody(configuration: Configuration) -> some View {
        SoftPressBorderedPrimitive(
            configuration: configuration,
            reduceMotion: reduceMotion,
            pressedScale: pressedScale
        )
    }
}

private struct SoftPressBorderedPrimitive: View {
    let configuration: PrimitiveButtonStyleConfiguration
    var reduceMotion: Bool
    var pressedScale: CGFloat

    @GestureState private var isPressed = false

    var body: some View {
        BorderedButtonStyle()
            .makeBody(configuration: configuration)
            .scaleEffect((isPressed && !reduceMotion) ? pressedScale : 1)
            .animation(reduceMotion ? nil : TrailhoundMotion.cardSpring, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isPressed) { _, state, _ in
                        state = true
                    }
            )
    }
}

// MARK: - Route path reveal

enum RoutePathReveal {
    /// Returns a polyline prefix for `progress` in `0...1`, with an interpolated tip.
    static func prefix(
        _ coordinates: [CLLocationCoordinate2D],
        progress: Double
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count >= 2 else { return coordinates }
        let clamped = min(1, max(0, progress))
        if clamped <= 0 { return [coordinates[0]] }
        if clamped >= 1 { return coordinates }

        let segmentCount = coordinates.count - 1
        let exact = Double(segmentCount) * clamped
        let index = min(segmentCount - 1, Int(exact))
        let fraction = exact - Double(index)
        var result = Array(coordinates.prefix(index + 1))
        let start = coordinates[index]
        let end = coordinates[index + 1]
        result.append(
            CLLocationCoordinate2D(
                latitude: start.latitude + (end.latitude - start.latitude) * fraction,
                longitude: start.longitude + (end.longitude - start.longitude) * fraction
            )
        )
        return result
    }

    static func tip(
        of coordinates: [CLLocationCoordinate2D],
        progress: Double
    ) -> CLLocationCoordinate2D? {
        prefix(coordinates, progress: progress).last
    }

    /// Fraction along the point index range closest to `coordinate` (0...1).
    static func progress(
        nearestTo coordinate: CLLocationCoordinate2D,
        in coordinates: [CLLocationCoordinate2D]
    ) -> Double {
        guard coordinates.count >= 2 else { return 0 }
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, point) in coordinates.enumerated() {
            let dLat = point.latitude - coordinate.latitude
            let dLon = point.longitude - coordinate.longitude
            let distance = dLat * dLat + dLon * dLon
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return Double(bestIndex) / Double(coordinates.count - 1)
    }
}

// MARK: - Soft pulse ring (Core Animation)

/// Compact Core Animation glow ring — used for recording tab badge and similar live signals.
struct SoftPulseRing: UIViewRepresentable {
    var color: UIColor
    var isActive: Bool
    var reduceMotion: Bool

    func makeUIView(context: Context) -> SoftPulseRingView {
        SoftPulseRingView()
    }

    func updateUIView(_ uiView: SoftPulseRingView, context: Context) {
        uiView.apply(color: color, isActive: isActive && !reduceMotion)
    }
}

final class SoftPulseRingView: UIView {
    private let ringLayer = CAShapeLayer()
    private var isActive = false
    private var ringColor: UIColor = .systemRed

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        backgroundColor = .clear

        ringLayer.fillColor = UIColor.clear.cgColor
        ringLayer.lineWidth = 2
        ringLayer.opacity = 0
        layer.addSublayer(ringLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = ringLayer.lineWidth
        ringLayer.frame = bounds
        ringLayer.path = UIBezierPath(ovalIn: bounds.insetBy(dx: inset, dy: inset)).cgPath
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, isActive {
            startPulseIfNeeded()
        }
    }

    func apply(color: UIColor, isActive: Bool) {
        ringColor = color
        ringLayer.strokeColor = color.withAlphaComponent(0.7).cgColor
        self.isActive = isActive

        if isActive {
            isHidden = false
            startPulseIfNeeded()
        } else {
            stopPulse()
            ringLayer.opacity = 0
            ringLayer.transform = CATransform3DIdentity
            isHidden = true
        }
    }

    private func startPulseIfNeeded() {
        guard ringLayer.animation(forKey: "softPulse") == nil else { return }
        ringLayer.opacity = 0.4
        ringLayer.transform = CATransform3DIdentity

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.25
        opacity.toValue = 0.75

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.92
        scale.toValue = 1.18

        let group = CAAnimationGroup()
        group.animations = [opacity, scale]
        group.duration = 1.7
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        group.isRemovedOnCompletion = false
        ringLayer.add(group, forKey: "softPulse")
    }

    private func stopPulse() {
        ringLayer.removeAnimation(forKey: "softPulse")
    }
}
