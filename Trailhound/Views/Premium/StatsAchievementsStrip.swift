import SwiftUI
import UIKit

struct StatsAchievementsStrip: View {
    let achievements: [AchievementDisplay]
    var isExpanded: Bool
    var onOpen: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("premium.achievements.title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                    .padding(.trailing, 44)
                if visible.isEmpty {
                    Text(L10n.string("premium.achievements.empty"))
                        .font(.caption)
                        .foregroundStyle(StatsTextColor.tertiary(for: colorScheme))
                } else {
                    idleMedals
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onOpen) {
                GlassToolbarSymbol(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.mapFullscreen)
            .accessibilityIdentifier("stats.premium.achievements")
            .allowsHitTesting(!isExpanded)
            .offset(x: StatsCardTokens.expandGlyphOffset.width, y: StatsCardTokens.expandGlyphOffset.height)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var idleMedals: some View {
        ViewThatFits(in: .horizontal) {
            medalRow
            ScrollView(.horizontal, showsIndicators: false) {
                medalRow
            }
            .scrollClipDisabled()
        }
        .frame(maxWidth: .infinity)
        .achievementIdleClock(enabled: ticksIdleClock && !isExpanded)
    }

    private var ticksIdleClock: Bool {
        !reduceMotion && !UITestSupport.isEnabled && achievements.contains(where: \.isUnlocked)
    }

    private var medalRow: some View {
        HStack(spacing: 10) {
            ForEach(visible) { item in
                AchievementBadgeView(item: item, compact: true, playsMotion: !isExpanded)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8)
    }

    private var visible: [AchievementDisplay] {
        AchievementStripPreview.medals(from: achievements)
    }
}

struct AchievementBadgeView: View {
    let item: AchievementDisplay
    var compact: Bool = false
    var showsLabels: Bool = true
    var emphasized: Bool = false
    var playsMotion: Bool = true

    var body: some View {
        VStack(spacing: 6) {
            AchievementMedalMark(
                item: item,
                size: compact ? AchievementGalleryTokens.compactMedalSize : AchievementGalleryTokens.medalSize,
                emphasized: emphasized,
                playsMotion: playsMotion
            )
            if showsLabels, !compact {
                Text(L10n.string(item.id.titleKey))
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(item.isUnlocked ? .primary : .secondary)
                if !item.isUnlocked {
                    Text(AchievementProgressCaption.text(for: item))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: compact ? 52 : 96, height: compact ? 56 : nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(compactAccessibilityLabel)
    }

    private var compactAccessibilityLabel: String {
        var parts = [L10n.string(item.id.titleKey)]
        parts.append(item.isUnlocked ? L10n.string("premium.achievements.unlocked") : L10n.string("stats.awards.locked"))
        if !item.isUnlocked {
            parts.append(AchievementProgressCaption.text(for: item))
        }
        return parts.joined(separator: ", ")
    }
}

/// Year-awards style round medal: 3D chrome disc, family enamel or km metal.
struct AchievementMedalMark: View {
    let item: AchievementDisplay
    var size: CGFloat
    var emphasized: Bool = false
    var playsMotion: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.achievementIdleTime) private var idleTime
    @State private var motionOn = false

    var body: some View {
        let palette = AchievementTheme.medalPalette(for: item.id, scheme: colorScheme)
        ZStack {
            AchievementMedalChrome(id: item.id, size: size)
            if !item.isUnlocked {
                AchievementMedalLockScrim(size: size)
            }
            glyph(ink: palette.glyph)
                .opacity(1)
            if !item.isUnlocked {
                AchievementMedalLockOverlay(size: size)
            }
        }
        .frame(width: size, height: size)
        .modifier(AchievementMedalDiscClip(allowsGlyphOverflow: playsIdleSymbol && AchievementMedalIdle.glyphOverflows(item.id.family)))
        .shadow(
            color: Color.black.opacity(reduceMotion ? 0.12 : 0.28),
            radius: reduceMotion ? 2 : 4,
            y: 1
        )
        .shadow(
            color: emphasized && item.isUnlocked && !reduceMotion
                ? palette.glow.opacity(motionOn ? 0.55 : 0.18)
                : .clear,
            radius: emphasized ? 16 : 0
        )
        .scaleEffect(x: motionScaleX, y: motionScaleY)
        .rotationEffect(.degrees(motionRotation))
        .offset(y: motionOffsetY)
        .accessibilityHidden(true)
        .achievementIdleClockPose(drivenByClock: idleTime != nil)
        .onAppear(perform: startFamilyMotion)
        .onChange(of: item.isUnlocked) { _, _ in
            startFamilyMotion()
        }
        .onChange(of: playsMotion) { _, _ in
            startFamilyMotion()
        }
        .onChange(of: idleTime != nil) { _, _ in
            startFamilyMotion()
        }
    }

    private var playsIdleSymbol: Bool {
        playsFamilyMotion
    }

    @ViewBuilder
    private func glyph(ink: Color) -> some View {
        switch item.id.family {
        case .distance:
            AchievementDistancePathGlyph(
                size: size,
                isActive: playsIdleSymbol,
                ink: ink,
                motion: item.id.medalMaterial.map(AchievementDistancePathMotion.for) ?? .rendezvous
            )
        case .night where item.id == .nightOwl:
            AchievementNightSkyGlyph(size: size, isActive: playsIdleSymbol)
        default:
            Image(systemName: item.id.systemImage)
                .font(size < 50 ? .body.weight(.semibold) : .title3.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(ink)
                .modifier(AchievementFamilyIdleEffect(family: item.id.family, isActive: playsIdleSymbol, size: size))
        }
    }

    private var familyPeriod: Double {
        AchievementMedalIdle.period(for: item.id.family)
    }

    private var idlePhase: CGFloat {
        guard playsFamilyMotion else { return 0 }
        if let idleTime {
            return AchievementMedalIdle.pingPong(at: idleTime, duration: familyPeriod)
        }
        return motionOn ? 1 : 0
    }

    private var motionScaleX: CGFloat {
        guard playsFamilyMotion else { return 1 }
        let p = idlePhase
        switch item.id.family {
        case .firstTrip, .distance, .night: return 1
        case .streak: return 1 + 0.10 * p
        case .routes: return 0.97 + 0.09 * p
        default: return 1 + 0.06 * p
        }
    }

    private var motionScaleY: CGFloat {
        guard playsFamilyMotion else { return 1 }
        let p = idlePhase
        switch item.id.family {
        case .firstTrip, .distance, .night: return 1
        case .streak: return 1 + 0.10 * p
        default: return motionScaleX
        }
    }

    private var motionRotation: Double {
        guard playsFamilyMotion, AchievementMedalIdle.discTilts(item.id.family) else { return 0 }
        let p = Double(idlePhase)
        switch item.id.family {
        case .routes: return -16 + 32 * p
        case .business: return -5 + 10 * p
        case .weekend: return -8 + 16 * p
        case .fleet: return -6 + 12 * p
        default: return -4 + 8 * p
        }
    }

    private var motionOffsetY: CGFloat {
        guard playsFamilyMotion, size >= 50 else { return 0 }
        let p = idlePhase
        switch item.id.family {
        case .cities: return -7 * p
        case .distance, .night: return 0
        default: return 2 - 5 * p
        }
    }

    private var playsFamilyMotion: Bool {
        playsMotion && item.isUnlocked && !reduceMotion
    }

    private var playsEmphasizedMotion: Bool {
        emphasized && playsFamilyMotion
    }

    private func startFamilyMotion() {
        guard playsFamilyMotion, idleTime == nil else {
            motionOn = false
            return
        }
        motionOn = false
        withAnimation(
            .easeInOut(duration: familyPeriod * 0.45)
            .repeatForever(autoreverses: true)
        ) {
            motionOn = true
        }
    }
}

struct AchievementCardGlobalFrameKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1, next.height > 1 {
            value = next
        }
    }
}

/// Grows the Stats badges card in place. Not a sheet, not matchedGeometry.
struct AchievementGalleryExpandOverlay: View {
    let achievements: [AchievementDisplay]
    let sourceGlobal: CGRect
    @Binding var isExpanded: Bool
    var onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var idleClockOn = false

    var body: some View {
        GeometryReader { proxy in
            let overlayGlobal = proxy.frame(in: .global)
            let frame = AchievementGalleryExpandLayout.localSurface(
                sourceGlobal: sourceGlobal,
                overlayGlobal: overlayGlobal,
                expanded: isExpanded
            )
            let radius = AchievementGalleryExpandLayout.cornerRadius(expanded: isExpanded)
            let window = windowSafeInsets
            let topInset = max(proxy.safeAreaInsets.top, window.top, 54)
            let bottomInset = max(proxy.safeAreaInsets.bottom, window.bottom, 34)
            ZStack {
                Color.clear
                    .allowsHitTesting(false)
                surface(radius: radius, topInset: topInset, bottomInset: bottomInset)
                    .frame(width: frame.width, height: frame.height, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .position(x: frame.midX, y: frame.midY)
            }
            .animation(TrailhoundMotion.badgeCardExpand(reduceMotion: reduceMotion), value: isExpanded)
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("stats.achievements.expanded")
        .onAppear(perform: syncIdleClock)
        .onChange(of: isExpanded) { _, _ in
            syncIdleClock()
        }
    }

    private func syncIdleClock() {
        if isExpanded {
            Task { @MainActor in
                try? await Task.sleep(
                    for: .milliseconds(reduceMotion ? 0 : 780)
                )
                idleClockOn = isExpanded
            }
        } else {
            idleClockOn = false
        }
    }

    /// `GeometryReader` under `.ignoresSafeArea()` reports zero insets — same as trip-detail map.
    private var windowSafeInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let inset = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets {
            return inset
        }
        return scenes.flatMap(\.windows).first?.safeAreaInsets
            ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }

    @ViewBuilder
    private func surface(radius: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        ZStack(alignment: .top) {
            StatsAchievementsStrip(
                achievements: achievements,
                isExpanded: true,
                onOpen: {}
            )
            .padding(StatsCardTokens.contentInset)
            .opacity(isExpanded ? 0 : 1)
            .animation(TrailhoundMotion.badgeGalleryAppear(reduceMotion: reduceMotion), value: isExpanded)
            .allowsHitTesting(false)
            AchievementGalleryView(
                achievements: achievements,
                topInset: topInset,
                bottomInset: bottomInset,
                onClose: onClose,
                playsIdleClock: idleClockOn
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(isExpanded ? 1 : 0)
            .animation(TrailhoundMotion.badgeGalleryAppear(reduceMotion: reduceMotion), value: isExpanded)
            .allowsHitTesting(isExpanded)
        }
        .background {
            AtmosphericBackground()
                .allowsHitTesting(false)
        }
        .glassCard(cornerRadius: radius, contentInset: 0, frozen: true, allowsNative: false)
    }
}

struct AchievementGalleryView: View {
    let achievements: [AchievementDisplay]
    var topInset: CGFloat
    var bottomInset: CGFloat
    var onClose: () -> Void
    var playsIdleClock: Bool = true
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Text(L10n.string("premium.achievements.title"))
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                GlassToolbarCollapseButton(
                    accessibilityIdentifier: "stats.achievement.expanded.close",
                    action: onClose
                )
            }
            .padding(.leading, 16)
            .padding(.trailing, 12)
            .padding(.top, topInset)
            .padding(.bottom, 8)
            galleryScroll
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGlassShell()
    }

    /// Catalog order so the km ladder stays together (100k after 10k), not buried after other locked families.
    private var galleryItems: [AchievementDisplay] {
        achievements.sorted(by: AchievementDisplay.listOrder)
    }

    private var galleryScroll: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(galleryItems) { item in
                    AchievementGalleryCard(item: item, playsMotion: playsIdleClock)
                }
            }
            .padding(16)
            .padding(.bottom, bottomInset)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .achievementIdleClock(enabled: playsIdleClock)
    }

    private var columns: [GridItem] {
        let spacing: CGFloat = 12
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: spacing, alignment: .top)]
        }
        let count = sizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: count)
    }
}

