import SwiftUI
import UIKit

struct RecordingCarAnimationView<CarOverlay: View>: View {
    var compact: Bool = false
    /// When true, the road clock ticks (TimelineView stays mounted). Independent of pause.
    var isAnimating: Bool = true
    /// Freeze dashes / smoke / bounce and show the pause badge — does not tear down TimelineView.
    var isPaused: Bool = false
    /// 0 = car off-screen left, 1 = settled driving position.
    var driveInProgress: CGFloat = 1
    /// Side-profile SF Symbol fallback; default is the fixed right-facing car.
    var systemImage: String? = nil
    /// Pre-decoded thumb from the app target — never load from disk here (TimelineView hot path).
    var vehiclePhoto: UIImage? = nil
    /// `scaleEffect(x:)` for the symbol so it faces right. Default `-1` matches `car.side.fill`.
    var symbolScaleX: CGFloat = -1
    /// Compact notification / list cards skip the sin bounce (avoids pause/resume bounce-in/out).
    var allowsVerticalBounce: Bool = true
    @ViewBuilder var carOverlay: (TrailhoundRoadSceneLayout) -> CarOverlay

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var metrics: TrailhoundRoadSceneMetrics { compact ? .compact : .regular }
    /// Keep the same view tree on pause/resume — only freeze the clock when not animating.
    private var shouldRunClock: Bool { isAnimating && !reduceMotion }
    private var animationInterval: TimeInterval {
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return 1 / 12 }
        return compact ? (1 / 15) : (1 / 30)
    }

    /// Remount when the mark asset changes. Pause/resume keeps the same id (no swap jank);
    /// vehicle photo swaps must bust `drawingGroup` + paused TimelineView caches.
    private var markIdentity: String {
        if let vehiclePhoto {
            return "photo-\(ObjectIdentifier(vehiclePhoto))"
        }
        return "symbol-\(systemImage ?? "car.side.fill")"
    }

    var body: some View {
        // Always keep TimelineView mounted so pause/resume never swaps view trees
        // (that remount was the main notification-card jank source). Pause the
        // schedule instead — frozen last frame, no continuous redraws.
        TimelineView(
            .animation(
                minimumInterval: animationInterval,
                paused: !shouldRunClock || isPaused
            )
        ) { timeline in
            RoadSceneDriver(
                liveTime: timeline.date.timeIntervalSinceReferenceDate,
                shouldAnimate: shouldRunClock && !isPaused,
                isPaused: isPaused,
                metrics: metrics,
                driveInProgress: driveInProgress,
                showsPauseBadge: true,
                systemImage: systemImage,
                vehiclePhoto: vehiclePhoto,
                symbolScaleX: symbolScaleX,
                allowsVerticalBounce: allowsVerticalBounce,
                carOverlay: carOverlay
            )
        }
        .id(markIdentity)
        .frame(height: metrics.sceneHeight)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 10))
        .drawingGroup(opaque: false, colorMode: .linear)
        .accessibilityHidden(true)
    }
}

extension RecordingCarAnimationView where CarOverlay == EmptyView {
    init(
        compact: Bool = false,
        isAnimating: Bool = true,
        isPaused: Bool = false,
        driveInProgress: CGFloat = 1,
        systemImage: String? = nil,
        vehiclePhoto: UIImage? = nil,
        symbolScaleX: CGFloat = -1,
        allowsVerticalBounce: Bool = true
    ) {
        self.compact = compact
        self.isAnimating = isAnimating
        self.isPaused = isPaused
        self.driveInProgress = driveInProgress
        self.systemImage = systemImage
        self.vehiclePhoto = vehiclePhoto
        self.symbolScaleX = symbolScaleX
        self.allowsVerticalBounce = allowsVerticalBounce
        self.carOverlay = { _ in EmptyView() }
    }
}

/// Shared sizing for recording + onboarding road scenes.
struct TrailhoundRoadSceneMetrics: Equatable {
    var sceneHeight: CGFloat
    var roadHeight: CGFloat
    var carSize: CGFloat
    var cornerRadius: CGFloat
    var settledXFraction: CGFloat

