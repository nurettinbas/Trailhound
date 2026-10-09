import SwiftUI
import UIKit

// MARK: - Class

/// Screen class. Device model names are not stored.
enum TrailhoundLayoutClass: String, Equatable, Sendable {
    /// iPhone portrait and closed fold portrait. Existing single column.
    case phone
    /// iPhone landscape and closed fold landscape (compact vertical size class).
    case phoneLandscape
    /// Phone-family device with both size classes regular (open inner screen).
    case duoOpen
    /// iPad. Narrow Split View / Slide Over resolves to `phone`.
    case pad
}

enum TripDetailStyle: Equatable, Sendable {
    case overlay
    case split
    case floatingPanel
    case stacked
}

enum RecordingCardArrangement: Equatable, Sendable {
    case list
    case pane
    case banner
}

enum SettingsChrome: Equatable, Sendable {
    case form
    case split
    case grid
}

enum MapChrome: Equatable, Sendable {
    case bottomSheet
    case floatingTrailing
    case splitPane
}

enum TripDetailRegion: Equatable, Sendable {
    case automatic
    case details
    case map
}

struct TrailhoundLayoutSnapshot: Equatable, Sendable {
    var layoutClass: TrailhoundLayoutClass
    var size: CGSize
    var isLandscape: Bool

    static let phone = TrailhoundLayoutSnapshot(
        layoutClass: .phone,
        size: CGSize(width: 390, height: 844),
        isLandscape: false
    )

    var columnCount: Int {
        TrailhoundLayoutResolver.columnCount(layout: layoutClass, contentWidth: contentWidth)
    }

    var contentWidth: CGFloat {
        switch layoutClass {
        case .duoOpen where isLandscape:
            return max(0, (size.width - GlassTokens.hingeGutter) / 2)
        case .phoneLandscape:
            return size.width * (1 - GlassTokens.railWidthFraction)
        case .pad where isLandscape:
            return size.width * (1 - GlassTokens.railWidthFraction)
        default:
            return size.width
        }
    }

    var splitsTrips: Bool {
        switch layoutClass {
        case .phone:
            return false
        case .phoneLandscape:
            return true
        case .duoOpen:
            return isLandscape
        case .pad:
            return isLandscape
        }
    }

    var opensTripInPane: Bool { layoutClass != .phone }

    var embedsTripDetail: Bool { layoutClass != .phone }

    var tripDetailStyle: TripDetailStyle {
        switch layoutClass {
        case .phone:
            return .overlay
        case .duoOpen:
            return isLandscape ? .split : .overlay
        case .phoneLandscape:
            return .floatingPanel
        case .pad:
            return isLandscape ? .floatingPanel : .stacked
        }
    }

    var recordingCardArrangement: RecordingCardArrangement {
        switch layoutClass {
        case .phone:
            return .list
        case .pad where !isLandscape:
            return .banner
        case .duoOpen where !isLandscape:
            return .list
        default:
            return .pane
        }
    }

    /// Open fold held upright: the hinge runs across the middle. The recording card sits on it.
    var pinsRecordingCardToFold: Bool {
        layoutClass == .duoOpen && !isLandscape
    }

    /// Closed Duo cover, and the upright open fold when it is still shorter than a phone.
    /// The welcome column centers in that height instead of running off the top and bottom.
    var centersOnboardingColumn: Bool {
        if layoutClass == .duoOpen, !isLandscape { return true }
        guard layoutClass == .phone, size.width > 1 else { return false }
        return size.height / size.width < 1.75
    }

    /// Upright bottom sheet beside a side tab. The leading gap matches the margin
    /// between the card and the tab, not the width of the tab column.
    /// A normal phone has no trailing tab inset, so the sheet stays full-bleed.
    func duoSheetLeadingInset(matchingTrailingSafeArea trailing: CGFloat) -> CGFloat {
        guard tripDetailStyle == .overlay else { return 0 }
        guard trailing >= 44 else { return 0 }
        return GlassTokens.panelHorizontalInset
    }

    /// Phone and Duo put the camera and status cluster in the trailing corner.
    /// Full-screen collapse circles lead the title there. iPad keeps them trailing.
    var pinsOverlayCloseLeading: Bool {
        layoutClass != .pad
    }