struct AchievementGalleryCard: View {
    let item: AchievementDisplay
    var playsMotion: Bool = true

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @State private var sharePreview: UIImage?

    var body: some View {
        VStack(spacing: 5) {
            VStack(spacing: 5) {
                AchievementMedalMark(
                    item: item,
                    size: AchievementGalleryTokens.medalSize,
                    playsMotion: playsMotion
                )
                Text(L10n.string(item.id.titleKey))
                    .font(.caption.weight(.semibold))
                    .glassPrimaryInk()
                    .multilineTextAlignment(.center)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.85)
                    .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? nil : AchievementGalleryTokens.titleSlotHeight)
                Text(L10n.string(item.id.bodyKey))
                    .font(.caption.weight(.medium))
                    .glassSecondaryInk()
                    .multilineTextAlignment(.center)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.85)
                    .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? nil : AchievementGalleryTokens.bodySlotHeight)
                Text(statusText)
                    .font(.caption.weight(.medium).monospacedDigit())
                    .glassSecondaryInk()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, minHeight: AchievementGalleryTokens.statusSlotHeight)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(cardAccessibilityLabel)
            shareSlot
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: cardMinHeight, maxHeight: cardMaxHeight, alignment: .top)
        .glassCard(cornerRadius: AchievementGalleryTokens.cardRadius, contentInset: 0, allowsNative: false)
        .accessibilityIdentifier("stats.achievement.card.\(item.id.rawValue)")
        .task(id: shareRenderKey) {
            guard item.isUnlocked else { return }
            if !UITestSupport.isEnabled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
            }
            sharePreview = AchievementShareRenderer.image(
                for: item,
                palette: shellPalette,
                scheme: colorScheme
            )
        }
    }

    private var shareRenderKey: String {
        "\(item.id.rawValue)-\(shellPalette.rawValue)-\(colorScheme == .dark ? "d" : "l")"
    }

    private var statusText: String {
        if let unlockedAt = item.unlockedAt {
            return unlockedAt.formatted(date: .abbreviated, time: .omitted)
        }
        return AchievementProgressCaption.text(for: item)
    }

    private var cardAccessibilityLabel: String {
        var parts = [L10n.string(item.id.titleKey)]
        parts.append(item.isUnlocked ? L10n.string("premium.achievements.unlocked") : L10n.string("stats.awards.locked"))
        parts.append(statusText)
        return parts.joined(separator: ", ")
    }

    private var cardMinHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize
            ? AchievementGalleryTokens.accessibilityMinHeight
            : AchievementGalleryTokens.cardHeight
    }

    private var cardMaxHeight: CGFloat? {
        dynamicTypeSize.isAccessibilitySize ? nil : AchievementGalleryTokens.cardHeight
    }

    @ViewBuilder
    private var shareSlot: some View {
        if item.isUnlocked {
            ShareLink(
                item: AchievementSharePayload(display: item, palette: shellPalette, scheme: colorScheme),
                preview: SharePreview(
                    AchievementShareRenderer.caption(for: item),
                    image: sharePreviewImage
                )
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                    Text(L10n.share)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .trailhoundCompactProminentButton()
            }
            .buttonStyle(AchievementShareButtonStyle())
            .frame(maxWidth: .infinity, minHeight: AchievementGalleryTokens.shareSlotHeight)
            .accessibilityIdentifier("stats.achievement.share.\(item.id.rawValue)")
        } else {
            Color.clear
                .frame(maxWidth: .infinity, minHeight: AchievementGalleryTokens.shareSlotHeight)
                .accessibilityHidden(true)
        }
    }

    private var sharePreviewImage: Image {
        if let sharePreview, sharePreview.size.width > 2 {
            return Image(uiImage: sharePreview)
        }
        return Image(systemName: item.id.systemImage)
    }
}

