import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// Optional full-screen live follow while a trip is recording.
///
/// Presented from the trips list; does not own recording lifecycle. Open fades the map in
/// while the road vehicle mark flies into the nav puck. Close expands the HUD then rises.
struct LiveFollowMapView: View {
    var vehiclePhoto: UIImage?
    var vehicleSystemImage: String = "car.fill"
    /// Card + road-vehicle frames for close morph / open hero flight.
    var cardAnchor: RecordingCardAnchor
    var onClose: () -> Void
    var onStop: (RecordingCardAnchor) -> Void

    @Environment(TripRecordingService.self) private var recordingService
    @Environment(LocationService.self) private var locationService
    @Environment(NetworkMonitor.self) private var networkMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable private var settings = AppSettings.shared

    @State private var session = LiveFollowSession()
    @State private var isFollowing = true
    @State private var mapClarity: Double = 0
    @State private var chromeReveal: Double = 0
    /// 0 = road vehicle at list card; 1 = nav puck on the map.
    @State private var heroFlight: CGFloat = 0
    @State private var heroOpacity: Double = 1
    /// Keeps the SwiftUI hero mounted during the open handoff crossfade.
    @State private var showHeroOverlay = true
    @State private var puckRevealed = false
    @State private var mapMounted = false
    @State private var isClosing = false
    /// After open fade finishes — follow camera may advance from GPS.
    @State private var openSettled = false
    @State private var displaySegments: [LiveFollowPolylineSegment] = []
    @State private var lastBreadcrumbPointCount = -1
    @State private var hudAnchorBox = RecordingCardAnchorBox()
    @State private var displayLink = DisplayLinkClock()
    @State private var pausePinCoordinates: [CLLocationCoordinate2D] = []
    @State private var wasPaused = false
    @State private var idleLockHeld = false
    /// Local 2D/3D mirror — avoids rebuilding the MapKit host on every settings write.
    @State private var uses3DLocal = true

    private var uses3D: Bool { uses3DLocal }

    private var isPaused: Bool {
        recordingService.state == .paused
    }

    private var statusText: String {
        isPaused ? L10n.recordingPaused : L10n.recordingStarted
    }

    private var tipCoordinate: CLLocationCoordinate2D? {
        session.vehicleCoordinate
            ?? locationService.lastLocation?.coordinate
            ?? recordingService.liveBreadcrumbCoordinates.last
    }

    private var startPinCoordinate: CLLocationCoordinate2D? {
        recordingService.liveBreadcrumbCoordinates.first
    }

    private var tripStopCoordinates: [CLLocationCoordinate2D] {
        recordingService.liveStopCoordinates
    }

    private var mapPins: [LiveFollowMapPin] {
        LiveFollowMapPinBuilder.pins(
            startCoordinate: startPinCoordinate,
            pauseCoordinates: pausePinCoordinates,
            tripStopCoordinates: tripStopCoordinates
        )
    }

    /// Hero overlay while flying / crossfading onto the map puck.
    private var showHeroFlight: Bool {
        showHeroOverlay
    }

