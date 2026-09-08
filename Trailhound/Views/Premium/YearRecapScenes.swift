import SwiftUI
import UIKit

enum RecapSceneMotion {
    /// Sine wave mapped to 0...1. Period ≤ 0 returns 0.
    static func phase(_ period: TimeInterval, at t: TimeInterval) -> CGFloat {
        guard period > 0 else { return 0 }
        let cycle = t.truncatingRemainder(dividingBy: period) / period
        let sine = (sin(cycle * 2 * .pi) + 1) / 2
        return CGFloat(min(1, max(0, sine)))
    }

    /// Sine wave mapped to -1...1.
    static func signedPhase(_ period: TimeInterval, at t: TimeInterval) -> CGFloat {
        phase(period, at: t) * 2 - 1
    }

    /// Linear wrap 0...1 for dash / highlight travel.
    static func saw(_ period: TimeInterval, at t: TimeInterval) -> CGFloat {
        guard period > 0 else { return 0 }
        let cycle = t.truncatingRemainder(dividingBy: period) / period
        if cycle < 0 { return CGFloat(cycle + 1) }
        return CGFloat(min(1, max(0, cycle)))
    }
}

enum RecapHubTeaserMetrics {
    static let posterHeight: CGFloat = 148
    static let stackedHeight: CGFloat = 88
    static let emptyHeight: CGFloat = 72
    static let idleInterval: TimeInterval = 1.0 / 8.0
}

struct RecapHubTeaserScene: View {
    var height: CGFloat = RecapHubTeaserMetrics.emptyHeight
    var allowsIdleMotion: Bool = false
    var cornerRadius: CGFloat = StatsCardTokens.nestedRadius

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isOnScreen = false

    private var liveMotion: Bool {
        allowsIdleMotion
            && isOnScreen
            && scenePhase == .active
            && !reduceMotion
            && !ProcessInfo.processInfo.isLowPowerModeEnabled
            && !UITestSupport.isEnabled
    }