private struct AchievementShareButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : TrailhoundMotion.snappy, value: configuration.isPressed)
    }
}

private struct AchievementMedalDiscClip: ViewModifier {
    var allowsGlyphOverflow: Bool

    func body(content: Content) -> some View {
        if allowsGlyphOverflow {
            content
        } else {
            content.clipShape(Circle())
        }
    }
}

struct AchievementUnlockOverlay: View {
    let item: AchievementDisplay
    var onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var didFinish = false

    var body: some View {
        VStack(spacing: 14) {
            medal
            Text(L10n.string("premium.achievements.unlocked"))
                .font(.headline)
            Text(L10n.string(item.id.titleKey))
                .font(.subheadline.weight(.semibold))
        }
        .padding(28)
        .glassCard(cornerRadius: StatsCardTokens.radius, contentInset: 0)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.86)
        .onTapGesture(perform: finish)
        .task(id: item.id) {
            await play()
        }
        .accessibilityIdentifier("stats.premium.achievement.unlock")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var medal: some View {
        medalMark
    }

    private var medalMark: some View {
        AchievementMedalMark(
            item: item,
            size: AchievementGalleryTokens.expandedMedalSize,
            emphasized: true
        )
        .accessibilityHidden(true)
    }

    private var dwell: TimeInterval {
        UITestSupport.isEnabled ? 0.05 : AchievementGalleryTokens.unlockDwell
    }

    @MainActor
    private func play() async {
        didFinish = false
        appeared = false
        TrailhoundHaptics.badgeUnlocked()
        withAnimation(TrailhoundMotion.badgeUnlock(reduceMotion: reduceMotion)) {
            appeared = true
        }
        try? await Task.sleep(for: .seconds(dwell))
        guard !Task.isCancelled else { return }
        finish()
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onDismiss()
    }
}