    static let compact = TrailhoundRoadSceneMetrics(
        sceneHeight: 44,
        roadHeight: 18,
        carSize: 22,
        cornerRadius: 8,
        settledXFraction: 0.58
    )

    static let regular = TrailhoundRoadSceneMetrics(
        sceneHeight: 80,
        roadHeight: 30,
        carSize: 36,
        cornerRadius: 10,
        settledXFraction: 0.58
    )

    static let hero = TrailhoundRoadSceneMetrics(
        sceneHeight: 140,
        roadHeight: 28,
        carSize: 44,
        cornerRadius: 16,
        settledXFraction: 0.5
    )

    static func easeOutCubic(_ t: CGFloat) -> CGFloat {
        1 - pow(1 - t, 3)
    }
}

struct TrailhoundRoadSceneLayout: Equatable {
    var size: CGSize
    var carCenter: CGPoint
    var carSize: CGFloat
    var roadHeight: CGFloat
    var driveEased: CGFloat
    var isPaused: Bool
}

/// Recording card = white car on dark road over brand glass.
/// Atmosphere = no road slab; brand car + flowing lane dashes on the shell (light/dark).
enum TrailhoundRoadScenePalette: Equatable {
    case recording
    case atmosphere
}

/// Procedural Trailhound road + car. Recording and onboarding share this DNA.
struct TrailhoundRoadDrivingScene<Overlay: View>: View {
    let time: TimeInterval
    var metrics: TrailhoundRoadSceneMetrics = .regular
    var palette: TrailhoundRoadScenePalette = .recording
    var isPaused: Bool = false
    var driveInProgress: CGFloat = 1
    var showsPauseBadge: Bool = false
    /// Side-profile SF Symbol fallback; default is the fixed right-facing car.
    var systemImage: String? = nil
    /// Pre-decoded vehicle thumb (app injects; no I/O on the animation clock).
    var vehiclePhoto: UIImage? = nil
    /// Symbol horizontal scale so the vehicle faces right (`-1` for left-facing SF side cars).
    var symbolScaleX: CGFloat = -1
    var allowsVerticalBounce: Bool = true
    @ViewBuilder var overlay: (_ layout: TrailhoundRoadSceneLayout) -> Overlay

    @Environment(\.colorScheme) private var colorScheme

    /// Lane band height used for car/dash layout (atmosphere has no filled road).
    private var laneBandHeight: CGFloat {
        palette == .atmosphere ? max(12, metrics.roadHeight * 0.45) : metrics.roadHeight
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let carSize = metrics.carSize
            let roadHeight = laneBandHeight
            let settledX = width * metrics.settledXFraction
            let startX = -carSize * 0.8
            let eased = TrailhoundRoadSceneMetrics.easeOutCubic(min(1, max(0, driveInProgress)))
            let carCenterX = startX + (settledX - startX) * eased
            let roadTop = height - roadHeight
            let carY = roadTop - carSize * 0.35
            let bounce: CGFloat = {
                guard allowsVerticalBounce, !isPaused else { return 0 }
                return sin(time * 8) * 1.2
            }()
            let carCenter = CGPoint(x: carCenterX, y: carY + bounce)
            let carOpacity = Double(0.35 + 0.65 * eased)
            let layout = TrailhoundRoadSceneLayout(
                size: geo.size,
                carCenter: carCenter,
                carSize: carSize,
                roadHeight: roadHeight,
                driveEased: eased,
                isPaused: isPaused
            )

            ZStack(alignment: .bottom) {
                if palette == .recording {
                    roadSurface(width: width, roadHeight: roadHeight)
                }
                laneMarkings(
                    width: width,
                    roadHeight: roadHeight,
                    carCenterX: carCenterX,
                    carSize: carSize
                )
                exhaustSmoke(
                    originX: carCenterX - carSize * 0.48,
                    originY: carY + carSize * 0.08,
                    strength: eased
                )
                carIcon(center: carCenter, size: carSize, opacity: carOpacity)

                if showsPauseBadge, isPaused {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: carSize * 0.65, weight: .semibold))
                        .foregroundStyle(.yellow.opacity(0.95))
                        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                        .position(x: carCenterX, y: carY)
                }