    /// `GeometryReader` under `.ignoresSafeArea()` reports zero insets — read the key window instead.
    private var windowSafeInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let inset = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets {
            return inset
        }
        return scenes.flatMap(\.windows).first?.safeAreaInsets ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }

    var body: some View {
        GeometryReader { geo in
            let safe = windowSafeInsets
            let topInset = max(geo.safeAreaInsets.top, safe.top)
            let bottomInset = max(geo.safeAreaInsets.bottom, safe.bottom)
            let containerGlobal = geo.frame(in: .global)
            let sourceGlobal = LiveFollowPresentation.sourceRect(
                from: cardAnchor,
                fallbackContainer: containerGlobal
            )
            let origin = containerGlobal.origin
            let heroSourceGlobal = LiveFollowPresentation.heroSourceRect(
                from: cardAnchor,
                cardFallback: sourceGlobal
            )
            let heroSourceLocal = heroSourceGlobal.offsetBy(dx: -origin.x, dy: -origin.y)
            let heroDest = LiveFollowPresentation.heroDestCenter(in: geo.size, uses3D: uses3D)
            let dimOpacity = mapMounted ? 0.42 * (1 - mapClarity) : 0.0

            ZStack(alignment: .topLeading) {
                // Transparent cover must still eat taps so the trips list underneath cannot scroll.
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())

                if mapMounted {
                    mapLayer
                        .ignoresSafeArea()
                        .opacity(mapClarity)

                    if isPaused {
                        pausedOverlay
                            .transition(.opacity)
                    }
                }

                Color.black.opacity(dimOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            // Chrome + hero above MapKit (Map often ignores sibling z-order).
            .overlay {
                ZStack {
                    settledChromeStack(topInset: topInset, bottomInset: bottomInset)

                    if showHeroFlight {
                        LiveFollowVehicleHero(
                            progress: heroFlight,
                            sourceLocal: heroSourceLocal,
                            destCenter: heroDest,
                            vehiclePhoto: vehiclePhoto,
                            vehicleSystemImage: vehicleSystemImage
                        )
                        .opacity(heroOpacity)
                        .allowsHitTesting(false)
                        .zIndex(40)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: isPaused)
        .statusBarHidden(false)
        .onAppear {
            uses3DLocal = settings.liveFollowMap3DEnabled
            retainIdleLock()
            wasPaused = isPaused
            runOpenSequence()
        }
        .onDisappear {
            stopDisplayLink()
            releaseIdleLock()
        }
        .onChange(of: mapMounted) { _, mounted in
            if mounted {
                startDisplayLink()
            } else {
                stopDisplayLink()
            }
        }
        .onChange(of: isFollowing) { _, value in
            session.isFollowing = value
        }
        .onChange(of: openSettled) { _, value in
            session.openSettled = value
        }
        .onChange(of: isClosing) { _, value in
            session.isClosing = value
        }
        .onChange(of: isPaused) { _, paused in
            session.isPaused = paused
            handlePauseChromeChange(paused)
        }
        .onChange(of: reduceMotion) { _, value in
            session.reduceMotion = value
        }
        .onChange(of: recordingService.state.isActiveSession) { _, isActive in
            if !isActive {
                // Parent clears the cover; skip reverse morph (list card is gone).
                onClose()
            }
        }
        .onChange(of: recordingService.liveBreadcrumbCoordinates.count) { _, count in
            guard mapMounted else { return }
            refreshDisplaySegments(force: count != lastBreadcrumbPointCount)
        }
        .onChange(of: settings.liveFollowMap3DEnabled) { _, enabled in
            guard mapMounted else { return }
            guard uses3DLocal != enabled else { return }
            uses3DLocal = enabled
            session.applyDimensionMode(enabled)
        }
        .accessibilityAddTraits(.isModal)
    }

    private func settledChromeStack(topInset: CGFloat, bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            topChrome
                .padding(.horizontal, GlassTokens.panelHorizontalInset)
                .padding(.top, topInset + 10)
                .opacity(chromeReveal)
                .zIndex(2)

            Spacer(minLength: 0)

            bottomHUD(useGlass: true)
                .containerRelativeFrame(
                    .horizontal,
                    count: 12,
                    span: 10,
                    spacing: 0,
                    alignment: .center
                )
                .padding(.bottom, LiveFollowPresentation.settledBottomPadding + bottomInset)
                .opacity(chromeReveal)
                .background {
                    GeometryReader { geo in
                        let frame = geo.frame(in: .global)
                        Color.clear
                            .onAppear { updateHUDAnchor(frame) }
                            .onChange(of: frame.origin.y) { _, _ in updateHUDAnchor(frame) }
                            .onChange(of: frame.size.width) { _, _ in updateHUDAnchor(frame) }
                            .onChange(of: frame.size.height) { _, _ in updateHUDAnchor(frame) }
                    }
                }
        }
    }

    private var mapLayer: some View {
        LiveFollowMapKitView(
            session: session,
            isFollowing: isFollowing && openSettled && !isClosing,
            interactionEnabled: !isPaused,
            segments: displaySegments,
            pins: mapPins,
            vehiclePhoto: vehiclePhoto,
            vehicleSystemImage: vehicleSystemImage,
            puckRevealed: puckRevealed,
            isMoving: !isPaused,
            onUserBreakFollow: {
                guard isFollowing else { return }
                isFollowing = false
            }
        )
    }

    /// Full-screen amber wash + centered pause callout. Pass-through so Resume/Stop stay tappable.
    private var pausedOverlay: some View {
        ZStack {
            Color.yellow.opacity(0.38)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.yellow, .black.opacity(0.85))
                Text(L10n.recordingPaused)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.yellow.opacity(0.75), lineWidth: 1.5)
                    }
            }
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.recordingPaused)
        }
        .allowsHitTesting(false)
    }

    private var topChrome: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: isPaused ? "pause.circle.fill" : "record.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isPaused ? Color.yellow : Color.red)
                    .contentTransition(.opacity)
                    .symbolEffect(
                        .pulse,
                        options: .repeating,
                        isActive: !isPaused && !reduceMotion && mapMounted
                    )
                Text(statusText)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassChrome(cornerRadius: 14)

            Spacer(minLength: 4)

            if !networkMonitor.isConnected {
                Text(L10n.tripMapOfflineHint)
                    .font(.caption2)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassChrome(cornerRadius: 14)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            GPSQualityBadge(quality: session.displayedGPSQuality, compact: true)
        }
    }

    /// 2D/3D, recenter, and close — white-on-blue chips matching the recording-card pills.
    private var mapToolsRail: some View {
        HStack(spacing: 10) {
            mapDimensionToggle

            Button {
                TrailhoundHaptics.selection()
                isFollowing = true
                session.isFollowing = true
                session.applyDimensionMode(uses3DLocal)
                if let location = locationService.lastLocation {
                    session.forceRecenter(location: location)
                }
            } label: {
                Image(systemName: isFollowing ? "location.north.line.fill" : "location.north.line")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(isFollowing ? 0.26 : 0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("recording.live_map.recenter"))

            Spacer(minLength: 8)

            Button {
                TrailhoundHaptics.selection()
                beginClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color(red: 0.52, green: 0.08, blue: 0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("recording.live_map.close"))
        }
        .accessibilityElement(children: .contain)
    }

    private var mapDimensionToggle: some View {
        HStack(spacing: 0) {
            mapDimensionSegment(title: "2D", selected: !uses3DLocal) {
                setDimensionMode(false)
            }
            mapDimensionSegment(title: "3D", selected: uses3DLocal) {
                setDimensionMode(true)
            }
        }
        .padding(3)
        .frame(height: 44)
        .background(.white.opacity(0.12), in: Capsule())
    }

    private func mapDimensionSegment(
        title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard !selected else { return }
            TrailhoundHaptics.selection()
            action()
        } label: {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(selected ? 1 : 0.62))
                .frame(width: 44, height: 38)
                .background {
                    if selected {
                        Capsule().fill(.white.opacity(0.28))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            title == "2D"
                ? L10n.string("recording.live_map.switch_2d")
                : L10n.string("recording.live_map.switch_3d")
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func setDimensionMode(_ enabled3D: Bool) {
        uses3DLocal = enabled3D
        settings.liveFollowMap3DEnabled = enabled3D
        session.applyDimensionMode(enabled3D)
    }

    private func bottomHUD(useGlass: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            mapToolsRail

            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(height: 1)

            ActiveTripLiveStats(compact: true)

            HStack(spacing: 10) {
                Button {
                    let toggle = {
                        if isPaused {
                            recordingService.resumeRecording()
                        } else {
                            recordingService.pauseRecording()
                        }
                    }
                    if reduceMotion {
                        toggle()
                    } else {
                        withAnimation(TrailhoundMotion.recordingToggle) {
                            toggle()
                        }
                    }
                } label: {
                    RecordingActionLabel(
                        title: isPaused ? L10n.resume : L10n.pause,
                        systemImage: isPaused ? "play.fill" : "pause.fill"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(SoftPressBorderedButtonStyle(reduceMotion: reduceMotion))
                .controlSize(.regular)
                .tint(.white)

                Button(role: .destructive) {
                    // No reverse morph — parent dismisses instantly then plays end credits.
                    onStop(hudAnchorBox.value.width > 0 ? hudAnchorBox.value : cardAnchor)
                } label: {
                    RecordingActionLabel(title: L10n.stop, systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(.red)
            }
        }
        .padding(14)
        // Width fills the HUD slot; height stays intrinsic so settled layout does not
        // stretch into the Spacer (morphing phase applies an explicit height separately).
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            if useGlass {
                RecordingCardStyle.glassSurface(isPaused: isPaused)
            } else {
                RecordingCardStyle.listSurface(isPaused: isPaused)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: RecordingCardStyle.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: RecordingCardStyle.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
        }
    }

    @MainActor
    private func runOpenSequence() {
        // Lock camera to the follow pose BEFORE Map appears — never fade in from .automatic.
        openSettled = false
        mapClarity = 0
        chromeReveal = 0
        heroFlight = 0
        heroOpacity = 1
        showHeroOverlay = true
        puckRevealed = false
        prepareMapMount()

        if reduceMotion {
            mapClarity = 1
            chromeReveal = 1
            heroFlight = 1
            heroOpacity = 0
            showHeroOverlay = false
            puckRevealed = true
            openSettled = true
            return
        }

        // One shared fade for map + hero so they stay synchronized (tiles can catch up underneath).
        Task { @MainActor in
            // Let MapKit paint the first frame at the final camera while still invisible.
            try? await Task.sleep(for: .milliseconds(50))
            guard !isClosing else { return }
            withAnimation(
                TrailhoundMotion.liveFollowReveal,
                completionCriteria: .logicallyComplete
            ) {
                mapClarity = 1
                chromeReveal = 1
                heroFlight = 1
            } completion: {
                guard !self.isClosing else { return }
                // Reveal map puck under the hero, then fade the hero out in place (no teleport).
                self.puckRevealed = true
                self.openSettled = true
                withAnimation(.easeOut(duration: 0.28)) {
                    self.heroOpacity = 0
                }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !self.isClosing else { return }
                    self.showHeroOverlay = false
                }
            }
        }
    }

    /// Inserts the map tree after the follow camera is already written (no world→local fly-in).
    @MainActor
    private func prepareMapMount() {
        guard !isClosing, !mapMounted else { return }
        bootstrapCamera()
        refreshDisplaySegments(force: true)
        mapMounted = true
    }

    @MainActor
    private func beginClose() {
        guard !isClosing else { return }
        isClosing = true
        stopDisplayLink()
        releaseIdleLock()
        // Reverse of open: hero at puck landing spot → fly back to list card.
        showHeroOverlay = true
        heroOpacity = 1
        heroFlight = 1
        puckRevealed = false

        if reduceMotion {
            mapClarity = 0
            chromeReveal = 0
            heroFlight = 0
            mapMounted = false
            onClose()
            return
        }

        withAnimation(
            TrailhoundMotion.liveFollowReveal,
            completionCriteria: .logicallyComplete
        ) {
            mapClarity = 0
            chromeReveal = 0
            heroFlight = 0
        } completion: {
            self.mapMounted = false
            self.onClose()
        }
    }

    private func updateHUDAnchor(_ frame: CGRect) {
        guard frame.width > 0 else { return }
        hudAnchorBox.value = RecordingCardAnchor(
            minX: frame.minX,
            minY: frame.minY,
            width: frame.width,
            height: frame.height
        )
    }

    private func bootstrapCamera() {
        session.locationService = locationService
        session.isPaused = isPaused
        session.isFollowing = isFollowing
        session.openSettled = openSettled
        session.isClosing = isClosing
        session.bootstrap(
            uses3D: uses3D,
            reduceMotion: reduceMotion,
            location: locationService.lastLocation,
            tip: recordingService.liveBreadcrumbCoordinates.last
        )
        session.setDisplayedGPSQuality(locationService.gpsQuality)
    }

    @MainActor
    private func startDisplayLink() {
        syncSessionFlags()
        displayLink.onTick = { [session] dt in
            session.handleDisplayTick(dt: dt)
        }
        displayLink.start()
    }

    @MainActor
    private func stopDisplayLink() {
        displayLink.stop()
        displayLink.onTick = nil
    }

    private func syncSessionFlags() {
        session.locationService = locationService
        session.isPaused = isPaused
        session.isFollowing = isFollowing
        session.openSettled = openSettled
        session.isClosing = isClosing
        session.uses3D = uses3D
        session.reduceMotion = reduceMotion
    }

    private func handlePauseChromeChange(_ paused: Bool) {
        defer { wasPaused = paused }
        guard paused, !wasPaused else { return }
        if let coordinate = tipCoordinate {
            pausePinCoordinates.append(coordinate)
        }
    }

    private func retainIdleLock() {
        guard !idleLockHeld else { return }
        ScreenIdleLock.shared.retain()
        idleLockHeld = true
    }

    private func releaseIdleLock() {
        guard idleLockHeld else { return }
        ScreenIdleLock.shared.release()
        idleLockHeld = false
    }

    private func refreshDisplaySegments(force: Bool) {
        let count = recordingService.liveBreadcrumbCoordinates.count
        guard force || count != lastBreadcrumbPointCount else { return }
        lastBreadcrumbPointCount = count
        let live = recordingService.liveBreadcrumbSegments
        displaySegments = Self.polylineSegments(from: live)
    }

    /// Apple Maps navigation blue — traveled breadcrumb.
    static let routeBlue = Color(red: 0.28, green: 0.62, blue: 1.0)
    /// Matches MapKit puck plate (~50% transparent).
    static let puckPlateBlue = Color(red: 0.28, green: 0.62, blue: 1.0).opacity(0.5)

    /// Decimate each gap-split live segment for MapKit cost; never rewrite stored points.
    static func polylineSegments(
        from liveSegments: [[CLLocationCoordinate2D]]
    ) -> [LiveFollowPolylineSegment] {
        var result: [LiveFollowPolylineSegment] = []
        for (index, coords) in liveSegments.enumerated() {
            guard coords.count >= 2 else { continue }
            let samples = coords.enumerated().map { offset, coordinate in
                RouteSample(
                    coordinate: coordinate,
                    timestamp: Date(timeIntervalSince1970: TimeInterval(offset)),
                    speedMps: nil
                )
            }
            let pieces = RouteDisplayPath.displaySegmentCoordinates(samples: samples)
            for (pieceIndex, piece) in pieces.enumerated() where piece.count >= 2 {
                result.append(
                    LiveFollowPolylineSegment(
                        id: "live-\(index)-\(pieceIndex)",
                        coordinates: piece
                    )
                )
            }
        }
        return result
    }
}

/// Open hero: road vehicle mark flies from the recording card into the nav-puck look.
///
/// Arc placement uses `LiveFollowHeroArcPlacement` (`AnimatableModifier`) so SwiftUI
/// samples the Bezier each frame — a View-level `Animatable` conformance trips Swift 6
/// main-actor isolation with `UIImage`.
struct LiveFollowVehicleHero: View {
    var progress: CGFloat
    var sourceLocal: CGRect
    var destCenter: CGPoint
    var vehiclePhoto: UIImage?
    var vehicleSystemImage: String

    private let puckCircle: CGFloat = 56
    private let chevronSize = CGSize(width: 52, height: 38)
    private let chevronOverlap: CGFloat = 18

    var body: some View {
        let t = LiveFollowPresentation.clampedProgress(progress)
        let side = LiveFollowPresentation.lerp(
            max(min(sourceLocal.width, sourceLocal.height) * 0.55, 36),
            puckCircle,
            t
        )
        let puckChrome = t
        let frameHeight = side + chevronSize.height - chevronOverlap * puckChrome + 14
        let frameWidth = max(side, chevronSize.width) + 24

        ZStack(alignment: .top) {
            Circle()
                .fill(Color.black.opacity(0.22 * puckChrome))
                .frame(width: side + 10, height: side + 10)

            ZStack {
                Circle()
                    .fill(LiveFollowMapView.puckPlateBlue)

                if let vehiclePhoto {
                    Image(uiImage: vehiclePhoto)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: vehicleSystemImage)
                        .font(.system(size: side * 0.38, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: side * (1 - 0.12 * puckChrome), height: side * (1 - 0.12 * puckChrome))
            .clipShape(Circle())
            .padding(LiveFollowPresentation.lerp(0, 8, t))
            .background {
                Circle()
                    .fill(LiveFollowMapView.puckPlateBlue)
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.35 + 0.65 * puckChrome), lineWidth: 2 + 3 * puckChrome)
            }
            .frame(width: side, height: side)

            LiveFollowNavChevron()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.42, green: 0.76, blue: 1.0),
                            LiveFollowMapView.routeBlue,
                            Color(red: 0.12, green: 0.48, blue: 0.95)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    LiveFollowNavChevron()
                        .stroke(
                            .white,
                            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                        )
                }
                .frame(width: chevronSize.width, height: chevronSize.height)
                .offset(y: side - chevronOverlap * puckChrome)
                .opacity(puckChrome)
                .scaleEffect(0.7 + 0.3 * puckChrome, anchor: .top)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .frame(width: frameWidth, height: frameHeight)
        .modifier(
            LiveFollowHeroArcPlacement(
                progress: progress,
                from: CGPoint(x: sourceLocal.midX, y: sourceLocal.midY),
                to: destCenter,
                sourceSide: max(min(sourceLocal.width, sourceLocal.height) * 0.55, 36),
                puckSide: puckCircle,
                chevronHeight: chevronSize.height,
                chevronOverlap: chevronOverlap
            )
        )
        .accessibilityHidden(true)
    }
}

/// Samples the Bezier path as `progress` animates (avoids straight-line `.position` lerp).
private struct LiveFollowHeroArcPlacement: AnimatableModifier {
    var progress: CGFloat
    var from: CGPoint
    var to: CGPoint
    var sourceSide: CGFloat
    var puckSide: CGFloat
    var chevronHeight: CGFloat
    var chevronOverlap: CGFloat

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let t = LiveFollowPresentation.clampedProgress(progress)
        let circleCenter = LiveFollowPresentation.heroFlightPoint(from: from, to: to, progress: t)
        let side = LiveFollowPresentation.lerp(sourceSide, puckSide, t)
        let frameHeight = side + chevronHeight - chevronOverlap * t + 14
        let frameCenterY = circleCenter.y + (frameHeight / 2 - side / 2)
        content.position(x: circleCenter.x, y: frameCenterY)
    }
}

/// Circle photo badge with a filled heading chevron overlapping the bottom — matches the live-map puck.
struct LiveFollowPuckMark: View {
    var vehiclePhoto: UIImage?
    var vehicleSystemImage: String
    var isMoving: Bool
    var reduceMotion: Bool

    private let circleSize: CGFloat = 56
    private let photoBorder: CGFloat = 5
    /// Air between the photo and the inner edge of the white ring.
    private let photoGap: CGFloat = 3
    private let chevronSize = CGSize(width: 52, height: 38)
    /// How far the chevron sits up onto the circle.
    private let chevronOverlap: CGFloat = 18

    @State private var pulseOn = false

    var body: some View {
        ZStack(alignment: .top) {
            if isMoving, !reduceMotion {
                SoftPulseRing(
                    color: UIColor(red: 0.28, green: 0.62, blue: 1.0, alpha: 1),
                    isActive: true,
                    reduceMotion: false
                )
                .frame(width: circleSize + 22, height: circleSize + 22)
                .offset(y: -11)
                .allowsHitTesting(false)
            }

            ZStack(alignment: .top) {
                photoBadge
                    .frame(width: circleSize, height: circleSize)

                filledChevron
                    .frame(width: chevronSize.width, height: chevronSize.height)
                    .offset(y: circleSize - chevronOverlap)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.36), radius: 6, y: 3)
        }
        .frame(
            width: max(circleSize, chevronSize.width) + 24,
            height: circleSize + chevronSize.height - chevronOverlap + 14
        )
        .scaleEffect(pulseOn ? 1.03 : 1)
        .offset(y: -circleSize / 2 + 8)
        .onAppear { syncPulse() }
        .onChange(of: isMoving) { _, _ in syncPulse() }
        .onChange(of: reduceMotion) { _, _ in syncPulse() }
        .accessibilityHidden(true)
    }

    private func syncPulse() {
        if isMoving, !reduceMotion {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulseOn = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                pulseOn = false
            }
        }
    }

    private var filledChevron: some View {
        LiveFollowNavChevron()
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.42, green: 0.76, blue: 1.0),
                        LiveFollowMapView.routeBlue,
                        Color(red: 0.12, green: 0.48, blue: 0.95)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                LiveFollowNavChevron()
                    .stroke(
                        .white,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                    )
            }
    }

    private var photoBadge: some View {
        ZStack {
            Circle()
                .fill(LiveFollowMapView.puckPlateBlue)

            photoContent
                .padding(photoBorder + photoGap)
                .clipShape(Circle())

            Circle()
                .strokeBorder(.white, lineWidth: photoBorder)
        }
    }

    @ViewBuilder
    private var photoContent: some View {
        if let vehiclePhoto {
            Image(uiImage: vehiclePhoto)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: vehicleSystemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// GPS puck: filled arrow pointing up, shallow notch at the bottom.
private struct LiveFollowNavChevron: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let points = [
            CGPoint(x: w * 0.50, y: h * 0.04),
            CGPoint(x: w * 0.97, y: h * 0.92),
            CGPoint(x: w * 0.50, y: h * 0.72),
            CGPoint(x: w * 0.03, y: h * 0.92)
        ]
        let radius = min(w, h) * 0.12
        let cg = CGMutablePath()
        let last = points[points.count - 1]
        let first = points[0]
        cg.move(to: CGPoint(x: (last.x + first.x) / 2, y: (last.y + first.y) / 2))
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            cg.addArc(tangent1End: current, tangent2End: next, radius: radius)
        }
        cg.closeSubpath()
        return Path(cg)
    }
}

struct LiveFollowPolylineSegment: Identifiable {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
}
