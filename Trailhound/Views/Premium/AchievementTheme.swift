import SwiftUI

enum AchievementGalleryTokens {
    static let cardRadius: CGFloat = 16
    static let cardHeight: CGFloat = 196
    static let accessibilityMinHeight: CGFloat = 220
    static let medalSize: CGFloat = 48
    static let expandedMedalSize: CGFloat = 128
    static let compactMedalSize: CGFloat = 44
    /// Unlock overlay dwell before the next unseen badge.
    static let unlockDwell: TimeInterval = 3
    static let shareSlotHeight: CGFloat = 28
    static let titleSlotHeight: CGFloat = 28
    static let bodySlotHeight: CGFloat = 32
    static let statusSlotHeight: CGFloat = 14
}

/// Maps the Stats badges card onto the full-screen overlay. Grow/shrink the same
/// rounded rect — never a sheet insert.
enum AchievementGalleryExpandLayout {
    static let collapsedCornerRadius = StatsCardTokens.radius
    static let expandedCornerRadius: CGFloat = 0
    static let minimumSourceLength: CGFloat = 8

    static func localSurface(sourceGlobal: CGRect, overlayGlobal: CGRect, expanded: Bool) -> CGRect {
        let container = CGRect(origin: .zero, size: overlayGlobal.size)
        if expanded { return container }
        guard sourceGlobal.width >= minimumSourceLength, sourceGlobal.height >= minimumSourceLength else {
            return container
        }
        return CGRect(
            x: sourceGlobal.minX - overlayGlobal.minX,
            y: sourceGlobal.minY - overlayGlobal.minY,
            width: sourceGlobal.width,
            height: sourceGlobal.height
        )
    }

    static func cornerRadius(expanded: Bool) -> CGFloat {
        expanded ? expandedCornerRadius : collapsedCornerRadius
    }

    static func hasUsableSource(_ source: CGRect) -> Bool {
        source.width >= minimumSourceLength && source.height >= minimumSourceLength
    }
}

/// Shell-independent family colors for round medals only — cards stay glass.
/// Km medals use metal materials; other families use enamel (family hue) in the same 3D chrome.
enum AchievementTheme {
    /// Black wash over a full-color medal so locked discs stay saturated, not washed out.
    static let lockScrimOpacity: Double = 0.45

    static func familyHue(for family: AchievementFamily) -> Double {
        switch family {
        case .firstTrip: 142
        case .distance: 178
        case .business: 38
        case .streak: 24
        case .cities: 214
        case .night: 252
        case .routes: 278
        }
    }

    static func familyAccent(for id: AchievementID, scheme: ColorScheme, unlocked: Bool) -> Color {
        hsl(
            hue: familyHue(for: id.family),
            saturation: saturation(for: id, unlocked: unlocked, scheme: scheme),
            lightness: accentLightness(scheme: scheme, unlocked: unlocked)
        )
    }

    static func familyHighlight(for id: AchievementID, scheme: ColorScheme, unlocked: Bool) -> Color {
        hsl(
            hue: familyHue(for: id.family),
            saturation: saturation(for: id, unlocked: unlocked, scheme: scheme) * 0.9,
            lightness: min(0.86, accentLightness(scheme: scheme, unlocked: unlocked) + 0.16)
        )
    }

    static func medalPalette(for id: AchievementID, scheme: ColorScheme) -> AchievementMedalPalette {
        if let material = id.medalMaterial {
            return metalPalette(material, scheme: scheme)
        }
        let accent = familyAccent(for: id, scheme: scheme, unlocked: true)
        let highlight = familyHighlight(for: id, scheme: scheme, unlocked: true)
        let hue = familyHue(for: id.family)
        let sat = saturation(for: id, unlocked: true, scheme: scheme)
        let light = accentLightness(scheme: scheme, unlocked: true)
        return AchievementMedalPalette(
            faceHighlight: highlight,
            faceAccent: accent,
            rimHighlight: hsl(hue: hue, saturation: sat * 0.55, lightness: min(0.92, light + 0.28)),
            rimAccent: hsl(hue: hue, saturation: min(0.88, sat + 0.08), lightness: max(0.18, light - 0.14)),
            glyph: .white,
            glow: accent,
            specularOpacity: 0.35
        )
    }