                overlay(layout)
            }
        }
    }

    private func roadSurface(width: CGFloat, roadHeight: CGFloat) -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(isPaused ? 0.16 : 0.22),
                        Color.black.opacity(isPaused ? 0.28 : 0.35)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(height: roadHeight)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.white.opacity(isPaused ? 0.2 : 0.35))
                    .frame(height: 2)
            }
    }

    private func laneMarkings(
        width: CGFloat,
        roadHeight: CGFloat,
        carCenterX: CGFloat,
        carSize: CGFloat
    ) -> some View {
        let dashWidth: CGFloat = palette == .atmosphere ? 18 : 22
        let dashSpacing: CGFloat = palette == .atmosphere ? 16 : 18
        let patternLength = dashWidth + dashSpacing
        let scrollSpeed: CGFloat = 90
        // `time` is already frozen by RoadSceneDriver when paused — keep last offset, don't snap to 0.
        let offset = -CGFloat(time.truncatingRemainder(dividingBy: Double(patternLength / scrollSpeed))) * scrollSpeed
        // +2 dashes on the left and +2 on the right vs the base fill count.
        let baseCount = max(0, Int(width / patternLength) + 6)
        let leadingExtra = 2
        let trailingExtra = 2
        let firstIndex = -2 - leadingExtra
        let dashCount = baseCount + trailingExtra
        let dashColor: Color = {
            switch palette {
            case .recording:
                return Color.white.opacity(isPaused ? 0.45 : 0.85)
            case .atmosphere:
                return colorScheme == .dark
                    ? Color.white.opacity(isPaused ? 0.28 : 0.42)
                    : TrailhoundBrandColors.brandBottom.opacity(isPaused ? 0.28 : 0.4)
            }
        }()
        let dashHeight: CGFloat = palette == .atmosphere ? 2.5 : 3
        // Symmetric gap under the car so left/right dash runs stay balanced.
        let carHalf = carSize * 0.58
        let carLeading = carCenterX - carHalf
        let carTrailing = carCenterX + carHalf

        return ZStack(alignment: .leading) {
            if dashCount > firstIndex {
                ForEach(firstIndex..<dashCount, id: \.self) { index in
                    let x = offset + CGFloat(index) * patternLength
                    let dashLeading = x
                    let dashTrailing = x + dashWidth
                    let underCar = palette == .atmosphere
                        && dashTrailing > carLeading
                        && dashLeading < carTrailing
                    if !underCar {
                        Capsule()
                            .fill(dashColor)
                            .frame(width: dashWidth, height: dashHeight)
                            .offset(x: x)
                    }
                }
            }
        }
        .frame(height: roadHeight, alignment: .center)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .offset(y: palette == .atmosphere ? -roadHeight * 0.15 : -roadHeight * 0.38)
        .mask {
            if palette == .atmosphere {
                // Symmetric soft fade so the stripe run reads centered with the car.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white, location: 0.08),
                        .init(color: .white, location: 0.92),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: roadHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                Rectangle()
                    .frame(height: roadHeight)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private func carIcon(center: CGPoint, size: CGFloat, opacity: Double) -> some View {
        let carColor: Color = {
            switch palette {
            case .recording:
                return .white.opacity(isPaused ? 0.75 : opacity)
            case .atmosphere:
                // Same accent as onboarding feature icons — blends into light/dark shells.
                return TrailhoundBrandColors.brandBottom.opacity(isPaused ? 0.7 : max(0.65, opacity))
            }
        }()
        let shadowColor: Color = palette == .atmosphere
            ? TrailhoundBrandColors.brandBottom.opacity(colorScheme == .dark ? 0.35 : 0.2)
            : Color.black.opacity(0.25)
        let shadowRadius: CGFloat = palette == .atmosphere ? 8 : 3
        // Photos read smaller than SF Symbols at the same point size — bump them up, no chrome.
        // Cap slightly above scene height so thumbs can grow (~+30%) without clipping to a tiny plate.
        let photoSize = min(size * 3.0, metrics.sceneHeight * 1.18)
        let markSize = vehiclePhoto == nil ? size : photoSize

        return Group {
            if let vehiclePhoto {
                Image(uiImage: vehiclePhoto)
                    .resizable()
                    .scaledToFit()
                    .frame(width: photoSize, height: photoSize)
                    .opacity(isPaused ? 0.75 : 1)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            } else {
                Image(systemName: systemImage ?? "car.side.fill")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(carColor)
                    .symbolRenderingMode(palette == .atmosphere ? .hierarchical : .monochrome)
                    // Face right — symbols only; never mirror a photo.
                    .scaleEffect(x: symbolScaleX, y: 1)
                    .shadow(color: shadowColor, radius: shadowRadius, y: 2)
            }
        }
        .frame(width: markSize, height: markSize)
        .position(x: center.x, y: center.y)
    }

    private func exhaustSmoke(originX: CGFloat, originY: CGFloat, strength: CGFloat) -> some View {
        Group {
            if !isPaused, strength > 0.2 {
                ZStack {
                    ForEach(0..<7, id: \.self) { index in
                        smokePuff(
                            originX: originX,
                            originY: originY,
                            index: index,
                            cycle: 1.1,
                            stagger: 0.16,
                            strength: strength
                        )
                    }
                }
            }
        }
    }

    private func smokePuff(
        originX: CGFloat,
        originY: CGFloat,
        index: Int,
        cycle: Double,
        stagger: Double,
        strength: CGFloat
    ) -> some View {
        let progress = (time + stagger * Double(index)).truncatingRemainder(dividingBy: cycle) / cycle
        let drift = CGFloat(progress)
        let size = 6 + drift * 14
        let x = originX - drift * 36 - CGFloat(index % 2) * 4
        let y = originY - drift * 22 + sin(progress * .pi) * 6
        let base = palette == .atmosphere ? 0.28 : 0.55
        let opacity = Double(1 - progress) * base * Double(strength)
        let smoke: Color = palette == .atmosphere
            ? TrailhoundBrandColors.brandBottom.opacity(opacity)
            : Color.white.opacity(opacity)

        return Circle()
            .fill(smoke)
            .frame(width: size, height: size)
            .blur(radius: 1.5 + drift * 2)
            .position(x: x, y: y)
    }
}

extension TrailhoundRoadDrivingScene where Overlay == EmptyView {
    init(
        time: TimeInterval,
        metrics: TrailhoundRoadSceneMetrics = .regular,
        palette: TrailhoundRoadScenePalette = .recording,
        isPaused: Bool = false,
        driveInProgress: CGFloat = 1,
        showsPauseBadge: Bool = false,
        systemImage: String? = nil,
        vehiclePhoto: UIImage? = nil,
        symbolScaleX: CGFloat = -1,
        allowsVerticalBounce: Bool = true
    ) {
        self.time = time
        self.metrics = metrics
        self.palette = palette
        self.isPaused = isPaused
        self.driveInProgress = driveInProgress
        self.showsPauseBadge = showsPauseBadge
        self.systemImage = systemImage
        self.vehiclePhoto = vehiclePhoto
        self.symbolScaleX = symbolScaleX
        self.allowsVerticalBounce = allowsVerticalBounce
        self.overlay = { _ in EmptyView() }
    }
}

private struct RoadSceneDriver<CarOverlay: View>: View {
    /// Live clock while animating; `nil` uses a frozen frame (no `TimelineView` tick).
    let liveTime: TimeInterval?
    let shouldAnimate: Bool
    let isPaused: Bool
    let metrics: TrailhoundRoadSceneMetrics
    let driveInProgress: CGFloat
    let showsPauseBadge: Bool
    var systemImage: String? = nil
    var vehiclePhoto: UIImage? = nil
    var symbolScaleX: CGFloat = -1
    var allowsVerticalBounce: Bool = true
    @ViewBuilder var carOverlay: (TrailhoundRoadSceneLayout) -> CarOverlay

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
            isPaused: isPaused,
            driveInProgress: driveInProgress,
            showsPauseBadge: showsPauseBadge,
            systemImage: systemImage,
            vehiclePhoto: vehiclePhoto,
            symbolScaleX: symbolScaleX,
            allowsVerticalBounce: allowsVerticalBounce,
            overlay: carOverlay
        )
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