    var hidesRecordingCardFromList: Bool {
        recordingCardArrangement == .pane || pinsRecordingCardToFold
    }

    var mapChrome: MapChrome {
        switch layoutClass {
        case .phone:
            return .bottomSheet
        case .duoOpen:
            return isLandscape ? .splitPane : .bottomSheet
        case .phoneLandscape, .pad:
            return .floatingTrailing
        }
    }

    var settingsChrome: SettingsChrome {
        switch layoutClass {
        case .phone:
            return .form
        case .phoneLandscape, .duoOpen:
            return .split
        case .pad:
            return isLandscape ? .split : .grid
        }
    }

    var badgeColumnCount: Int {
        TrailhoundLayoutResolver.badgeColumnCount(
            layout: layoutClass,
            isLandscape: isLandscape,
            accessibility: false
        )
    }

    var showsHeroRail: Bool {
        layoutClass == .phoneLandscape || (layoutClass == .pad && isLandscape)
    }

    var storyStageMaxWidth: CGFloat? {
        switch layoutClass {
        case .phone:
            return nil
        case .phoneLandscape, .duoOpen, .pad:
            return min(size.height * 9 / 16, size.width * 0.46)
        }
    }

    func hingeFrame() -> CGRect {
        TrailhoundLayoutResolver.hingeFrame(in: size, gutter: GlassTokens.hingeGutter)
    }
}

/// Trailing gap between a full-bleed container and the window edge: the side-tab column.
@MainActor
enum TrailhoundSideTabGap {
    static func trailing(in geometry: GeometryProxy, layoutDirection: LayoutDirection) -> CGFloat {
        let safe = geometry.safeAreaInsets.trailing
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first
        guard let window else { return safe }
        let frame = geometry.frame(in: .global)
        let measured: CGFloat
        if frame.width > 1, frame.height > 1 {
            let raw = layoutDirection == .rightToLeft
                ? frame.minX
                : window.bounds.width - frame.maxX
            measured = raw > 0 && raw < frame.width ? raw : 0
        } else {
            measured = 0
        }
        let windowEdge = layoutDirection == .rightToLeft ? window.safeAreaInsets.left : window.safeAreaInsets.right
        return max(safe, windowEdge, measured, sideColumnWidth(in: window))
    }

    /// Vertical tab bar width. A bottom bar is wide and short, so it returns 0.
    private static func sideColumnWidth(in window: UIWindow) -> CGFloat {
        guard let bar = findTabBar(in: window) else { return 0 }
        guard bar.bounds.height > bar.bounds.width * 1.4, bar.bounds.width >= 44 else { return 0 }
        return bar.bounds.width
    }

    private static func findTabBar(in view: UIView) -> UITabBar? {
        if let bar = view as? UITabBar { return bar }
        for child in view.subviews {
            if let found = findTabBar(in: child) { return found }
        }
        return nil
    }
}

enum TrailhoundLayoutResolver {
    /// Open inner screen when a size class stays compact: the long side is two phones.
    static let openFoldSpan: CGFloat = 1100

    /// A camera write while the window is turning cancels the orientation change.
    /// A sheet only changes height. A turn flips the aspect, or moves both axes together.
    static func viewportChangeCancelsRotation(from old: CGSize, to new: CGSize) -> Bool {
        guard old.width > 1, old.height > 1, new.width > 1, new.height > 1 else { return false }
        let widthDelta = abs(new.width - old.width)
        let heightDelta = abs(new.height - old.height)
        let aspectFlipped = (old.width > old.height) != (new.width > new.height)
        if aspectFlipped { return true }
        return widthDelta > 12 && heightDelta > 12
    }