    static func medalGlow(for id: AchievementID, scheme: ColorScheme) -> Color {
        medalPalette(for: id, scheme: scheme).glow
    }

    static func medalFill(for id: AchievementID, scheme: ColorScheme) -> LinearGradient {
        let palette = medalPalette(for: id, scheme: scheme)
        var colors = [palette.faceHighlight, palette.faceAccent]
        if let extra = palette.iridescent {
            colors = [palette.faceHighlight, extra, palette.faceAccent]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
    }

    private static func metalPalette(_ material: AchievementMedalMaterial, scheme: ColorScheme) -> AchievementMedalPalette {
        let dark = scheme == .dark
        switch material {
        case .silver:
            return AchievementMedalPalette(
                faceHighlight: hex(dark ? 0xA8B0B8 : 0xC8D0D8),
                faceAccent: hex(dark ? 0x6A747E : 0x8A949E),
                rimHighlight: hex(dark ? 0xD8DEE4 : 0xF2F5F7),
                rimAccent: hex(dark ? 0x4A5258 : 0x6E767E),
                glyph: hex(0x1A2230),
                glow: hex(dark ? 0xA8B0B8 : 0xC8D0D8),
                specularOpacity: 0.55
            )
        case .gold:
            return AchievementMedalPalette(
                faceHighlight: hex(dark ? 0xD4A84A : 0xF3D08A),
                faceAccent: hex(dark ? 0x9A6A12 : 0xC48A1A),
                rimHighlight: hex(dark ? 0xE8C878 : 0xFFE9B0),
                rimAccent: hex(dark ? 0x6A4408 : 0x8A5A10),
                glyph: hex(0x3A2208),
                glow: hex(dark ? 0xD4A84A : 0xF3D08A),
                specularOpacity: 0.45
            )
        case .platinum:
            // 10,000 km — saturated teal chrome (not gray metal).
            let highlight = hex(dark ? AchievementPlatinumSwatch.faceHighlightDark : AchievementPlatinumSwatch.faceHighlightLight)
            let accent = hex(dark ? AchievementPlatinumSwatch.faceAccentDark : AchievementPlatinumSwatch.faceAccentLight)
            return AchievementMedalPalette(
                faceHighlight: highlight,
                faceAccent: accent,
                rimHighlight: hex(dark ? 0xB8FFF8 : 0xE8FFFC),
                rimAccent: hex(dark ? 0x087F78 : 0x0A9088),
                glyph: .white,
                glow: highlight,
                specularOpacity: 0.50
            )
        case .diamond:
            // 100,000 km — saturated lavender chrome (not icy blue).
            let highlight = hex(dark ? AchievementDiamondSwatch.faceHighlightDark : AchievementDiamondSwatch.faceHighlightLight)
            let accent = hex(dark ? AchievementDiamondSwatch.faceAccentDark : AchievementDiamondSwatch.faceAccentLight)
            return AchievementMedalPalette(
                faceHighlight: highlight,
                faceAccent: accent,
                rimHighlight: hex(dark ? 0xF3E8FF : 0xFBF5FF),
                rimAccent: hex(dark ? 0x7C3AED : 0x8B5CF6),
                glyph: .white,
                glow: highlight,
                specularOpacity: 0.50
            )
        }
    }

    private static func saturation(for id: AchievementID, unlocked: Bool, scheme: ColorScheme) -> Double {
        let base: Double
        switch id.familyTier {
        case 3: base = 0.82
        case 2: base = 0.78
        case 1: base = 0.68
        default: base = 0.58
        }
        let lockedDrop = unlocked ? 0 : 0.12
        let darkBoost = scheme == .dark ? 0.06 : 0
        return min(0.88, max(0.28, base - lockedDrop + darkBoost))
    }

    private static func accentLightness(scheme: ColorScheme, unlocked: Bool) -> Double {
        if scheme == .dark {
            return unlocked ? 0.58 : 0.50
        }
        return unlocked ? 0.48 : 0.42
    }

    static func hex(_ rgb: UInt32) -> Color {
        Color(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }

    /// HSL with h in 0...360, s/l in 0...1.
    static func hsl(hue: Double, saturation: Double, lightness: Double) -> Color {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        let s = min(1, max(0, saturation))
        let l = min(1, max(0, lightness))
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let r: Double
        let g: Double
        let b: Double
        switch h * 6 {
        case 0..<1: r = c; g = x; b = 0
        case 1..<2: r = x; g = c; b = 0
        case 2..<3: r = 0; g = c; b = x
        case 3..<4: r = 0; g = x; b = c
        case 4..<5: r = x; g = 0; b = c
        default: r = c; g = 0; b = x
        }
        return Color(red: r + m, green: g + m, blue: b + m)
    }
}

/// 10,000 km platinum face — teal, not gray.
enum AchievementPlatinumSwatch {
    static let faceHighlightDark: UInt32 = 0x3EDDD4
    static let faceAccentDark: UInt32 = 0x14B2AA
    static let faceHighlightLight: UInt32 = 0x52E8E0
    static let faceAccentLight: UInt32 = 0x20C4BC
}

/// 100,000 km diamond face — lavender, not ice blue.
enum AchievementDiamondSwatch {
    static let faceHighlightDark: UInt32 = 0xD8B4FE
    static let faceAccentDark: UInt32 = 0xB794F6
    static let faceHighlightLight: UInt32 = 0xE9D5FF
    static let faceAccentLight: UInt32 = 0xC4B5FD
}

struct AchievementMedalPalette {
    let faceHighlight: Color
    let faceAccent: Color
    let rimHighlight: Color
    let rimAccent: Color
    let glyph: Color
    let glow: Color
    let specularOpacity: Double
    var iridescent: Color? = nil
}

/// Bezel, face, specular, and inner shade — one recipe for metal km medals and enamel families.
struct AchievementMedalChrome: View {
    let id: AchievementID
    var size: CGFloat

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.achievementIdleTime) private var idleTime

    var body: some View {
        let palette = AchievementTheme.medalPalette(for: id, scheme: colorScheme)
        let inset = max(2, size * 0.08)
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [palette.rimHighlight, palette.rimAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Circle()
                .fill(AchievementTheme.medalFill(for: id, scheme: colorScheme))
                .padding(inset)
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.black.opacity(0.18)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(inset)
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(palette.specularOpacity), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.28
                    )
                )
                .frame(width: size * 0.55, height: size * 0.28)
                .offset(x: -size * 0.08 + specularNudge, y: -size * 0.22)
                .allowsHitTesting(false)
            Circle()
                .strokeBorder(palette.rimHighlight.opacity(0.55), lineWidth: max(1, size * 0.035))
                .padding(inset * 0.45)
        }
        .frame(width: size, height: size)
    }

    private var specularNudge: CGFloat {
        guard let idleTime, !reduceMotion else { return 0 }
        let phase = AchievementMedalIdle.pingPong(at: idleTime, duration: 2.4)
        return (phase - 0.5) * 0.06 * size
    }
}