    var body: some View {
        Group {
            if liveMotion {
                TimelineView(.animation(minimumInterval: RecapHubTeaserMetrics.idleInterval)) { timeline in
                    canvas(motion: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                canvas(motion: 0)
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
        .onAppear { isOnScreen = true }
        .onDisappear { isOnScreen = false }
    }

    private func canvas(motion: TimeInterval) -> RecapStoryCanvas {
        RecapStoryCanvas(
            palette: shellPalette,
            scheme: colorScheme,
            kind: .intro,
            badgeIDs: [],
            motion: motion
        )
    }
}

struct RecapPageScene: View {
    let page: RecapStoryPage
    var isActive: Bool
    var reduceMotion: Bool
    var badgeIDs: [AchievementID] = []
    var motion: TimeInterval = 0

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        RecapStoryCanvas(
            palette: shellPalette,
            scheme: colorScheme,
            kind: page,
            badgeIDs: badgeIDs,
            motion: reduceMotion ? 0 : motion
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if page == .badges {
                RecapStoryBadgeStage(
                    ids: badgeIDs,
                    motion: motion,
                    reduceMotion: reduceMotion
                )
            }
        }
        .opacity(isActive ? 1 : 0.92)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct RecapStoryBottomScrim: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: [
                .clear,
                .clear,
                Color.black.opacity(colorScheme == .dark ? 0.58 : 0.42)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct RecapStoryPageForeground: View {
    let snapshot: YearRecapSnapshot
    let page: RecapStoryPage
    var displayedDistance: Double
    var routeImage: UIImage?
    var motion: TimeInterval
    var reduceMotion: Bool

    var body: some View {
        VStack(spacing: 12) {
            RecapStoryPageCopy(
                snapshot: snapshot,
                page: page,
                displayedDistance: displayedDistance,
                routeImage: routeImage
            )
            .padding(.horizontal, 28)
            if page == .badges {
                let extra = RecapStoryBadgeLayout.overflowCount(RecapStoryBadgeIDs.resolved(from: snapshot).count)
                if extra > 0 {
                    Text("+\(extra)")
                        .font(.headline.monospacedDigit())
                        .glassSecondaryInk()
                }
            }
        }
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }
}

enum RecapStoryBadgeIDs {
    static func resolved(from snapshot: YearRecapSnapshot) -> [AchievementID] {
        snapshot.unlockedAchievementIDs
            .compactMap(AchievementID.init(rawValue:))
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}

struct RecapStoryPageCopy: View {
    let snapshot: YearRecapSnapshot
    let page: RecapStoryPage
    var displayedDistance: Double
    var routeImage: UIImage?

    var body: some View {
        switch page {
        case .intro:
            VStack(spacing: 8) {
                Text(String(format: L10n.string("premium.recap.intro"), snapshot.year))
                    .font(.largeTitle.weight(.bold))
                    .glassPrimaryInk()
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
            }
        case .distance:
            VStack(spacing: 8) {
                Text(DateFormatters.formatDistance(displayedDistance))
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .glassPrimaryInk()
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text(String(format: L10n.string("premium.recap.distance_body"), snapshot.tripCount))
                    .font(.title3)
                    .glassSecondaryInk()
                    .multilineTextAlignment(.center)
                if snapshot.duration > 0 {
                    Text(String(format: L10n.string("premium.recap.duration_line"), DateFormatters.formatDuration(snapshot.duration)))
                        .font(.headline)
                        .glassSecondaryInk()
                }
            }
        case .cities:
            VStack(spacing: 12) {
                Text("\(snapshot.cityCount)")
                    .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                    .glassPrimaryInk()
                    .minimumScaleFactor(0.55)
                    .lineLimit(1)
                Text(L10n.string("premium.recap.cities_body"))
                    .font(.title3)
                    .glassSecondaryInk()
                ForEach(snapshot.topCities, id: \.self) { city in
                    Text(city).font(.headline).glassPrimaryInk()
                }
            }
        case .route:
            VStack(spacing: 10) {
                Text(L10n.string("premium.recap.route_title"))
                    .font(.headline)
                    .glassSecondaryInk()
                if let routeImage {
                    Image(uiImage: routeImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .accessibilityHidden(true)
                }
                Text("\(snapshot.topRouteStart ?? "") → \(snapshot.topRouteEnd ?? "")")
                    .font(.title2.weight(.bold))
                    .glassPrimaryInk()
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                Text(String(format: L10n.string("premium.recap.route_count"), snapshot.topRouteCount))
                    .glassSecondaryInk()
            }
        case .time:
            VStack(spacing: 12) {
                if snapshot.nightDistanceMeters > 0 {
                    Text(String(format: L10n.string("premium.recap.night"), DateFormatters.formatDistance(snapshot.nightDistanceMeters)))
                        .font(.title2.weight(.bold))
                        .glassPrimaryInk()
                        .minimumScaleFactor(0.7)
                }
                if snapshot.longestStreak > 0 {
                    Text(String(format: L10n.string("premium.recap.streak"), snapshot.longestStreak))
                        .font(.title2.weight(.bold))
                        .glassPrimaryInk()
                }
                if let month = snapshot.busiestMonth {
                    Text(String(format: L10n.string("premium.recap.busiest_month"), DateFormatters.formatMonthName(month: month, year: snapshot.year)))
                        .font(.title3)
                        .glassSecondaryInk()
                    if snapshot.busiestMonthDistanceMeters > 0 {
                        Text(DateFormatters.formatDistance(snapshot.busiestMonthDistanceMeters))
                            .font(.headline.monospacedDigit())
                            .glassPrimaryInk()
                    }
                }
            }
            .multilineTextAlignment(.center)
        case .categories:
            VStack(spacing: 10) {
                Text(L10n.string("premium.recap.categories_title"))
                    .font(.headline)
                    .glassSecondaryInk()
                HStack(spacing: 28) {
                    VStack {
                        Text(DateFormatters.formatDistance(snapshot.businessDistanceMeters))
                            .font(.title3.weight(.bold).monospacedDigit())
                            .glassPrimaryInk()
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        Text(L10n.string("premium.recap.business"))
                            .glassSecondaryInk()
                    }
                    VStack {
                        Text(DateFormatters.formatDistance(snapshot.otherDistanceMeters))
                            .font(.title3.weight(.bold).monospacedDigit())
                            .glassPrimaryInk()
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        Text(L10n.string("premium.recap.other"))
                            .glassSecondaryInk()
                    }
                }
                .font(.caption)
            }
        case .cost:
            VStack(spacing: 10) {
                if snapshot.estimatedFuelCost > 0 {
                    Text(FuelCostCalculator.formatCost(snapshot.estimatedFuelCost))
                        .font(.title.weight(.bold).monospacedDigit())
                        .glassPrimaryInk()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(L10n.string("premium.recap.fuel_estimate"))
                        .glassSecondaryInk()
                }
                if snapshot.paidExpenses > 0 {
                    Text(FuelCostCalculator.formatCost(snapshot.paidExpenses))
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .glassPrimaryInk()
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text(L10n.string("premium.recap.logged_expenses"))
                        .glassSecondaryInk()
                }
            }
        case .badges:
            Text(L10n.string("premium.recap.badges_title"))
                .font(.headline)
                .glassSecondaryInk()
                .multilineTextAlignment(.center)
        case .closing:
            VStack(spacing: 10) {
                Text(String(format: L10n.string("premium.recap.closing"), snapshot.year))
                    .font(.largeTitle.weight(.bold))
                    .glassPrimaryInk()
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                Text(L10n.string("premium.recap.closing_body"))
                    .font(.title3)
                    .glassSecondaryInk()
                    .multilineTextAlignment(.center)
            }
        }
    }
}

enum RecapStoryBadgeLayout {
    static let maxVisible = 6
    static let captionSlot: CGFloat = 34
    static let slotScale: CGFloat = 2.12

    static func visibleCount(_ count: Int) -> Int {
        min(maxVisible, max(0, count))
    }

    static func overflowCount(_ count: Int) -> Int {
        max(0, count - maxVisible)
    }

    static func rowPattern(count: Int) -> [Int] {
        switch visibleCount(count) {
        case 0: []
        case 1: [1]
        case 2: [2]
        case 3: [3]
        case 4: [2, 2]
        case 5: [3, 2]
        default: [3, 3]
        }
    }

    static func medalSize(in size: CGSize, count: Int) -> CGFloat {
        let n = visibleCount(count)
        guard n > 0 else { return 0 }
        let columns = CGFloat(rowPattern(count: n).max() ?? 1)
        let preferred: CGFloat
        switch n {
        case 1: preferred = min(92, size.width * 0.26)
        case 2: preferred = min(78, size.width * 0.22)
        case 4: preferred = min(70, size.width * 0.2)
        default: preferred = min(64, size.width * 0.16)
        }
        let maxFit = (size.width * 0.9) / (columns * slotScale)
        return min(preferred, maxFit)
    }

    static func slotSize(medal: CGFloat) -> CGSize {
        CGSize(width: medal * slotScale, height: medal * slotScale + captionSlot)
    }

    static func slots(in size: CGSize, count: Int) -> [CGRect] {
        let n = visibleCount(count)
        guard n > 0 else { return [] }
        let medal = medalSize(in: size, count: n)
        let slot = slotSize(medal: medal)
        let pattern = rowPattern(count: n)
        let rowGap = medal * 0.1
        let clusterH = CGFloat(pattern.count) * slot.height + CGFloat(max(0, pattern.count - 1)) * rowGap
        let clusterY = min(max(size.height * 0.38 - clusterH / 2, size.height * 0.14), size.height * 0.4)
        var frames: [CGRect] = []
        for (row, items) in pattern.enumerated() {
            let rowW = CGFloat(items) * slot.width
            let originX = (size.width - rowW) / 2
            let y = clusterY + CGFloat(row) * (slot.height + rowGap)
            for column in 0..<items {
                frames.append(
                    CGRect(
                        x: originX + CGFloat(column) * slot.width,
                        y: y,
                        width: slot.width,
                        height: slot.height
                    )
                )
            }
        }
        return frames
    }

    static func medalRect(in slot: CGRect, medal: CGFloat, offsetY: CGFloat) -> CGRect {
        CGRect(
            x: slot.midX - medal / 2,
            y: slot.minY + (slot.height - captionSlot - medal) * 0.42 + offsetY,
            width: medal,
            height: medal
        )
    }

    static func offsetY(index: Int, motion: TimeInterval, reduceMotion: Bool) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return RecapSceneMotion.signedPhase(2.4, at: motion + Double(index) * 0.28) * 5
    }
}

struct RecapStoryBadgeStage: View {
    let ids: [AchievementID]
    var motion: TimeInterval
    var reduceMotion: Bool

    private var visible: [AchievementID] {
        Array(ids.prefix(RecapStoryBadgeLayout.maxVisible))
    }

    var body: some View {
        GeometryReader { geo in
            let slots = RecapStoryBadgeLayout.slots(in: geo.size, count: visible.count)
            let medal = RecapStoryBadgeLayout.medalSize(in: geo.size, count: visible.count)
            ForEach(Array(visible.enumerated()), id: \.element) { index, id in
                RecapStoryBadgeCell(
                    id: id,
                    size: medal,
                    index: index,
                    motion: motion,
                    reduceMotion: reduceMotion
                )
                .frame(width: slots[index].width, height: slots[index].height)
                .position(x: slots[index].midX, y: slots[index].midY)
            }
        }
        .environment(\.achievementIdleTime, reduceMotion ? nil : motion)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ids.map { L10n.string($0.titleKey) }.joined(separator: ", "))
    }
}

private struct RecapStoryBadgeCell: View {
    let id: AchievementID
    let size: CGFloat
    let index: Int
    var motion: TimeInterval
    var reduceMotion: Bool

    var body: some View {
        GeometryReader { geo in
            let slot = CGRect(origin: .zero, size: geo.size)
            let offset = RecapStoryBadgeLayout.offsetY(index: index, motion: motion, reduceMotion: reduceMotion)
            let medalRect = RecapStoryBadgeLayout.medalRect(in: slot, medal: size, offsetY: offset)
            AchievementMedalMark(
                item: AchievementDisplay(
                    id: id,
                    currentValue: id.threshold,
                    unlockedAt: Date(),
                    needsCelebration: false
                ),
                size: size,
                playsMotion: !reduceMotion
            )
            .frame(width: size, height: size)
            .position(x: medalRect.midX, y: medalRect.midY)
            Text(L10n.string(id.titleKey))
                .font(.caption.weight(.semibold))
                .glassPrimaryInk()
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(width: slot.width - 8)
                .position(
                    x: slot.midX,
                    y: min(slot.maxY - RecapStoryBadgeLayout.captionSlot / 2, medalRect.maxY + 16)
                )
        }
        .accessibilityHidden(true)
    }
}

private struct RecapStoryCanvas: View {
    let palette: ShellPalette
    let scheme: ColorScheme
    let kind: RecapStoryPage
    let badgeIDs: [AchievementID]
    var motion: TimeInterval = 0

    var body: some View {
        Canvas { context, size in
            let atmosphere = palette.atmosphere(for: scheme)
            let tint = atmosphere.tint.color
            let glow = atmosphere.glow.color
            let top = atmosphere.top.color
            let bottom = atmosphere.bottom.color
            drawAtmosphere(context: &context, size: size, top: top, bottom: bottom, glow: glow)
            switch kind {
            case .intro:
                drawIntro(context: &context, size: size, tint: tint, glow: glow)
            case .distance:
                drawDistance(context: &context, size: size, tint: tint, glow: glow)
            case .cities:
                drawCities(context: &context, size: size, tint: tint, glow: glow)
            case .route:
                drawRoute(context: &context, size: size, tint: tint, glow: glow)
            case .time:
                drawTime(context: &context, size: size, tint: tint, glow: glow)
            case .categories:
                drawCategories(context: &context, size: size, tint: tint, glow: glow)
            case .cost:
                drawCost(context: &context, size: size, tint: tint, glow: glow)
            case .badges:
                drawBadges(context: &context, size: size, tint: tint, glow: glow)
            case .closing:
                drawClosing(context: &context, size: size, tint: tint, glow: glow)
            }
        }
    }

    private func drawAtmosphere(
        context: inout GraphicsContext,
        size: CGSize,
        top: Color,
        bottom: Color,
        glow: Color
    ) {
            let night = kind == .time
            let topColor = night
                ? (scheme == .dark
                    ? Color(red: 0.06, green: 0.08, blue: 0.18)
                    : Color(red: 0.28, green: 0.34, blue: 0.52))
                : top
            let bottomColor = night
                ? (scheme == .dark
                    ? Color(red: 0.04, green: 0.05, blue: 0.1)
                    : Color(red: 0.16, green: 0.18, blue: 0.3))
                : bottom
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .linearGradient(
                    Gradient(colors: [topColor, bottomColor]),
                    startPoint: CGPoint(x: size.width / 2, y: 0),
                    endPoint: CGPoint(x: size.width / 2, y: size.height)
                )
            )
        if kind != .badges {
            let sunY = kind == .time ? size.height * 0.2 : size.height * 0.16
            let sunSize: CGFloat = kind == .time ? 52 : 44
            let breathe = RecapSceneMotion.phase(6, at: motion)
            let sunRect = CGRect(x: size.width * 0.68, y: sunY, width: sunSize, height: sunSize)
            let sunColor = kind == .time ? Color.white.opacity(0.88) : glow
            context.fill(
                Path(ellipseIn: sunRect.insetBy(dx: -28, dy: -28)),
                with: .radialGradient(
                    Gradient(colors: [sunColor.opacity(0.28 + 0.32 * Double(breathe)), .clear]),
                    center: CGPoint(x: sunRect.midX, y: sunRect.midY),
                    startRadius: 6,
                    endRadius: 64 + 22 * breathe
                )
            )
            context.fill(Path(ellipseIn: sunRect), with: .color(sunColor.opacity(kind == .time ? 0.92 : 0.8)))
        }
        let compact = size.height <= RecapHubTeaserMetrics.posterHeight + 1
        if !compact {
            drawAmbientSparkles(context: &context, size: size, glow: glow)
        }
    }

    private func drawAmbientSparkles(context: inout GraphicsContext, size: CGSize, glow: Color) {
        let seeds: [(CGFloat, CGFloat, CGFloat)] = [
            (0.10, 0.14, 1.7),
            (0.22, 0.08, 2.3),
            (0.38, 0.16, 1.9),
            (0.54, 0.10, 2.6),
            (0.72, 0.13, 2.1),
            (0.88, 0.09, 1.8),
            (0.16, 0.28, 2.8),
            (0.84, 0.24, 2.4),
            (0.48, 0.22, 3.1),
            (0.64, 0.32, 2.0)
        ]
        let extra: [(CGFloat, CGFloat, CGFloat)] = kind == .badges
            ? [(0.08, 0.42, 2.2), (0.92, 0.38, 2.5), (0.30, 0.48, 1.9), (0.70, 0.52, 2.7)]
            : []
        for (index, seed) in (seeds + extra).enumerated() {
            let twinkle = RecapSceneMotion.phase(1.5 + Double(seed.2) * 0.18, at: motion + Double(index) * 0.41)
            guard twinkle > 0.18 else { continue }
            let drift = RecapSceneMotion.signedPhase(7.5, at: motion + Double(index)) * 6
            let point = CGPoint(x: size.width * seed.0 + drift, y: size.height * seed.1)
            drawSparkle(
                context: &context,
                at: point,
                brightness: twinkle,
                color: index.isMultiple(of: 3) ? glow : .white,
                scale: kind == .badges ? 1.15 : 0.85
            )
        }
    }

    private func drawSparkle(
        context: inout GraphicsContext,
        at point: CGPoint,
        brightness: CGFloat,
        color: Color,
        scale: CGFloat
    ) {
        let r = 1.15 * scale * (0.5 + 0.75 * brightness)
        context.fill(
            Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(
                Gradient(colors: [color.opacity(0.55 + 0.4 * Double(brightness)), .clear]),
                center: point,
                startRadius: 0.4,
                endRadius: r * 2.4
            )
        )
        let arm = r * 2.6
        let thin = max(0.55, r * 0.32)
        context.fill(
            Path(roundedRect: CGRect(x: point.x - thin / 2, y: point.y - arm, width: thin, height: arm * 2), cornerRadius: thin / 2),
            with: .color(Color.white.opacity(0.28 + 0.62 * Double(brightness)))
        )
        context.fill(
            Path(roundedRect: CGRect(x: point.x - arm, y: point.y - thin / 2, width: arm * 2, height: thin), cornerRadius: thin / 2),
            with: .color(Color.white.opacity(0.18 + 0.5 * Double(brightness)))
        )
    }

    private func drawIntro(context: inout GraphicsContext, size: CGSize, tint: Color, glow: Color) {
        drawVanishingRoad(context: &context, size: size, horizonY: size.height * 0.38, tint: tint)
        drawPlate(context: &context, size: size, tint: tint, glow: glow)
        let compact = size.height <= RecapHubTeaserMetrics.posterHeight + 1
        guard !compact else { return }
        let wave = RecapSceneMotion.signedPhase(4, at: motion)
        var flag = Path()
        let pole = CGPoint(x: size.width * 0.18, y: size.height * 0.28)
        flag.move(to: pole)
        flag.addLine(to: CGPoint(x: pole.x, y: pole.y + size.height * 0.22))
        context.stroke(flag, with: .color(.white.opacity(0.7)), lineWidth: 3)
        var cloth = Path()
        cloth.move(to: pole)
        cloth.addLine(to: CGPoint(x: pole.x + size.width * 0.16, y: pole.y + 8 + 10 * wave))
        cloth.addLine(to: CGPoint(x: pole.x, y: pole.y + size.height * 0.1))
        cloth.closeSubpath()
        context.fill(cloth, with: .color(tint.opacity(0.85)))
        context.stroke(cloth, with: .color(.white.opacity(0.45)), lineWidth: 1)
    }

    private func drawDistance(context: inout GraphicsContext, size: CGSize, tint: Color, glow: Color) {
        drawVanishingRoad(context: &context, size: size, horizonY: size.height * 0.5, tint: tint)
        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.42)
        let radius = min(size.width, size.height) * 0.28
        var arc = Path()
        arc.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(140),
            endAngle: .degrees(40),
            clockwise: false
        )
        context.stroke(arc, with: .color(.white.opacity(0.22)), style: StrokeStyle(lineWidth: 14, lineCap: .round))
        var fill = Path()
        let fillSweep = 110 + 28 * RecapSceneMotion.phase(6.5, at: motion)
        fill.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(140),
            endAngle: .degrees(140 + Double(fillSweep)),
            clockwise: false
        )
        context.stroke(fill, with: .color(tint), style: StrokeStyle(lineWidth: 14, lineCap: .round))
        for tick in 0..<9 {
            let angle = Angle.degrees(140 + Double(tick) * 28.75)
            let inner = point(on: center, radius: radius - 22, angle: angle)
            let outer = point(on: center, radius: radius - 8, angle: angle)
            var tickPath = Path()
            tickPath.move(to: inner)
            tickPath.addLine(to: outer)
            context.stroke(tickPath, with: .color(.white.opacity(0.55)), lineWidth: tick % 2 == 0 ? 2.5 : 1.2)
        }
        var needle = Path()
        needle.move(to: center)
        let sway = RecapSceneMotion.signedPhase(5.5, at: motion)
        needle.addLine(to: point(on: center, radius: radius - 18, angle: .degrees(232 + Double(16 * sway))))
        context.stroke(needle, with: .color(glow), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 8, y: center.y - 8, width: 16, height: 16)),
            with: .color(.white.opacity(0.9))
        )
    }