    static func resolve(
        horizontal: UserInterfaceSizeClass?,
        vertical: UserInterfaceSizeClass?,
        size: CGSize,
        idiom: UIUserInterfaceIdiom,
        debugOverride: TrailhoundLayoutClass? = nil
    ) -> TrailhoundLayoutClass {
        if let override = debugOverride ?? TrailhoundLayoutDebug.forcedClass {
            return override
        }
        let narrow = size.width > 0 && size.width < GlassTokens.compactWidthCeiling
        if idiom == .pad {
            if horizontal == .compact || narrow {
                return .phone
            }
            return .pad
        }
        if vertical == .compact {
            return .phoneLandscape
        }
        // Open inner screen. Portrait is often under 700pt wide, and some folds keep a
        // compact horizontal size class while the height is two phones stacked.
        if horizontal == .regular, vertical == .regular {
            return .duoOpen
        }
        if size.height >= openFoldSpan, size.height > size.width {
            return .duoOpen
        }
        if size.width >= openFoldSpan, size.width > size.height {
            return .duoOpen
        }
        return .phone
    }

    static func snapshot(
        horizontal: UserInterfaceSizeClass?,
        vertical: UserInterfaceSizeClass?,
        size: CGSize,
        idiom: UIUserInterfaceIdiom
    ) -> TrailhoundLayoutSnapshot {
        let resolved = resolve(
            horizontal: horizontal,
            vertical: vertical,
            size: size,
            idiom: idiom
        )
        let landscape = size.width > size.height && size.height > 0
        return TrailhoundLayoutSnapshot(
            layoutClass: resolved,
            size: size,
            isLandscape: landscape
        )
    }

    /// Half tiles stay between `moduleMinHalf` and `moduleMaxHalf`. Extra width adds a column.
    static func columnCount(layout: TrailhoundLayoutClass, contentWidth: CGFloat) -> Int {
        let width = max(contentWidth, 1)
        var columns: Int
        switch layout {
        case .phone, .phoneLandscape, .duoOpen:
            columns = 2
        case .pad:
            columns = 4
        }
        while columns < 8, halfWidth(columns: columns, contentWidth: width) > GlassTokens.moduleMaxHalf {
            columns += 1
        }
        while columns > 1, halfWidth(columns: columns, contentWidth: width) < GlassTokens.moduleMinHalf {
            columns -= 1
        }
        return columns
    }

    static func halfWidth(columns: Int, contentWidth: CGFloat) -> CGFloat {
        let count = max(columns, 1)
        let gaps = StatsCardTokens.pairSpacing * CGFloat(count - 1)
        return (contentWidth - gaps) / CGFloat(count)
    }

    static func badgeColumnCount(
        layout: TrailhoundLayoutClass,
        isLandscape: Bool,
        accessibility: Bool
    ) -> Int {
        if accessibility { return 1 }
        switch layout {
        case .phone:
            return 2
        case .phoneLandscape:
            return 4
        case .duoOpen:
            return isLandscape ? 4 : 3
        case .pad:
            return isLandscape ? 6 : 4
        }
    }

    static func hingeFrame(in size: CGSize, gutter: CGFloat = GlassTokens.hingeGutter) -> CGRect {
        let width = min(gutter, size.width)
        let x = (size.width - width) / 2
        return CGRect(x: x, y: 0, width: width, height: size.height)
    }

    static func frameIntersectsHinge(_ frame: CGRect, container: CGSize, gutter: CGFloat = GlassTokens.hingeGutter) -> Bool {
        frame.intersects(hingeFrame(in: container, gutter: gutter))
    }

    /// List stays on the leading edge. Right-to-left mirrors it onto the visual right.
    static func listIsOnVisualLeft(direction: LayoutDirection) -> Bool {
        direction == .leftToRight
    }

    /// Width of the leading pane so the gutter sits on the window midpoint (the fold).
    /// A trailing tab column makes the content narrower than the window; splitting that
    /// content in half lands the seam off the hinge.
    static func duoLeadingPaneWidth(
        contentOriginX: CGFloat,
        contentWidth: CGFloat,
        windowWidth: CGFloat,
        gutter: CGFloat,
        listOnVisualLeft: Bool
    ) -> CGFloat {
        let fallback = max(0, (contentWidth - gutter) / 2)
        guard windowWidth > 1, contentWidth > 1 else { return fallback }
        let hinge = windowWidth / 2
        let halfGutter = gutter / 2
        let raw = listOnVisualLeft
            ? hinge - halfGutter - contentOriginX
            : (contentOriginX + contentWidth) - (hinge + halfGutter)
        guard raw > 0, raw < contentWidth else { return fallback }
        let minimum = min(160, fallback)
        let maximum = max(minimum, contentWidth - gutter - minimum)
        return min(max(raw, minimum), maximum)
    }
}

