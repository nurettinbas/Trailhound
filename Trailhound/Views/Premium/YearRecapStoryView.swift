import CoreLocation
import SwiftUI
import UIKit

struct YearRecapStoryView: View {
    var onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.scenePhase) private var scenePhase

    @State private var frozen: YearRecapSnapshot
    @State private var pages: [RecapStoryPage]
    @State private var playback: RecapStoryPlayback
    @State private var displayedDistance: Double = 0
    @State private var advanceTask: Task<Void, Never>?
    @State private var shareItem = RecapShareItem.empty
    @State private var routeImage: UIImage?
    @State private var clockStartedAt = Date()
    @State private var remainingAtClock = RecapStoryPlayback.pageDuration
    @State private var motionElapsed: TimeInterval = 0
    @State private var motionTickAnchor = Date()
    @State private var pageAdvancing = true

    init(snapshot: YearRecapSnapshot, onClose: @escaping () -> Void) {
        self.onClose = onClose
        let pages = RecapStoryPagePolicy.pages(for: snapshot)
        _frozen = State(initialValue: snapshot)
        _pages = State(initialValue: pages)
        _playback = State(
            initialValue: RecapStoryPlayback(
                pageCount: max(1, pages.count),
                autoplayEnabled: !UITestSupport.isEnabled
            )
        )
    }

    private var currentPage: RecapStoryPage {
        guard !pages.isEmpty else { return .intro }
        return pages[min(max(0, playback.pageIndex), pages.count - 1)]
    }

    private var liveMotion: Bool {
        playback.autoplayEnabled
            && !playback.isPaused
            && scenePhase == .active
            && !reduceMotion
            && !UITestSupport.isEnabled
    }

    private var freezeStoryMotion: Bool {
        reduceMotion || UITestSupport.isEnabled
    }

    private var motionInterval: TimeInterval {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? 1 / 12 : 1 / 30
    }

    private func motionT(now: Date) -> TimeInterval {
        if liveMotion {
            return motionElapsed + now.timeIntervalSince(motionTickAnchor)
        }
        return motionElapsed
    }

    var body: some View {
        ZStack(alignment: .top) {
            visualLayers
                .allowsHitTesting(false)
            RecapStoryTapCatcher(
                onBack: retreatFromControl,
                onForward: advanceFromControl,
                onHoldChanged: { holding in
                    if holding {
                        pausePlayback()
                    } else {
                        resumePlayback()
                    }
                }
            )
            .ignoresSafeArea()
            chromeLayer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .presentationBackground {
            shellPalette.atmosphere(for: colorScheme).bottom.color
        }
        .onAppear {
            motionTickAnchor = Date()
            applyMotionPolicy()
            animateDistance()
            scheduleAdvance()
            TrailhoundHaptics.selection()
        }
        .onChange(of: playback.pageIndex) { _, _ in
            animateDistance()
            scheduleAdvance()
            TrailhoundHaptics.selection()
        }
        .onChange(of: playback.isPaused) { _, paused in
            if paused {
                advanceTask?.cancel()
            } else {
                scheduleAdvance()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                pausePlayback()
            }
        }
        .onDisappear {
            advanceTask?.cancel()
            FrequentRoutesSnapshotCache.shared.dropMemory()
        }
        .task {
            await warmRoute()
        }
        .task(id: shareRenderKey) {
            await Task.yield()
            shareItem = RecapShareRenderer.item(
                for: frozen,
                page: currentPage,
                palette: shellPalette,
                scheme: colorScheme,
                routeImage: routeImage
            )
        }
        .accessibilityIdentifier("stats.premium.recap.story")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            String(format: L10n.string("premium.recap.page_a11y"), playback.pageIndex + 1, max(1, pages.count))
        )
    }

    private func storyLayers(now: Date) -> some View {
        let t = motionT(now: now)
        return ZStack(alignment: .top) {
            ZStack {
                RecapPageScene(
                    page: currentPage,
                    isActive: true,
                    reduceMotion: freezeStoryMotion,
                    badgeIDs: RecapStoryBadgeIDs.resolved(from: frozen),
                    motion: t
                )
                .id(currentPage)
                .transition(
                    TrailhoundMotion.recapSceneTransition(
                        reduceMotion: freezeStoryMotion,
                        advancing: pageAdvancing
                    )
                )
            }
            .ignoresSafeArea()

            RecapStoryBottomScrim()

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack {
                    RecapStoryPageForeground(
                        snapshot: frozen,
                        page: currentPage,
                        displayedDistance: displayedDistance,
                        routeImage: routeImage,
                        motion: t,
                        reduceMotion: freezeStoryMotion
                    )
                    .id(playback.pageIndex)
                    .transition(TrailhoundMotion.recapCopyTransition(reduceMotion: freezeStoryMotion))
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 12)
            .onGlassShell()
        }
        .animation(TrailhoundMotion.recapPage(reduceMotion: freezeStoryMotion), value: playback.pageIndex)
    }

    @ViewBuilder
    private var visualLayers: some View {
        if liveMotion {
            TimelineView(.animation(minimumInterval: motionInterval)) { timeline in
                storyLayers(now: timeline.date)
            }
        } else {
            storyLayers(now: motionTickAnchor)
        }
    }

    @ViewBuilder
    private var chromeLayer: some View {
        Group {
            if liveMotion {
                TimelineView(.animation(minimumInterval: motionInterval)) { timeline in
                    topChrome(now: timeline.date)
                }
            } else {
                topChrome(now: Date())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, RecapStoryChromeMetrics.topPadding(windowTop: windowTopInset))
        .ignoresSafeArea(edges: .top)
        .onGlassShell()
        .zIndex(2)
    }

    /// `fullScreenCover` / tap overlay can zero SwiftUI safe-area; the window still has the island.
    private var windowTopInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let inset = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets.top {
            return inset
        }
        return scenes.flatMap(\.windows).first?.safeAreaInsets.top ?? 59
    }

    private var shareRenderKey: String {
        "\(playback.pageIndex)-\(routeImage != nil)-\(colorScheme)-\(shellPalette.rawValue)"
    }

    private func topChrome(now: Date) -> some View {
        VStack(alignment: .trailing, spacing: 8) {
            RecapStoryProgressBar(
                playback: playback,
                clockStartedAt: clockStartedAt,
                remainingAtClock: remainingAtClock,
                now: now
            )
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                ShareLink(
                    item: shareItem,
                    preview: SharePreview("Trailhound", image: Image(uiImage: shareItem.image))
                ) {
                    GlassToolbarSymbol(systemName: "square.and.arrow.up", sampling: .frozen)
                }
                .buttonStyle(.plain)
                .disabled(shareItem.image.size.width < 2)
                .accessibilityIdentifier("stats.premium.recap.share")
                Button(action: close) {
                    GlassToolbarSymbol(systemName: "xmark", sampling: .frozen)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stats.premium.recap.close")
                .accessibilityLabel(L10n.string("premium.recap.close_a11y"))
            }
        }
        .padding(.horizontal, 12)
    }

    private func applyMotionPolicy() {
        if reduceMotion, playback.autoplayEnabled {
            playback = RecapStoryPlayback(pageCount: pages.count, autoplayEnabled: false)
        }
    }

    private func advanceFromControl() {
        if playback.isLastPage {
            close()
            return
        }
        pageAdvancing = true
        animatePageChange {
            if playback.advance() == .moved {
                resetClock()
            }
        }
    }

    private func retreatFromControl() {
        pageAdvancing = false
        animatePageChange {
            if playback.retreat() == .moved {
                resetClock()
            }
        }
    }

    private func animatePageChange(_ body: () -> Void) {
        if let animation = TrailhoundMotion.recapPage(reduceMotion: freezeStoryMotion) {
            withAnimation(animation, body)
        } else {
            body()
        }
    }

    private func pausePlayback() {
        guard !playback.isPaused else { return }
        motionElapsed += max(0, Date().timeIntervalSince(motionTickAnchor))
        let elapsed = Date().timeIntervalSince(clockStartedAt)
        playback.setRemaining(max(0, remainingAtClock - elapsed))
        playback.pause()
    }

    private func resumePlayback() {
        playback.resume()
        remainingAtClock = playback.remaining
        clockStartedAt = Date()
        motionTickAnchor = Date()
    }

    private func resetClock() {
        remainingAtClock = RecapStoryPlayback.pageDuration
        clockStartedAt = Date()
        playback.setRemaining(RecapStoryPlayback.pageDuration)
    }

    private func scheduleAdvance() {
        advanceTask?.cancel()
        guard playback.autoplayEnabled, !playback.isPaused else { return }
        let wait = max(0.05, playback.remaining)
        remainingAtClock = wait
        clockStartedAt = Date()
        let closingPage = playback.isLastPage
        advanceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            if closingPage {
                if playback.consume(wait) == .finished {
                    close()
                }
                return
            }
            pageAdvancing = true
            animatePageChange {
                if playback.consume(wait) == .moved {
                    resetClock()
                }
            }
        }
    }

    private func close() {
        advanceTask?.cancel()
        TrailhoundHaptics.badgeUnlocked()
        onClose()
    }

    private func animateDistance() {
        guard currentPage == .distance else { return }
        displayedDistance = reduceMotion ? frozen.distanceMeters : 0
        withAnimation(TrailhoundMotion.recapCountUp(reduceMotion: reduceMotion)) {
            displayedDistance = frozen.distanceMeters
        }
    }

    private func warmRoute() async {
        guard
            frozen.topRouteCount >= 2,
            let slat = frozen.topRouteStartLatitude,
            let slon = frozen.topRouteStartLongitude,
            let elat = frozen.topRouteEndLatitude,
            let elon = frozen.topRouteEndLongitude
        else { return }
        routeImage = await FrequentRoutesSnapshotCache.shared.snapshot(
            start: CLLocationCoordinate2D(latitude: slat, longitude: slon),
            end: CLLocationCoordinate2D(latitude: elat, longitude: elon),
            count: frozen.topRouteCount,
            isBusiness: frozen.businessDistanceMeters > frozen.otherDistanceMeters
        )
    }
}