    private func drawCities(context: inout GraphicsContext, size: CGSize, tint: Color, glow: Color) {
        let drift = RecapSceneMotion.signedPhase(8, at: motion) * 14
        var skyline = context
        skyline.translateBy(x: drift, y: 0)
        let base = size.height * 0.52
        let widths: [CGFloat] = [0.07, 0.1, 0.06, 0.14, 0.08, 0.11, 0.07, 0.09, 0.06]
        let heights: [CGFloat] = [0.14, 0.28, 0.18, 0.38, 0.22, 0.32, 0.16, 0.24, 0.2]
        var x = size.width * 0.04
        var silhouette = Path()
        silhouette.move(to: CGPoint(x: 0, y: base))
        for index in widths.indices {
            let w = size.width * widths[index]
            let h = size.height * heights[index]
            silhouette.addLine(to: CGPoint(x: x, y: base))
            silhouette.addLine(to: CGPoint(x: x, y: base - h))
            if index == 1 || index == 3 || index == 5 {
                silhouette.addLine(to: CGPoint(x: x + w * 0.45, y: base - h - 16))
                silhouette.addLine(to: CGPoint(x: x + w, y: base - h))
            } else {
                silhouette.addLine(to: CGPoint(x: x + w, y: base - h))
            }
            silhouette.addLine(to: CGPoint(x: x + w, y: base))
            x += w + 6
        }
        silhouette.addLine(to: CGPoint(x: size.width, y: base))
        silhouette.addLine(to: CGPoint(x: size.width, y: size.height))
        silhouette.addLine(to: CGPoint(x: 0, y: size.height))
        silhouette.closeSubpath()
        skyline.fill(silhouette, with: .color(tint.opacity(0.42)))
        skyline.fill(
            Path(CGRect(x: 0, y: base, width: size.width, height: size.height - base)),
            with: .linearGradient(
                Gradient(colors: [tint.opacity(0.18), Color.black.opacity(0.2)]),
                startPoint: CGPoint(x: size.width / 2, y: base),
                endPoint: CGPoint(x: size.width / 2, y: size.height)
            )
        )
        for index in 0..<12 {
            let wx = size.width * (0.12 + CGFloat(index % 6) * 0.13)
            let wy = base - size.height * (0.08 + CGFloat(index / 6) * 0.1)
            let twinkle = RecapSceneMotion.phase(3.8, at: motion + Double(index) * 0.37)
            skyline.fill(
                Path(CGRect(x: wx, y: wy, width: 4, height: 7)),
                with: .color(glow.opacity(0.28 + 0.45 * Double(twinkle)))
            )
        }
    }