enum TrailhoundWindowSpace {
    static let name = "trailhound.window"
}

/// The tab column is a safe-area inset. SwiftUI’s named-space width is the
/// inset content, so a 50/50 split lands beside the fold and the system white
/// background shows through on the other screen. This reads the content rect
/// in the UIKit window, whose midpoint is the hinge.
struct TrailhoundWindowFrameReader: UIViewRepresentable {
    var onChange: (CGRect, CGSize) -> Void

    func makeUIView(context: Context) -> Probe {
        Probe()
    }

    func updateUIView(_ uiView: Probe, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChange = onChange
        uiView.onLayout = { [weak coordinator] frame, windowSize in
            coordinator?.publish(frame: frame, windowSize: windowSize)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    final class Probe: UIView {
        var onLayout: ((CGRect, CGSize) -> Void)?
        private var pending: (CGRect, CGSize)?
        private var coalesce: DispatchWorkItem?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            isAccessibilityElement = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard let window else { return }
            let frame = convert(bounds, to: window)
            let windowSize = window.bounds.size
            guard frame.width > 1, frame.height > 1, windowSize.width > 1, windowSize.height > 1 else { return }
            pending = (frame, windowSize)
            coalesce?.cancel()
            // Fold and rotate layout every frame. Writing SwiftUI state from here
            // restarts the reflow spring and never lets the next tab draw.
            let work = DispatchWorkItem { [weak self] in
                guard let self, let pending = self.pending else { return }
                self.pending = nil
                self.onLayout?(pending.0, pending.1)
            }
            coalesce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        }
    }

    final class Coordinator {
        var onChange: (CGRect, CGSize) -> Void
        private var lastFrame: CGRect = .null
        private var lastWindowSize: CGSize = CGSize(width: -1, height: -1)

        init(onChange: @escaping (CGRect, CGSize) -> Void) {
            self.onChange = onChange
        }

        func publish(frame: CGRect, windowSize: CGSize) {
            let moved = abs(frame.minX - lastFrame.minX) > 2
                || abs(frame.minY - lastFrame.minY) > 2
                || abs(frame.width - lastFrame.width) > 2
                || abs(frame.height - lastFrame.height) > 2
                || abs(windowSize.width - lastWindowSize.width) > 2
                || abs(windowSize.height - lastWindowSize.height) > 2
            guard moved else { return }
            lastFrame = frame
            lastWindowSize = windowSize
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                onChange(frame, windowSize)
            }
        }
    }
}

enum TrailhoundLayoutDebug {
    static var forcedClass: TrailhoundLayoutClass? {
        #if DEBUG
        guard let raw = UserDefaults.standard.string(forKey: "trailhound.layout.debugClass") else {
            return nil
        }
        return TrailhoundLayoutClass(rawValue: raw)
        #else
        return nil
        #endif
    }
}

// MARK: - Environment

private struct TrailhoundLayoutKey: EnvironmentKey {
    static let defaultValue = TrailhoundLayoutSnapshot.phone
}

private struct TripDetailRegionKey: EnvironmentKey {
    static let defaultValue = TripDetailRegion.automatic
}

extension EnvironmentValues {
    var trailhoundLayout: TrailhoundLayoutSnapshot {
        get { self[TrailhoundLayoutKey.self] }
        set { self[TrailhoundLayoutKey.self] = newValue }
    }

    var tripDetailRegion: TripDetailRegion {
        get { self[TripDetailRegionKey.self] }
        set { self[TripDetailRegionKey.self] = newValue }
    }
}

// MARK: - Module grid

enum TrailhoundModuleSpan: Hashable {
    case full
    case half
    case feature
}

private struct TrailhoundModuleSpanKey: LayoutValueKey {
    static let defaultValue = TrailhoundModuleSpan.full
}