/// Idle motion for unlocked medals. Flag waves; distance nodes travel the S; night sky bobs and sparkles.
enum AchievementMedalIdle {
    static let flagWaveDuration: TimeInterval = 0.72
    static let flagWaveSwayDegrees: Double = 36
    static let flagWaveFold: CGFloat = 0.24
    static let flagWaveFlapDegrees: Double = 12

    static var pathTravelDuration: TimeInterval { AchievementDistancePathMotion.convoy.duration }
    static let nightBobDuration: TimeInterval = 1.8
    static let nightSparkleDuration: TimeInterval = 0.55
    /// Stats strip / gallery share one clock. TabView sets `animation = nil`, so `withAnimation` never runs there.
    static let compactClockInterval: TimeInterval = 1.0 / 12.0

    /// One-way drift of the moon and stars. Disc stays put.
    static func nightBobAmplitude(for size: CGFloat) -> CGFloat {
        min(4, max(2, size * 0.06))
    }

    static func discTilts(_ family: AchievementFamily) -> Bool {
        switch family {
        case .firstTrip, .distance, .night: false
        default: true
        }
    }

    /// Eased 0...1...0. Time-driven idle so medals still move when SwiftUI animation is nil.
    static func pingPong(at time: TimeInterval, duration: TimeInterval) -> CGFloat {
        guard duration > 0, time.isFinite else { return 0 }
        let cycle = time.truncatingRemainder(dividingBy: duration * 2)
        let linear = cycle < duration ? cycle / duration : 2 - cycle / duration
        return CGFloat(0.5 - 0.5 * cos(linear * .pi))
    }
}