    private func drawRoute(context: inout GraphicsContext, size: CGSize, tint: Color, glow: Color) {
        drawVanishingRoad(context: &context, size: size, horizonY: size.height * 0.46, tint: tint)
        var arc = Path()
        let start = CGPoint(x: size.width * 0.16, y: size.height * 0.62)
        let end = CGPoint(x: size.width * 0.84, y: size.height * 0.48)
        let control = CGPoint(x: size.width * 0.5, y: size.height * 0.22)
        arc.move(to: start)
        arc.addQuadCurve(to: end, control: control)
        context.stroke(arc, with: .color(.white.opacity(0.28)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
        context.stroke(arc, with: .color(tint), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        let travel = RecapSceneMotion.saw(5.5, at: motion)
        let highlight = quadPoint(start: start, end: end, control: control, t: travel)
        context.fill(
            Path(ellipseIn: CGRect(x: highlight.x - 5, y: highlight.y - 5, width: 10, height: 10)),
            with: .color(.white.opacity(0.85))
        )
        let bob = RecapSceneMotion.signedPhase(5.5, at: motion) * 8
        drawPin(context: &context, at: CGPoint(x: start.x, y: start.y + bob), color: glow)
        drawPin(context: &context, at: CGPoint(x: end.x, y: end.y - bob), color: tint)
    }

    private func drawTime(context: inout GraphicsContext, size: CGSize, tint: Color, glow: Color) {
        drawVanishingRoad(context: &context, size: size, horizonY: size.height * 0.5, tint: tint, asphaltOpacity: 0.45)
        let driftX = RecapSceneMotion.signedPhase(8, at: motion) * 12
        let driftY = RecapSceneMotion.signedPhase(6.5, at: motion) * 8
        let moon = CGRect(x: size.width * 0.18 + driftX, y: size.height * 0.14 + driftY, width: 58, height: 58)
        context.fill(Path(ellipseIn: moon), with: .color(.white.opacity(0.9)))
        context.fill(
            Path(ellipseIn: moon.offsetBy(dx: 16, dy: -4)),
            with: .color(Color.black.opacity(scheme == .dark ? 0.45 : 0.18))
        )
        let stars = [0.42, 0.55, 0.68, 0.78, 0.32, 0.88]
        for (index, xRatio) in stars.enumerated() {
            let y = size.height * (0.12 + CGFloat(index % 3) * 0.07)
            let twinkle = RecapSceneMotion.phase(3.6, at: motion + Double(index) * 0.9)
            context.fill(
                Path(ellipseIn: CGRect(x: size.width * xRatio, y: y, width: 3, height: 3)),
                with: .color(.white.opacity(0.35 + 0.5 * Double(twinkle)))
            )
        }
        context.fill(
            Path(ellipseIn: CGRect(x: size.width * 0.62, y: size.height * 0.22, width: 10, height: 10)),
            with: .color(glow.opacity(0.55 + 0.25 * Double(RecapSceneMotion.phase(8, at: motion))))
        )
    }

    private func drawCategories(context: inout GraphicsContext, size: CGSize, tint: Color, glow: Color) {
        let horizon = CGPoint(x: size.width * 0.5, y: size.height * 0.4)
        var left = Path()
        left.move(to: horizon)
        left.addLine(to: CGPoint(x: size.width * 1.05, y: size.height * 1.02))
        left.addLine(to: CGPoint(x: size.width * 0.5, y: size.height * 1.02))
        left.closeSubpath()
        var right = Path()
        right.move(to: horizon)
        right.addLine(to: CGPoint(x: size.width * 0.5, y: size.height * 1.02))
        right.addLine(to: CGPoint(x: -size.width * 0.05, y: size.height * 1.02))
        right.closeSubpath()
        let breathe = RecapSceneMotion.phase(9, at: motion)
        context.fill(left, with: .color(tint.opacity(0.28 + 0.14 * Double(breathe))))
        context.fill(right, with: .color(glow.opacity(0.38 - 0.12 * Double(breathe))))
        var split = Path()
        split.move(to: horizon)
        split.addLine(to: CGPoint(x: size.width * 0.5, y: size.height))
        let dashPhase = RecapSceneMotion.saw(3.2, at: motion) * 18
        context.stroke(
            split,
            with: .color(.white.opacity(0.7)),
            style: StrokeStyle(lineWidth: 3, dash: [10, 8], dashPhase: dashPhase)
        )
        context.stroke(edge(from: horizon, to: CGPoint(x: size.width * 0.08, y: size.height)), with: .color(.white.opacity(0.35)), lineWidth: 2)
        context.stroke(edge(from: horizon, to: CGPoint(x: size.width * 0.92, y: size.height)), with: .color(.white.opacity(0.35)), lineWidth: 2)
    }

    private func drawCost(context: inout GraphicsContext, size: CGSize, tint: Color, glow: Color) {
        let pump = CGRect(x: size.width * 0.14, y: size.height * 0.28, width: size.width * 0.28, height: size.height * 0.34)
        context.fill(Path(roundedRect: pump, cornerRadius: 14), with: .color(tint.opacity(0.55)))
        context.fill(
            Path(roundedRect: CGRect(x: pump.minX + 16, y: pump.minY + 18, width: pump.width - 32, height: 36), cornerRadius: 8),
            with: .color(.white.opacity(0.22))
        )
        var hose = Path()
        let sway = RecapSceneMotion.signedPhase(4.5, at: motion)
        hose.move(to: CGPoint(x: pump.maxX - 8, y: pump.minY + 40))
        hose.addQuadCurve(
            to: CGPoint(x: pump.maxX + 28, y: pump.maxY - 24 + 14 * sway),
            control: CGPoint(x: pump.maxX + 46, y: pump.minY + 10 + 16 * sway)
        )
        context.stroke(hose, with: .color(.white.opacity(0.7)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        let card = CGRect(x: size.width * 0.52, y: size.height * 0.32, width: size.width * 0.34, height: size.height * 0.22)
        context.fill(Path(roundedRect: card, cornerRadius: 16), with: .color(.white.opacity(0.16)))
        context.stroke(Path(roundedRect: card, cornerRadius: 16), with: .color(glow.opacity(0.7)), lineWidth: 2)
        let sheenX = card.minX + card.width * RecapSceneMotion.saw(4.5, at: motion) * 0.7
        context.fill(
            Path(roundedRect: CGRect(x: sheenX, y: card.minY + 10, width: 18, height: card.height - 20), cornerRadius: 4),
            with: .color(.white.opacity(0.12))
        )
        context.fill(
            Path(roundedRect: CGRect(x: card.minX + 16, y: card.minY + 22, width: card.width * 0.42, height: 10), cornerRadius: 4),
            with: .color(.white.opacity(0.45))
        )
        context.fill(
            Path(roundedRect: CGRect(x: card.minX + 16, y: card.minY + 42, width: card.width * 0.62, height: 8), cornerRadius: 3),
            with: .color(.white.opacity(0.28))
        )
    }

    private func drawBadges(context: inout GraphicsContext, size: CGSize, tint _: Color, glow: Color) {
        let ids = Array(badgeIDs.prefix(RecapStoryBadgeLayout.maxVisible))
        guard !ids.isEmpty else { return }
        let slots = RecapStoryBadgeLayout.slots(in: size, count: ids.count)
        let medal = RecapStoryBadgeLayout.medalSize(in: size, count: ids.count)
        for (index, id) in ids.enumerated() {
            let offset = RecapStoryBadgeLayout.offsetY(index: index, motion: motion, reduceMotion: false)
            let rect = RecapStoryBadgeLayout.medalRect(in: slots[index], medal: medal, offsetY: offset)
            let pulse = RecapSceneMotion.phase(2.4, at: motion + Double(index) * 0.28)
            let accent = AchievementTheme.medalGlow(for: id, scheme: scheme)
            let haloPad = medal * 0.58
            context.fill(
                Path(ellipseIn: rect.insetBy(dx: -haloPad, dy: -haloPad)),
                with: .radialGradient(
                    Gradient(colors: [
                        accent.opacity(0.5 + 0.32 * Double(pulse)),
                        accent.opacity(0.16),
                        .clear
                    ]),
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    startRadius: medal * 0.12,
                    endRadius: medal * 1.05
                )
            )
            let sparkleCount = 5
            for sparkle in 0..<sparkleCount {
                let twinkle = RecapSceneMotion.phase(
                    1.35 + Double(sparkle) * 0.18,
                    at: motion + Double(index) * 0.21 + Double(sparkle) * 0.33
                )
                guard twinkle > 0.16 else { continue }
                let spin = RecapSceneMotion.saw(9.5, at: motion + Double(index) * 0.4) * .pi * 2
                let angle = (CGFloat(sparkle) / CGFloat(sparkleCount)) * .pi * 2 + CGFloat(index) * 0.35 + spin * 0.12
                let radius = medal * (0.68 + 0.14 * twinkle)
                let point = CGPoint(
                    x: rect.midX + cos(angle) * radius,
                    y: rect.midY + sin(angle) * radius
                )
                drawSparkle(
                    context: &context,
                    at: point,
                    brightness: twinkle,
                    color: sparkle.isMultiple(of: 2) ? accent : glow,
                    scale: 1.05
                )
            }
        }
    }

    private func drawClosing(context: inout GraphicsContext, size: CGSize, tint: Color, glow: Color) {
        let horizonY = size.height * 0.40
        drawVanishingRoad(context: &context, size: size, horizonY: horizonY, tint: tint)
        drawPlate(context: &context, size: size, tint: tint, glow: glow, yRatio: 0.12)

        let recede = 0.72 + 0.28 * RecapSceneMotion.phase(7, at: motion)
        let bob = RecapSceneMotion.signedPhase(5.5, at: motion) * 8
        let carW = size.width * 0.14 * recede
        let carH = size.height * 0.036 * recede
        let body = CGRect(
            x: size.width * 0.5 - carW / 2,
            y: horizonY + size.height * 0.05 + bob,
            width: carW,
            height: carH
        )
        var cabin = Path()
        cabin.move(to: CGPoint(x: body.minX + carW * 0.18, y: body.minY + carH * 0.35))
        cabin.addLine(to: CGPoint(x: body.minX + carW * 0.28, y: body.minY))
        cabin.addLine(to: CGPoint(x: body.maxX - carW * 0.28, y: body.minY))
        cabin.addLine(to: CGPoint(x: body.maxX - carW * 0.18, y: body.minY + carH * 0.35))
        cabin.closeSubpath()
        context.fill(Path(roundedRect: body, cornerRadius: carH * 0.35), with: .color(.black.opacity(scheme == .dark ? 0.55 : 0.38)))
        context.fill(cabin, with: .color(tint.opacity(0.55)))
        let lampPulse = 0.45 + 0.55 * RecapSceneMotion.phase(5.5, at: motion)
        let lampW = max(4, carW * 0.12)
        let lampH = max(3, carH * 0.28)
        let lampY = body.midY - lampH / 2
        context.fill(
            Path(ellipseIn: CGRect(x: body.minX + carW * 0.12, y: lampY, width: lampW, height: lampH)),
            with: .color(Color.red.opacity(0.35 + 0.45 * lampPulse))
        )
        context.fill(
            Path(ellipseIn: CGRect(x: body.maxX - carW * 0.12 - lampW, y: lampY, width: lampW, height: lampH)),
            with: .color(Color.red.opacity(0.35 + 0.45 * lampPulse))
        )
        var trail = Path()
        let trailY = body.midY
        trail.move(to: CGPoint(x: body.minX + carW * 0.18, y: trailY))
        trail.addLine(to: CGPoint(x: body.minX - size.width * 0.04, y: trailY + size.height * 0.12))
        trail.move(to: CGPoint(x: body.maxX - carW * 0.18, y: trailY))
        trail.addLine(to: CGPoint(x: body.maxX + size.width * 0.04, y: trailY + size.height * 0.12))
        context.stroke(
            trail,
            with: .color(glow.opacity(0.18 + 0.22 * Double(lampPulse))),
            style: StrokeStyle(lineWidth: 2, lineCap: .round)
        )
    }

    private func drawVanishingRoad(
        context: inout GraphicsContext,
        size: CGSize,
        horizonY: CGFloat,
        tint _: Color,
        asphaltOpacity: Double = 0.28
    ) {
        let horizon = CGPoint(x: size.width * 0.5, y: horizonY)
        var asphalt = Path()
        asphalt.move(to: horizon)
        asphalt.addLine(to: CGPoint(x: size.width * 1.08, y: size.height * 1.02))
        asphalt.addLine(to: CGPoint(x: -size.width * 0.08, y: size.height * 1.02))
        asphalt.closeSubpath()
        context.fill(asphalt, with: .color(Color.black.opacity(scheme == .dark ? asphaltOpacity : 0.16)))
        context.stroke(edge(from: horizon, to: CGPoint(x: size.width * 0.08, y: size.height)), with: .color(.white.opacity(0.35)), lineWidth: 2)
        context.stroke(edge(from: horizon, to: CGPoint(x: size.width * 0.92, y: size.height)), with: .color(.white.opacity(0.35)), lineWidth: 2)
        let shift = RecapSceneMotion.saw(4, at: motion)
        for step in 0..<8 {
            let unit = (CGFloat(step) / 8 + shift).truncatingRemainder(dividingBy: 1)
            let y = horizon.y + (size.height - horizon.y) * unit
            let width = 5 + 18 * unit
            let rect = CGRect(x: horizon.x - width / 2, y: y, width: width, height: 5 + 8 * unit)
            context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(.white.opacity(0.12 + 0.45 * Double(unit))))
        }
    }

    private func drawPlate(
        context: inout GraphicsContext,
        size: CGSize,
        tint: Color,
        glow: Color,
        yRatio: CGFloat = 0.2
    ) {
        let plate = CGRect(x: size.width * 0.36, y: size.height * yRatio, width: size.width * 0.28, height: size.width * 0.28)
        context.fill(Path(roundedRect: plate, cornerRadius: plate.width * 0.22), with: .color(tint.opacity(0.9)))
        context.stroke(Path(roundedRect: plate, cornerRadius: plate.width * 0.22), with: .color(.white.opacity(0.28)), lineWidth: 1.5)
        context.fill(
            Path(ellipseIn: CGRect(x: plate.midX - 10, y: plate.midY - 10, width: 20, height: 20)),
            with: .color(glow.opacity(0.85))
        )
    }

    private func drawPin(context: inout GraphicsContext, at point: CGPoint, color: Color) {
        context.fill(Path(ellipseIn: CGRect(x: point.x - 9, y: point.y - 22, width: 18, height: 18)), with: .color(color))
        var stem = Path()
        stem.move(to: CGPoint(x: point.x, y: point.y - 6))
        stem.addLine(to: point)
        context.stroke(stem, with: .color(color), style: StrokeStyle(lineWidth: 3, lineCap: .round))
    }

    private func quadPoint(start: CGPoint, end: CGPoint, control: CGPoint, t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
        )
    }

    private func point(on center: CGPoint, radius: CGFloat, angle: Angle) -> CGPoint {
        CGPoint(
            x: center.x + radius * CGFloat(cos(angle.radians)),
            y: center.y + radius * CGFloat(sin(angle.radians))
        )
    }

    private func edge(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        return path
    }
}