extension View {
    func moduleSpan(_ span: TrailhoundModuleSpan) -> some View {
        layoutValue(key: TrailhoundModuleSpanKey.self, value: span)
    }

    /// Centers a card at the pane max width. The glass surface itself does not stretch.
    func trailhoundPaneCard() -> some View {
        frame(maxWidth: GlassTokens.paneCardMaxWidth)
            .frame(maxWidth: .infinity)
    }

    func trailhoundReadableColumn() -> some View {
        frame(maxWidth: GlassTokens.readableTextWidth)
            .frame(maxWidth: .infinity)
    }
}

struct TrailhoundModuleGridCache {
    var columns: Int
    var width: CGFloat
}

struct TrailhoundModuleGrid: Layout {
    var layoutClass: TrailhoundLayoutClass
    var spacing: CGFloat = StatsCardTokens.pairSpacing

    func makeCache(subviews: Subviews) -> TrailhoundModuleGridCache {
        TrailhoundModuleGridCache(columns: 2, width: 0)
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout TrailhoundModuleGridCache
    ) -> CGSize {
        let width = proposal.width ?? cache.width
        let columns = TrailhoundLayoutResolver.columnCount(layout: layoutClass, contentWidth: width)
        cache = TrailhoundModuleGridCache(columns: columns, width: width)
        let frames = frames(for: subviews, width: width, columns: columns)
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout TrailhoundModuleGridCache
    ) {
        let columns = cache.width == bounds.width
            ? cache.columns
            : TrailhoundLayoutResolver.columnCount(layout: layoutClass, contentWidth: bounds.width)
        let frames = frames(for: subviews, width: bounds.width, columns: columns)
        for index in subviews.indices {
            let frame = frames[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func frames(for subviews: Subviews, width: CGFloat, columns: Int) -> [CGRect] {
        let count = max(columns, 1)
        let cell = TrailhoundLayoutResolver.halfWidth(columns: count, contentWidth: width)
        var frames: [CGRect] = []
        var column = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rowStart = 0

        func closeRow() {
            guard rowStart < frames.count else { return }
            for index in rowStart..<frames.count {
                frames[index].size.height = rowHeight
            }
            y += rowHeight
            column = 0
            rowHeight = 0
            rowStart = frames.count
        }

        for subview in subviews {
            let span = subview[TrailhoundModuleSpanKey.self]
            let need: Int
            switch span {
            case .half:
                need = 1
            case .full:
                need = count
            case .feature:
                need = min(2, count)
            }
            if column > 0, column + need > count {
                y += spacing
                closeRow()
            }
            let itemWidth = cell * CGFloat(need) + spacing * CGFloat(max(need - 1, 0))
            let measured = subview.sizeThatFits(
                ProposedViewSize(width: itemWidth, height: span == .feature ? GlassTokens.featureHeight : nil)
            ).height
            let height = span == .feature ? max(measured, GlassTokens.featureHeight) : measured
            let x = CGFloat(column) * (cell + spacing)
            frames.append(CGRect(x: x, y: y, width: itemWidth, height: height))
            rowHeight = max(rowHeight, height)
            column += need
            if column >= count {
                closeRow()
            }
        }
        if column > 0 {
            closeRow()
        }
        return frames
    }
}

// MARK: - Hero, split, map

struct TrailhoundHeroRail<Title: View, Figure: View, Detail: View>: View {
    var collapsed: Bool
    @ViewBuilder var title: () -> Title
    @ViewBuilder var figure: () -> Figure
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            title()
                .font(.subheadline.weight(.semibold))
                .glassSecondaryInk()
            if collapsed {
                figure()
                    .font(.title3.weight(.semibold))
                    .glassPrimaryInk()
                    .lineLimit(1)
            } else {
                figure()
                    .font(GlassTokens.heroFigureFont)
                    .glassPrimaryInk()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                detail()
                    .font(.subheadline)
                    .glassSecondaryInk()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Open-fold Recap. Two columns meet on the hinge. Each next card drops into the
/// shorter column so a short card does not leave a hole beside a taller one.
struct TrailhoundHingeMasonry: Layout {
    var leadingWidth: CGFloat?
    var columnGap: CGFloat = GlassTokens.hingeGutter
    var rowSpacing: CGFloat = StatsCardTokens.pairSpacing

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let frames = frames(for: subviews, width: width)
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(for: subviews, width: bounds.width)
        for index in subviews.indices {
            let frame = frames[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func frames(for subviews: Subviews, width: CGFloat) -> [CGRect] {
        let lead = resolvedLeading(width: width)
        let trail = max(0, width - columnGap - lead)
        let widths = [lead, trail]
        let origins = [CGFloat(0), lead + columnGap]
        var cursor = [CGFloat(0), CGFloat(0)]
        var frames: [CGRect] = []
        for subview in subviews {
            let column = cursor[0] <= cursor[1] ? 0 : 1
            let size = subview.sizeThatFits(ProposedViewSize(width: widths[column], height: nil))
            frames.append(CGRect(x: origins[column], y: cursor[column], width: widths[column], height: size.height))
            cursor[column] += size.height + rowSpacing
        }
        return frames
    }

    private func resolvedLeading(width: CGFloat) -> CGFloat {
        let fallback = max(0, (width - columnGap) / 2)
        guard let leadingWidth, leadingWidth > 1 else { return fallback }
        return min(max(leadingWidth, 1), max(width - columnGap - 1, 1))
    }
}

/// Measures the row in the window and packs `TrailhoundHingeMasonry` onto the fold.
struct TrailhoundHingeCardStack<Content: View>: View {
    @Environment(\.trailhoundLayout) private var layout
    @Environment(\.layoutDirection) private var layoutDirection
    @ViewBuilder var content: () -> Content

    @State private var contentInWindow: CGRect = .zero
    @State private var measuredWindowWidth: CGFloat = 0

    var body: some View {
        TrailhoundHingeMasonry(leadingWidth: leadingWidth) {
            content()
        }
        .statsCardListRow()
        .background {
            TrailhoundWindowFrameReader { frame, windowSize in
                guard frame != contentInWindow || windowSize.width != measuredWindowWidth else { return }
                contentInWindow = frame
                measuredWindowWidth = windowSize.width
            }
        }
    }

    private var leadingWidth: CGFloat? {
        let windowWidth = measuredWindowWidth > 1 ? measuredWindowWidth : layout.size.width
        let contentWidth = contentInWindow.width > 1 ? contentInWindow.width : layout.size.width
        let origin = contentInWindow.width > 1 ? contentInWindow.minX : 0
        guard contentWidth > 1, windowWidth > 1 else { return nil }
        return TrailhoundLayoutResolver.duoLeadingPaneWidth(
            contentOriginX: origin,
            contentWidth: contentWidth,
            windowWidth: windowWidth,
            gutter: GlassTokens.hingeGutter,
            listOnVisualLeft: TrailhoundLayoutResolver.listIsOnVisualLeft(direction: layoutDirection)
        )
    }
}

/// Leading pane is the list. Focus is the live surface. Right-to-left mirrors the stack.
/// The gutter is centered on the window, not on the tab-inset content, so it sits on the fold.
struct TrailhoundPaneSplit<Leading: View, Focus: View>: View {
    @Environment(\.trailhoundLayout) private var layout
    @Environment(\.layoutDirection) private var layoutDirection
    var gutter: CGFloat?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var focus: () -> Focus

    @State private var contentInWindow: CGRect = .zero
    @State private var measuredWindowWidth: CGFloat = 0

    var body: some View {
        let gap = gutter ?? defaultGutter
        split(gap: gap, leadingWidth: leadingWidth(gap: gap))
            .background {
                AtmosphericBackground()
                    .ignoresSafeArea()
                TrailhoundWindowFrameReader { frame, windowSize in
                    guard frame != contentInWindow || windowSize.width != measuredWindowWidth else { return }
                    contentInWindow = frame
                    measuredWindowWidth = windowSize.width
                }
            }
    }

    private func leadingWidth(gap: CGFloat) -> CGFloat? {
        let windowWidth = measuredWindowWidth > 1 ? measuredWindowWidth : layout.size.width
        let contentWidth = contentInWindow.width
        let origin = contentInWindow.minX
        guard contentWidth > 1, windowWidth > 1 else { return nil }
        return TrailhoundLayoutResolver.duoLeadingPaneWidth(
            contentOriginX: origin,
            contentWidth: contentWidth,
            windowWidth: windowWidth,
            gutter: gap,
            listOnVisualLeft: TrailhoundLayoutResolver.listIsOnVisualLeft(direction: layoutDirection)
        )
    }

    private func split(gap: CGFloat, leadingWidth: CGFloat?) -> some View {
        HStack(spacing: gap) {
            leading()
                .frame(width: leadingWidth)
                .frame(maxWidth: leadingWidth == nil ? .infinity : nil, maxHeight: .infinity)
                .clipShape(Rectangle())
            focus()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(Rectangle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var defaultGutter: CGFloat {
        if layout.layoutClass == .pad, layout.isLandscape {
            return GlassTokens.padLandscapeGap
        }
        if layout.layoutClass == .duoOpen {
            return GlassTokens.hingeGutter
        }
        return GlassTokens.hingeGutter
    }
}

/// Portrait open fold. The top pane ends on the horizontal hinge; the list fills below it.
struct TrailhoundFoldStack<Top: View, Bottom: View>: View {
    var gutter: CGFloat = GlassTokens.hingeGutter
    @ViewBuilder var top: () -> Top
    @ViewBuilder var bottom: () -> Bottom

    @State private var contentInWindow: CGRect = .zero
    @State private var measuredWindowHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: gutter) {
            top()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .frame(height: topHeight)
                .clipShape(Rectangle())
            bottom()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(Rectangle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            AtmosphericBackground()
                .ignoresSafeArea()
            TrailhoundWindowFrameReader { frame, windowSize in
                guard frame != contentInWindow || windowSize.height != measuredWindowHeight else { return }
                contentInWindow = frame
                measuredWindowHeight = windowSize.height
            }
        }
    }

    private var topHeight: CGFloat? {
        let contentHeight = contentInWindow.height
        let windowHeight = measuredWindowHeight
        guard contentHeight > 1, windowHeight > 1 else { return nil }
        return TrailhoundLayoutResolver.duoLeadingPaneWidth(
            contentOriginX: contentInWindow.minY,
            contentWidth: contentHeight,
            windowWidth: windowHeight,
            gutter: gutter,
            listOnVisualLeft: true
        )
    }
}

struct TrailhoundMapCanvas<MapContent: View, Panel: View>: View {
    @Environment(\.trailhoundLayout) private var layout
    @Binding var panelCollapsed: Bool
    @ViewBuilder var map: () -> MapContent
    @ViewBuilder var panel: () -> Panel

    var body: some View {
        switch layout.mapChrome {
        case .bottomSheet:
            ZStack(alignment: .bottom) {
                map()
                panel()
            }
        case .floatingTrailing:
            ZStack(alignment: .trailing) {
                map()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if !panelCollapsed {
                    panel()
                        .frame(width: GlassTokens.floatingPanelWidth)
                        .frame(maxHeight: .infinity)
                        .padding(.trailing, 16)
                        .padding(.vertical, 12)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                VStack {
                    HStack {
                        Spacer()
                        GlassToolbarCollapseButton(
                            accessibilityIdentifier: "layout.map.panel.collapse",
                            action: { panelCollapsed.toggle() }
                        )
                            .padding(.top, 8)
                            .padding(.trailing, 12)
                    }
                    Spacer()
                }
            }
        case .splitPane:
            TrailhoundPaneSplit {
                panel()
            } focus: {
                map()
            }
        }
    }
}

struct TrailhoundAdaptiveSheet: ViewModifier {
    @Environment(\.trailhoundLayout) private var layout

    func body(content: Content) -> some View {
        if layout.layoutClass == .pad {
            if #available(iOS 18.0, *) {
                content
                    .presentationSizing(.form)
                    .frame(maxWidth: 560)
            } else {
                content.frame(maxWidth: 560)
            }
        } else {
            content
        }
    }
}

extension View {
    func trailhoundAdaptiveSheet() -> some View {
        modifier(TrailhoundAdaptiveSheet())
    }
}