private struct AchievementIdleTimeKey: EnvironmentKey {
    static let defaultValue: TimeInterval? = nil
}

extension EnvironmentValues {
    var achievementIdleTime: TimeInterval? {
        get { self[AchievementIdleTimeKey.self] }
        set { self[AchievementIdleTimeKey.self] = newValue }
    }
}

/// Race-flag flutter: rotate and fold from the leading edge (the pole).
struct AchievementFlagWaveEffect: ViewModifier {
    var isActive: Bool
    @Environment(\.achievementIdleTime) private var idleTime
    @State private var waving = false

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(
                .degrees(swayDegrees),
                axis: (x: 0.22, y: 1, z: 0.14),
                anchor: .leading,
                perspective: 0.32
            )
            .rotationEffect(.degrees(flapDegrees), anchor: .leading)
            .scaleEffect(x: foldScale, y: 1, anchor: .leading)
            .onAppear(perform: start)
            .onChange(of: isActive) { _, _ in
                start()
            }
    }

    private var phase: CGFloat {
        guard isActive else { return 0 }
        if let idleTime {
            return AchievementMedalIdle.pingPong(at: idleTime, duration: AchievementMedalIdle.flagWaveDuration)
        }
        return waving ? 1 : 0
    }

    private var swayDegrees: Double {
        guard isActive else { return 0 }
        return -AchievementMedalIdle.flagWaveSwayDegrees * 0.7
            + Double(phase) * AchievementMedalIdle.flagWaveSwayDegrees * 1.7
    }

    private var flapDegrees: Double {
        guard isActive else { return 0 }
        return (Double(phase) - 0.5) * 2 * AchievementMedalIdle.flagWaveFlapDegrees
    }

    private var foldScale: CGFloat {
        guard isActive else { return 1 }
        return 1 - AchievementMedalIdle.flagWaveFold + phase * AchievementMedalIdle.flagWaveFold
    }

    private func start() {
        guard isActive, idleTime == nil else {
            waving = false
            return
        }
        waving = false
        withAnimation(
            .easeInOut(duration: AchievementMedalIdle.flagWaveDuration)
            .repeatForever(autoreverses: true)
        ) {
            waving = true
        }
    }
}

/// Two nodes on the distance S. Each km metal uses a different choreography so
/// the ladder reads as rank, not four copies of the same ping-pong.
enum AchievementDistancePathMotion: Equatable, Sendable {
    /// Full-path pair, 100 km silver.
    case convoy
    /// Opposite ends meet at mid, 1,000 km gold.
    case rendezvous
    /// Each node patrols one half, 10,000 km platinum.
    case patrol
    /// Bloom from mid to the ends, 100,000 km diamond.
    case bloom

    static func `for`(_ material: AchievementMedalMaterial) -> Self {
        switch material {
        case .silver: .convoy
        case .gold: .rendezvous
        case .platinum: .patrol
        case .diamond: .bloom
        }
    }