private struct RecapStoryProgressBar: View {
    let playback: RecapStoryPlayback
    let clockStartedAt: Date
    let remainingAtClock: TimeInterval
    let now: Date

    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        bars(now: now)
            .frame(height: 4)
            .accessibilityIdentifier("stats.premium.recap.segments")
            .accessibilityHidden(true)
    }

    private func bars(now: Date) -> some View {
        let elapsed = max(0, now.timeIntervalSince(clockStartedAt))
        let remaining = playback.isPaused || !playback.autoplayEnabled
            ? playback.remaining
            : max(0, remainingAtClock - elapsed)
        var fills: [Double] = []
        for index in 0..<playback.pageCount {
            if index < playback.pageIndex {
                fills.append(1)
            } else if index > playback.pageIndex {
                fills.append(0)
            } else if !playback.autoplayEnabled {
                fills.append(0)
            } else {
                fills.append(1 - remaining / RecapStoryPlayback.pageDuration)
            }
        }
        return HStack(spacing: 4) {
            ForEach(0..<playback.pageCount, id: \.self) { index in
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                    Capsule()
                        .fill(shellPalette.tintColor(for: colorScheme))
                        .frame(width: geo.size.width * CGFloat(min(1, max(0, fills[index]))))
                }
                .frame(height: 3)
            }
        }
    }
}

