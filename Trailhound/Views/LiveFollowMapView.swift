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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
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
    /// MapKit puck alpha — crossfades with `heroOpacity` at handoff.
    @State private var puckAlpha: CGFloat = 1
    @State private var puckFadeToken = 0
    /// Map-projected puck circle center (overlay-local). Locked once before the open flight.
    @State private var projectedHeroDest: CGPoint?
    @State private var lockProjectedHeroDest = false
    @State private var mapMounted = false
    @State private var isClosing = false
    /// After open handoff finishes — MapKit puck pulse / chrome settle. Follow camera
    /// already runs during the hero flight so the landing cannot drift at speed.
    @State private var openSettled = false
    @State private var hudAnchorBox = RecordingCardAnchorBox()
    @State private var displayLink = DisplayLinkClock()
    @State private var pausePinCoordinates: [CLLocationCoordinate2D] = []
    @State private var wasPaused = false
    @State private var idleLockHeld = false
    /// Local 2D/3D mirror — avoids rebuilding the MapKit host on every settings write.
    @State private var uses3DLocal = true
    /// Bumped to ask MapKit to fit start + traveled path + puck (north-up 2D).
    @State private var overviewRequestToken = 0
    @State private var recenterRequestToken = 0
    /// First recorded breadcrumb — kept for the cover's lifetime so the start flag
    /// cannot vanish if the live array is briefly empty.
    @State private var latchedStartCoordinate: CLLocationCoordinate2D?

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
        // Read the fallback only when needed — touching `lastLocation` here would
        // subscribe the whole body to every GPS fix.
        if let latched = latchedStartCoordinate { return latched }
        return LiveFollowMapPinBuilder.resolvedStartCoordinate(
            latched: nil,
            breadcrumbStart: recordingService.liveBreadcrumbCoordinates.first,
            fallback: locationService.lastLocation?.coordinate
        )
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
            let heroDest = projectedHeroDest
                ?? LiveFollowPresentation.heroDestCenter(in: geo.size, uses3D: uses3D)
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
                            vehicleSystemImage: vehicleSystemImage,
                            plateColor: liveFollowPlateColor,
                            chevronColors: liveFollowChevronColors
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
            latchStartCoordinateIfNeeded()
            retainIdleLock()
            wasPaused = isPaused
            runOpenSequence()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1_800))
                guard !isClosing else { return }
                forceOpenSettledIfNeeded()
            }
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
        LiveFollowMapKitView(
            session: session,
            isFollowing: isFollowing && !isClosing,
            isPaused: isPaused,
            overviewRequestToken: overviewRequestToken,
            recenterRequestToken: recenterRequestToken,
            pins: mapPins,
            vehiclePhoto: vehiclePhoto,
            vehicleSystemImage: vehicleSystemImage,
            puckRevealed: puckRevealed,
            puckAlpha: puckAlpha,
            puckFadeToken: puckFadeToken,
            isMoving: openSettled && !isPaused,
            onUserBreakFollow: {
                guard !isPaused, isFollowing else { return }
                isFollowing = false
                session.isFollowing = false
            },
            onPuckCircleScreenPoint: { point in
                guard !lockProjectedHeroDest else { return }
                Task { @MainActor in
                    guard !self.lockProjectedHeroDest else { return }
                    if self.projectedHeroDest == nil {
                        self.projectedHeroDest = point
                    } else if let current = self.projectedHeroDest,
                              abs(current.x - point.x) > 0.5
                                || abs(current.y - point.y) > 0.5
                    {
                        self.projectedHeroDest = point
                    }
                }
            },
            routeStrokeColor: LiveFollowRouteStrokeStyle.solidColor(
                for: shellPalette,
                scheme: colorScheme
            ),
            puckPlateColor: UIColor(liveFollowPlateColor),
            puckChevronColors: liveFollowChevronColors.map { UIColor($0) },
            themeSignature: "\(shellPalette.rawValue)-\(colorScheme == .dark ? "d" : "l")"
        )
    }

    /// Full-screen wash + centered pause callout. Pass-through so Resume/Stop stay tappable.
    private var pausedOverlay: some View {
        ZStack {
            Color.orange.opacity(0.16)
                .ignoresSafeArea()

            pauseStatusChip(font: .title3.weight(.bold), iconSize: 22, horizontal: 18, vertical: 10)
                .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        }
        .allowsHitTesting(false)
    }

    /// Opaque amber + white type — glass + `.primary` washes out on a light map.
    private func pauseStatusChip(
        font: Font,
        iconSize: CGFloat,
        horizontal: CGFloat,
        vertical: CGFloat
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: iconSize, weight: .semibold))
            Text(L10n.recordingPaused)
                .font(font)
                .multilineTextAlignment(.center)
                .lineLimit(1)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, horizontal)
        .padding(.vertical, vertical)
        .background(TrailhoundBrandColors.paused, in: Capsule())
        .compositingGroup()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.recordingPaused)
    }

    private var topChrome: some View {
        HStack(spacing: 8) {
            if isPaused {
                pauseStatusChip(font: .caption.weight(.bold), iconSize: 13, horizontal: 8, vertical: 6)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "record.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.red)
                        .symbolEffect(
                            .pulse,
                            options: .repeating,
                            isActive: !reduceMotion && mapMounted
                        )
                    Text(statusText)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .glassChrome(cornerRadius: 14)
            }

            Spacer(minLength: 4)

            if !networkMonitor.isConnected {
                Text(L10n.tripMapOfflineHint)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .glassChrome(cornerRadius: 14)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            GPSQualityBadge(quality: session.displayedGPSQuality, compact: true)
        }
    }

    /// 2D/3D, overview/follow switch, and close — chips on the palette-tinted recording HUD.
    private var mapToolsRail: some View {
        HStack(spacing: 8) {
            mapDimensionToggle
                .disabled(isPaused)
                .opacity(isPaused ? 0.38 : 1)
                .allowsHitTesting(!isPaused)
            mapFollowToggle
                .disabled(isPaused)
                .opacity(isPaused ? 0.38 : 1)
                .allowsHitTesting(!isPaused)

            Spacer(minLength: 8)

            Button {
                TrailhoundHaptics.selection()
                beginClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 33, height: 33)
                    .background(GlassSemantic.notificationBadge, in: Capsule())
                    .compositingGroup()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("recording.live_map.close"))
        }
        .accessibilityElement(children: .contain)
    }

    private var mapDimensionToggle: some View {
        mapCapsuleToggle {
            mapDimensionSegment(title: "2D", selected: !uses3DLocal) {
                setDimensionMode(false)
            }
            mapDimensionSegment(title: "3D", selected: uses3DLocal) {
                setDimensionMode(true)
            }
        }
    }

    /// Overview vs heading-follow — same capsule switch as 2D/3D.
    private var mapFollowToggle: some View {
        mapCapsuleToggle {
            mapIconSegment(
                systemName: "arrow.up.left.and.arrow.down.right",
                selected: !isFollowing,
                ignoreIfSelected: false,
                accessibilityLabel: L10n.string("recording.live_map.overview")
            ) {
                requestOverview()
            }
            mapIconSegment(
                systemName: isFollowing ? "location.north.line.fill" : "location.north.line",
                selected: isFollowing,
                ignoreIfSelected: true,
                accessibilityLabel: L10n.string("recording.live_map.recenter")
            ) {
                requestRecenter()
            }
        }
    }

    private func mapCapsuleToggle<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0, content: content)
            .padding(2)
            .frame(height: 33)
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
                .font(.caption.weight(.bold))
                .foregroundStyle(selected ? Color.white : shellPalette.chromeColor(for: .light))
                .frame(width: 33, height: 29)
                .background {
                    if selected {
                        Capsule().fill(liveFollowPlateColor.opacity(0.45))
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

    private func mapIconSegment(
        systemName: String,
        selected: Bool,
        ignoreIfSelected: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            if ignoreIfSelected, selected { return }
            TrailhoundHaptics.selection()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? Color.white : shellPalette.chromeColor(for: .light))
                .frame(width: 33, height: 29)
                .background {
                    if selected {
                        Capsule().fill(liveFollowPlateColor.opacity(0.45))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func setDimensionMode(_ enabled3D: Bool) {
        uses3DLocal = enabled3D
        settings.liveFollowMap3DEnabled = enabled3D
        session.applyDimensionMode(enabled3D)
    }

    private func requestOverview() {
        isFollowing = false
        session.isFollowing = false
        overviewRequestToken += 1
    }

    private func requestRecenter() {
        isFollowing = true
        session.isFollowing = true
        session.applyDimensionMode(uses3DLocal)
        recenterRequestToken += 1
    }

    private func bottomHUD(useGlass: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            mapToolsRail

            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(height: 1)

            ActiveTripLiveStats(compact: true)

            HStack(spacing: 8) {
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
                        systemImage: isPaused ? "play.fill" : "pause.fill",
                        compact: true
                    )
                }
                .buttonStyle(SoftPressBorderedButtonStyle(reduceMotion: reduceMotion))
                .controlSize(.small)
                .tint(.white)
                .frame(maxWidth: .infinity, minHeight: 34)

                Button(role: .destructive) {
                    // No reverse morph — parent dismisses instantly then plays end credits.
                    onStop(hudAnchorBox.value.width > 0 ? hudAnchorBox.value : cardAnchor)
                } label: {
                    RecordingActionLabel(title: L10n.stop, systemImage: "stop.fill", compact: true)
                }
                .trailhoundDestructiveButton()
                .controlSize(.small)
                .frame(maxWidth: .infinity, minHeight: 34)
            }
        }
        .padding(10)
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
        puckAlpha = 1
        projectedHeroDest = nil
        lockProjectedHeroDest = false
        prepareMapMount()

        if reduceMotion {
            mapClarity = 1
            chromeReveal = 1
            heroFlight = 1
            heroOpacity = 0
            showHeroOverlay = false
            puckAlpha = 1
            puckRevealed = true
            openSettled = true
            lockProjectedHeroDest = true
            return
        }

        // One shared fade for map + hero so they stay synchronized (tiles can catch up underneath).
        Task { @MainActor in
            // Let MapKit paint the first frame at the final camera while still invisible,
            // and publish a projected landing pixel for the hero arc.
            try? await Task.sleep(for: .milliseconds(50))
            guard !isClosing else { return }
            try? await Task.sleep(for: .milliseconds(16))
            guard !isClosing else { return }
            lockProjectedHeroDest = true
            withAnimation(
                TrailhoundMotion.liveFollowReveal,
                completionCriteria: .logicallyComplete
            ) {
                mapClarity = 1
                chromeReveal = 1
                heroFlight = 1
            } completion: {
                guard !self.isClosing else { return }
                Task { @MainActor in
                    await self.runOpenHandoff()
                }
            }
        }
    }

    /// Reveal MapKit puck under the hero and crossfade. Follow camera is already live.
    @MainActor
    private func runOpenHandoff() async {
        guard !isClosing else { return }
        // Add puck invisible under the hero; give MapKit a beat to materialize the view.
        puckAlpha = 0
        puckRevealed = true
        try? await Task.sleep(for: .milliseconds(32))
        guard !isClosing else { return }

        puckFadeToken += 1
        puckAlpha = 1
        withAnimation(
            TrailhoundMotion.liveFollowHandoff,
            completionCriteria: .logicallyComplete
        ) {
            heroOpacity = 0
        } completion: {
            guard !self.isClosing else { return }
            self.showHeroOverlay = false
            self.openSettled = true
        }
    }

    /// If the open-handoff animation completion never fires, still reveal the map and unlock follow.
    @MainActor
    private func forceOpenSettledIfNeeded() {
        guard !isClosing else { return }
        if mapClarity < 1 { mapClarity = 1 }
        if chromeReveal < 1 { chromeReveal = 1 }
        if heroOpacity > 0 { heroOpacity = 0 }
        if showHeroOverlay { showHeroOverlay = false }
        if puckAlpha < 1 { puckAlpha = 1 }
        if !puckRevealed { puckRevealed = true }
        if !openSettled { openSettled = true }
        lockProjectedHeroDest = true
    }

    /// Inserts the map tree after the follow camera is already written (no world→local fly-in).
    @MainActor
    private func prepareMapMount() {
        guard !isClosing, !mapMounted else { return }
        bootstrapCamera()
        latchStartCoordinateIfNeeded()
        mapMounted = true
    }

    @MainActor
    private func beginClose() {
        guard !isClosing else { return }
        isClosing = true
        openSettled = false
        stopDisplayLink()
        releaseIdleLock()

        if reduceMotion {
            showHeroOverlay = true
            heroOpacity = 1
            heroFlight = 1
            puckRevealed = false
            puckAlpha = 1
            mapClarity = 0
            chromeReveal = 0
            heroFlight = 0
            mapMounted = false
            onClose()
            return
        }

        Task { @MainActor in
            await runCloseHandoffThenFlight()
        }
    }

    /// Crossfade MapKit puck → SwiftUI hero, then fly the hero back to the list card.
    @MainActor
    private func runCloseHandoffThenFlight() async {
        // Remount hero at the landing spot, invisible, then fade it in over the puck.
        showHeroOverlay = true
        heroFlight = 1
        heroOpacity = 0

        puckFadeToken += 1
        puckAlpha = 0
        withAnimation(
            TrailhoundMotion.liveFollowHandoff,
            completionCriteria: .logicallyComplete
        ) {
            heroOpacity = 1
        } completion: {
            Task { @MainActor in
                guard self.isClosing else { return }
                self.puckRevealed = false
                self.puckAlpha = 1
                withAnimation(
                    TrailhoundMotion.liveFollowReveal,
                    completionCriteria: .logicallyComplete
                ) {
                    self.mapClarity = 0
                    self.chromeReveal = 0
                    self.heroFlight = 0
                } completion: {
                    self.mapMounted = false
                    self.onClose()
                }
            }
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
        session.recordingService = recordingService
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
            // Start pin fallback for a session opened before the first breadcrumb —
            // latched here (not via onChange) so the body never observes breadcrumbs.
            if latchedStartCoordinate == nil {
                latchStartCoordinateIfNeeded()
            }
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
        session.recordingService = recordingService
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

    private func latchStartCoordinateIfNeeded() {
        if latchedStartCoordinate == nil,
           let first = recordingService.liveBreadcrumbCoordinates.first
        {
            latchedStartCoordinate = first
        }
    }

    private var liveFollowPlateColor: Color {
        shellPalette.tintColor(for: colorScheme)
    }

    private var liveFollowChevronColors: [Color] {
        let atm = shellPalette.atmosphere(for: colorScheme)
        return [atm.glow.color, atm.tint.color, atm.chrome.color]
    }

    /// Map recorded GPS runs onto polyline segments. Runs are already split at gaps;
    /// pieces with fewer than two points cannot form a stroke and are dropped.
    ///
    /// The live map no longer routes geometry through SwiftUI at all (the coordinator
    /// pulls it from the session on display ticks); this stays as the pure mapping
    /// used by tests and any future list-side consumers.
    static func polylineSegments(
        from liveSegments: [[CLLocationCoordinate2D]]
    ) -> [LiveFollowPolylineSegment] {
        liveSegments.enumerated().compactMap { index, coords in
            guard coords.count >= 2 else { return nil }
            return LiveFollowPolylineSegment(id: "live-\(index)-0", coordinates: coords)
        }
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
    var plateColor: Color
    var chevronColors: [Color]

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
                    .fill(plateColor)

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
                    .fill(plateColor)
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.35 + 0.65 * puckChrome), lineWidth: 2 + 3 * puckChrome)
            }
            .frame(width: side, height: side)

            LiveFollowNavChevron()
                .fill(
                    LinearGradient(
                        colors: chevronColors,
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
    var plateColor: Color
    var chevronColors: [Color]

    private let circleSize: CGFloat = 56
    private let photoBorder: CGFloat = 5
    /// Air between the photo and the inner edge of the white ring.
    private let photoGap: CGFloat = 3
    private let chevronSize = CGSize(width: 52, height: 38)
    /// How far the chevron sits up onto the circle.
    private let chevronOverlap: CGFloat = 18

    var body: some View {
        ZStack(alignment: .top) {
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
        .offset(y: -circleSize / 2 + 8)
        .accessibilityHidden(true)
    }

    private var filledChevron: some View {
            LiveFollowNavChevron()
            .fill(
                LinearGradient(
                    colors: chevronColors,
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
                .fill(plateColor)

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