    var duration: TimeInterval {
        switch self {
        case .convoy: 1.45
        case .rendezvous: 1.65
        case .patrol: 1.90
        case .bloom: 2.20
        }
    }

    /// Phase 0...1 (eased ping-pong). Index 0 and 1 are the two path nodes.
    func nodeProgress(phase: CGFloat, index: Int) -> CGFloat {
        let p = min(1, max(0, phase))
        let lead = index == 0
        switch self {
        case .convoy:
            return lead ? p : 0.14 + p * 0.72
        case .rendezvous:
            return lead ? p : 1 - p
        case .patrol:
            return lead ? p * 0.45 : 0.55 + (1 - p) * 0.45
        case .bloom:
            return lead ? 0.5 * (1 - p) : 0.5 + 0.5 * p
        }
    }
}

/// S-curve matching `point.bottomleft.forward.to.point.topright.scurvepath`.
enum AchievementDistancePath {
    static func curve(in size: CGSize) -> Path {
        var path = Path()
        path.move(to: point(at: 0, in: size))
        path.addCurve(to: point(at: 1, in: size), control1: control1(in: size), control2: control2(in: size))
        return path
    }

    static func point(at t: CGFloat, in size: CGSize) -> CGPoint {
        let t = min(1, max(0, t))
        let p0 = start(in: size)
        let p1 = end(in: size)
        let c1 = control1(in: size)
        let c2 = control2(in: size)
        let u = 1 - t
        let tt = t * t
        let uu = u * u
        return CGPoint(
            x: uu * u * p0.x + 3 * uu * t * c1.x + 3 * u * tt * c2.x + tt * t * p1.x,
            y: uu * u * p0.y + 3 * uu * t * c1.y + 3 * u * tt * c2.y + tt * t * p1.y
        )
    }

    static func start(in size: CGSize) -> CGPoint {
        let box = insetBox(in: size)
        return CGPoint(x: box.minX, y: box.minY + box.height * 0.78)
    }

    static func end(in size: CGSize) -> CGPoint {
        let box = insetBox(in: size)
        return CGPoint(x: box.maxX, y: box.minY + box.height * 0.22)
    }

    static func control1(in size: CGSize) -> CGPoint {
        let box = insetBox(in: size)
        return CGPoint(x: box.maxX, y: box.minY + box.height * 0.82)
    }

    static func control2(in size: CGSize) -> CGPoint {
        let box = insetBox(in: size)
        return CGPoint(x: box.minX, y: box.minY + box.height * 0.18)
    }

    private static func insetBox(in size: CGSize) -> CGRect {
        let inset = min(size.width, size.height) * 0.22
        return CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
    }
}

/// Start and end nodes travel the S. Path sampling is an
/// `AnimatableModifier` — View-level `Animatable` is a Swift 6 isolation error.
struct AchievementDistancePathGlyph: View {
    var size: CGFloat
    var isActive: Bool
    var ink: Color = .white
    var motion: AchievementDistancePathMotion = .rendezvous
    @Environment(\.achievementIdleTime) private var idleTime
    @State private var progress: CGFloat = 0

    var body: some View {
        Color.clear
            .modifier(AchievementDistancePathDraw(progress: displayedProgress, ink: ink, motion: motion))
            .frame(width: size, height: size)
            .onAppear(perform: start)
            .onChange(of: isActive) { _, _ in
                start()
            }
    }

    private var displayedProgress: CGFloat {
        guard isActive else { return 0 }
        if let idleTime {
            return AchievementMedalIdle.pingPong(at: idleTime, duration: motion.duration)
        }
        return progress
    }

    private func start() {
        guard isActive, idleTime == nil else {
            progress = 0
            return
        }
        progress = 0
        withAnimation(
            .easeInOut(duration: motion.duration)
            .repeatForever(autoreverses: true)
        ) {
            progress = 1
        }
    }
}