private struct RecapStoryTapCatcher: UIViewRepresentable {
    var onBack: () -> Void
    var onForward: () -> Void
    var onHoldChanged: (Bool) -> Void

    func makeUIView(context: Context) -> RecapStoryTapView {
        RecapStoryTapView()
    }

    func updateUIView(_ uiView: RecapStoryTapView, context: Context) {
        uiView.onBack = onBack
        uiView.onForward = onForward
        uiView.onHoldChanged = onHoldChanged
    }
}

final class RecapStoryTapView: UIView, UIGestureRecognizerDelegate {
    var onBack: () -> Void = {}
    var onForward: () -> Void = {}
    var onHoldChanged: (Bool) -> Void = { _ in }

    private let backButton = UIButton(type: .custom)
    private let forwardButton = UIButton(type: .custom)
    private var suppressClick = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = .clear
        isAccessibilityElement = false

        configure(backButton, identifier: "stats.premium.recap.back", label: L10n.string("premium.recap.back_a11y")) {
            self.handleTap(isBack: true)
        }
        configure(forwardButton, identifier: "stats.premium.recap.forward", label: L10n.string("premium.recap.forward_a11y")) {
            self.handleTap(isBack: false)
        }
        addSubview(backButton)
        addSubview(forwardButton)

        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = RecapStoryTapMetrics.holdDuration
        hold.cancelsTouchesInView = false
        hold.delegate = self
        addGestureRecognizer(hold)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        let backWidth = bounds.width * RecapStoryTapMetrics.backWidthFraction
        backButton.frame = CGRect(x: 0, y: 0, width: backWidth, height: bounds.height)
        forwardButton.frame = CGRect(x: backWidth, y: 0, width: max(0, bounds.width - backWidth), height: bounds.height)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    private func configure(
        _ button: UIButton,
        identifier: String,
        label: String,
        action: @escaping () -> Void
    ) {
        button.backgroundColor = .clear
        button.accessibilityIdentifier = identifier
        button.accessibilityLabel = label
        button.accessibilityTraits = .button
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    }

    private func handleTap(isBack: Bool) {
        guard !suppressClick else { return }
        if isBack {
            onBack()
        } else {
            onForward()
        }
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            suppressClick = true
            onHoldChanged(true)
        case .ended, .cancelled, .failed:
            onHoldChanged(false)
            DispatchQueue.main.async { [weak self] in
                self?.suppressClick = false
            }
        default:
            break
        }
    }
}
