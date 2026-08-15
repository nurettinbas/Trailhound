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

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var followCamera = LiveFollowCamera()
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
    /// After open fade finishes — only then may follow-camera writes animate.
    @State private var openSettled = false
    @State private var displaySegments: [LiveFollowPolylineSegment] = []
    @State private var lastBreadcrumbPointCount = -1
    @State private var displayedGPSQuality: LocationService.GPSQuality = .lost
    /// Suppresses follow-break while we write the camera ourselves.
    @State private var ignoreNextCameraChange = false
    @State private var hudAnchorBox = RecordingCardAnchorBox()

    private var isPaused: Bool {
        recordingService.state == .paused
    }

    private var uses3D: Bool {
        settings.liveFollowMap3DEnabled
    }

    private var statusText: String {
        isPaused ? L10n.recordingPaused : L10n.recordingStarted
    }

    private var tipCoordinate: CLLocationCoordinate2D? {
        followCamera.center
            ?? locationService.lastLocation?.coordinate
            ?? recordingService.liveBreadcrumbCoordinates.last
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
            runOpenSequence()
        }
        .task(id: mapMounted) {
            guard mapMounted else { return }
            await runFollowLoop()
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
            followCamera.uses3D = enabled
            if isFollowing {
                applyCamera(animated: true)
            }
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

            trailingControls
                .padding(.trailing, GlassTokens.panelHorizontalInset)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .opacity(chromeReveal)

            bottomHUD(useGlass: true)
                .containerRelativeFrame(
                    .horizontal,
                    count: 12,
                    span: 8,
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
        Map(position: $cameraPosition, interactionModes: isPaused ? [] : .all) {
            ForEach(displaySegments) { segment in
                // Apple Maps–style traveled path: soft halo + solid blue route.
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(
                        Self.routeBlue.opacity(0.35),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round)
                    )
                    .mapOverlayLevel(level: .aboveRoads)
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(
                        Self.routeBlue,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                    )
                    .mapOverlayLevel(level: .aboveRoads)
            }

            if let tip = tipCoordinate, puckRevealed {
                // Empty title — MapKit must not draw “Current position” under the puck.
                // Hidden until the open hero flight lands.
                Annotation("", coordinate: tip, anchor: .center) {
                    LiveFollowPuckMark(
                        vehiclePhoto: vehiclePhoto,
                        vehicleSystemImage: vehicleSystemImage,
                        isMoving: !isPaused,
                        reduceMotion: reduceMotion
                    )
                    .accessibilityLabel(L10n.string("recording.live_map.vehicle"))
                }
            }
        }
        .mapStyle(
            .standard(elevation: uses3D ? .realistic : .flat)
        )
        .mapControls {
            // Empty — we own chrome; avoid system compass / scale crowding the HUD.
        }
        .onMapCameraChange(frequency: .onEnd) { _ in
            if ignoreNextCameraChange {
                ignoreNextCameraChange = false
                return
            }
            guard isFollowing else { return }
            isFollowing = false
        }
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
            Button {
                TrailhoundHaptics.selection()
                beginClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("recording.live_map.close"))

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

            GPSQualityBadge(quality: displayedGPSQuality, compact: true)
        }
    }

    private var trailingControls: some View {
        VStack(spacing: 10) {
            Button {
                TrailhoundHaptics.selection()
                settings.liveFollowMap3DEnabled.toggle()
            } label: {
                // Label = mode you switch into (Maps-style), not the current mode.
                Text(uses3D ? "2D" : "3D")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(TrailhoundBrandColors.brandBottom)
                    .frame(width: 44, height: 44)
                    .glassChrome(cornerRadius: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                uses3D
                    ? L10n.string("recording.live_map.switch_2d")
                    : L10n.string("recording.live_map.switch_3d")
            )
            .accessibilityValue(uses3D ? "3D" : "2D")

            if !isFollowing {
                Button {
                    TrailhoundHaptics.selection()
                    isFollowing = true
                    followCamera.uses3D = uses3D
                    if let location = locationService.lastLocation {
                        followCamera.forceRecenter(location: location)
                        applyCamera(animated: true)
                    }
                } label: {
                    Image(systemName: "location.north.line.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(TrailhoundBrandColors.brandBottom)
                        .frame(width: 44, height: 44)
                        .glassChrome(cornerRadius: 22)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("recording.live_map.recenter"))
                .transition(TrailhoundMotion.softRiseFromBottomTransition)
            }
        }
        .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: isFollowing)
    }

    private func bottomHUD(useGlass: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
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
        followCamera.uses3D = uses3D
        bootstrapCamera()
        refreshDisplaySegments(force: true)
        mapMounted = true
    }

    @MainActor
    private func beginClose() {
        guard !isClosing else { return }
        isClosing = true
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
        followCamera.uses3D = uses3D
        if let location = locationService.lastLocation {
            _ = followCamera.update(
                location: location,
                isPaused: isPaused,
                now: Date()
            )
            // First frame should show immediately even if sampler would wait.
            followCamera.forceRecenter(location: location)
            applyCamera(animated: false)
        } else if let tip = recordingService.liveBreadcrumbCoordinates.last {
            writeCamera(
                MapCamera(
                    centerCoordinate: tip,
                    distance: uses3D ? LiveFollowCamera.distance3D : LiveFollowCamera.distance2D,
                    heading: 0,
                    pitch: uses3D ? LiveFollowCamera.pitch3D : LiveFollowCamera.pitch2D
                ),
                animated: false
            )
        }
        displayedGPSQuality = locationService.gpsQuality
    }

    @MainActor
    private func runFollowLoop() async {
        while !Task.isCancelled, mapMounted {
            displayedGPSQuality = locationService.gpsQuality
            followCamera.uses3D = uses3D
            if isFollowing, let location = locationService.lastLocation {
                let changed = followCamera.update(
                    location: location,
                    isPaused: isPaused,
                    now: Date()
                )
                if changed {
                    // No camera animation during open fade — that reads as a world fly-in.
                    applyCamera(animated: openSettled && !isClosing)
                }
            }
            // Prefer live segment count — path must grow with the drive, not only camera ticks.
            refreshDisplaySegments(force: false)
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    private func applyCamera(animated: Bool) {
        guard let pose = followCamera.pose else { return }
        writeCamera(
            MapCamera(
                centerCoordinate: pose.center,
                distance: pose.distanceMeters,
                heading: pose.headingDegrees,
                pitch: pose.pitchDegrees
            ),
            animated: animated
        )
    }

    private func writeCamera(_ camera: MapCamera, animated: Bool) {
        ignoreNextCameraChange = true
        if animated, !reduceMotion, openSettled, !isClosing {
            withAnimation(.easeOut(duration: 0.28)) {
                cameraPosition = .camera(camera)
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                cameraPosition = .camera(camera)
            }
        }
    }

    private func refreshDisplaySegments(force: Bool) {
        let count = recordingService.liveBreadcrumbCoordinates.count
        guard force || count != lastBreadcrumbPointCount else { return }
        lastBreadcrumbPointCount = count
        let live = recordingService.liveBreadcrumbSegments
        displaySegments = Self.polylineSegments(from: live)
    }

    /// Apple Maps navigation blue — traveled breadcrumb.
    static let routeBlue = Color(red: 0.05, green: 0.48, blue: 1.0)

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
                    .fill(LiveFollowMapView.routeBlue)

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
                    .fill(LiveFollowMapView.routeBlue)
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
                            Color(red: 0.32, green: 0.70, blue: 1.0),
                            LiveFollowMapView.routeBlue,
                            Color(red: 0.04, green: 0.36, blue: 0.90)
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
                    color: UIColor(red: 0.05, green: 0.48, blue: 1.0, alpha: 1),
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
                        Color(red: 0.32, green: 0.70, blue: 1.0),
                        LiveFollowMapView.routeBlue,
                        Color(red: 0.04, green: 0.36, blue: 0.90)
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
                .fill(LiveFollowMapView.routeBlue)

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