private struct AchievementDistancePathDraw: ViewModifier, Animatable {
    var progress: CGFloat
    var ink: Color
    var motion: AchievementDistancePathMotion

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        Canvas { context, canvasSize in
            let line = max(1.5, canvasSize.width * 0.08)
            context.stroke(
                AchievementDistancePath.curve(in: canvasSize),
                with: .color(ink),
                style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
            )
            let phase = min(1, max(0, progress))
            let radius = max(2.1, canvasSize.width * 0.09)
            let ringWidth = max(1.2, line * 0.85)
            for index in 0..<2 {
                let point = AchievementDistancePath.point(
                    at: motion.nodeProgress(phase: phase, index: index),
                    in: canvasSize
                )
                var ring = Path()
                ring.addEllipse(in: CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                context.stroke(ring, with: .color(ink), style: StrokeStyle(lineWidth: ringWidth))
            }
        }
    }
}

/// Crescent and stars drift together; stars sparkle. Disc stays put.
struct AchievementNightSkyGlyph: View {
    var size: CGFloat
    var isActive: Bool
    @Environment(\.achievementIdleTime) private var idleTime
    @State private var bobbing = false
    @State private var sparkle = false

    var body: some View {
        let moonFont: Font = size < 50 ? .body.weight(.semibold) : .title3.weight(.semibold)
        let starFont: Font = size < 50 ? .caption2.weight(.bold) : .caption.weight(.bold)
        ZStack {
            Image(systemName: "moon.fill")
                .font(moonFont)
                .foregroundStyle(.white)
                .offset(x: -size * 0.10)
            star(leading: true, font: starFont)
                .offset(x: size * 0.16, y: -size * 0.20)
            star(leading: false, font: starFont)
                .scaleEffect(0.72)
                .offset(x: size * 0.26, y: size * 0.02)
        }
        .frame(width: size, height: size)
        .offset(y: bobOffset)
        .onAppear(perform: start)
        .onChange(of: isActive) { _, _ in
            start()
        }
    }

    private var bobPhase: CGFloat {
        guard isActive else { return 0 }
        if let idleTime {
            return AchievementMedalIdle.pingPong(at: idleTime, duration: AchievementMedalIdle.nightBobDuration)
        }
        return bobbing ? 1 : 0
    }

    private var bobOffset: CGFloat {
        guard isActive else { return 0 }
        let amplitude = AchievementMedalIdle.nightBobAmplitude(for: size)
        return (bobPhase - 0.5) * 2 * amplitude
    }

    private var sparklePhase: CGFloat {
        guard isActive else { return 0 }
        if let idleTime {
            return AchievementMedalIdle.pingPong(at: idleTime, duration: AchievementMedalIdle.nightSparkleDuration)
        }
        return sparkle ? 1 : 0
    }

    private func star(leading: Bool, font: Font) -> some View {
        let lit = leading ? sparklePhase : 1 - sparklePhase
        return Image(systemName: "sparkle")
            .font(font)
            .foregroundStyle(.white)
            .scaleEffect(0.78 + 0.44 * lit)
            .opacity(0.42 + 0.58 * lit)
    }

    private func start() {
        guard isActive, idleTime == nil else {
            bobbing = false
            sparkle = false
            return
        }
        bobbing = false
        sparkle = false
        withAnimation(
            .easeInOut(duration: AchievementMedalIdle.nightBobDuration)
            .repeatForever(autoreverses: true)
        ) {
            bobbing = true
        }
        withAnimation(
            .easeInOut(duration: AchievementMedalIdle.nightSparkleDuration)
            .repeatForever(autoreverses: true)
        ) {
            sparkle = true
        }
    }
}

/// Dark disc + pale lock shared by Stats badges and Year in review.
struct AchievementMedalLockOverlay: View {
    var size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(AchievementTheme.lockScrimOpacity))
            Image(systemName: "lock.fill")
                .font(.system(size: Self.lockGlyphSize(for: size), weight: .bold))
                .foregroundStyle(GlassText.placeholder(for: colorScheme))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static func lockGlyphSize(for medalSize: CGFloat) -> CGFloat {
        max(13, medalSize * 0.36)
    }
}
