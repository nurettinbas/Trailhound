import SwiftUI
import UIKit

enum GlassTokens {
    static let cardRadius: CGFloat = 22
    static let chipRadius: CGFloat = 14
    static let sectionSpacing: CGFloat = 14
    /// Distance from screen edge to the glass card rim.
    static let panelHorizontalInset: CGFloat = 16
    /// Padding between the glass card rim and its content (both sides).
    static let cardContentInset: CGFloat = 12
    /// List row content inset from the screen edge (`panel` + inner content padding).
    static var listContentHorizontalInset: CGFloat { panelHorizontalInset + cardContentInset }

    static func fieldFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(LightGlassPalette.fieldFillOpacity)
    }

    /// Frosted panel look without `Material` (keyboard-friendly forms).
    static func formPanelFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(LightGlassPalette.formPanelFillOpacity)
    }

    static var solidFallback: Color {
        Color(.secondarySystemGroupedBackground)
    }
}

enum GlassDensity {
    case panel
    case chrome

    func material(for scheme: ColorScheme) -> Material {
        .ultraThinMaterial
    }

    func frostOpacity(for scheme: ColorScheme) -> Double {
        switch self {
        case .panel:
            scheme == .dark ? 0.06 : LightGlassPalette.panelFillOpacity
        case .chrome:
            scheme == .dark ? 0.04 : LightGlassPalette.chromeFillOpacity
        }
    }

    func brandTintOpacity(for scheme: ColorScheme) -> Double {
        switch self {
        case .panel:
            scheme == .dark ? 0.20 : 0.22
        case .chrome:
            scheme == .dark ? 0.14 : 0.12
        }
    }

    func rimOpacity(for scheme: ColorScheme) -> Double {
        guard scheme == .light else { return 0 }
        switch self {
        case .panel: return LightGlassPalette.panelRimOpacity
        case .chrome: return LightGlassPalette.chromeRimOpacity
        }
    }
}

enum GlassRowPosition {
    case only
    case first
    case middle
    case last

    static func index(_ index: Int, in count: Int) -> GlassRowPosition {
        guard count > 1 else { return .only }
        if index == 0 { return .first }
        if index == count - 1 { return .last }
        return .middle
    }

    var topRadius: CGFloat {
        switch self {
        case .only, .first: GlassTokens.cardRadius
        case .middle, .last: 0
        }
    }

    var bottomRadius: CGFloat {
        switch self {
        case .only, .last: GlassTokens.cardRadius
        case .first, .middle: 0
        }
    }
}

/// Soft color wash behind frosted panels — visible through glass, not a flat blue screen.
struct AtmosphericBackground: View {
    enum Style {
        case full
        case lightweight
        /// System canvas + soft brand glows — for onboarding / surfaces that should follow light/dark, not the blue shell.
        case canvas
    }

    var style: Style = .full

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        Group {
            if style == .canvas && colorScheme == .dark {
                Color(.systemBackground)
            } else {
                LinearGradient(
                    colors: gradientColors,
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        // Overlay, not a ZStack sibling: the glows are wider than the screen and as siblings
        // they would stretch every container that puts this behind its content.
        .overlay {
            if style == .full || style == .canvas {
                let glowScale = style == .canvas ? 0.45 : 1.0
                ZStack {
                    if colorScheme == .dark {
                        glow(
                            shellPalette.glowColor(for: .dark).opacity(0.38 * glowScale),
                            diameter: 520,
                            offset: CGSize(width: -120, height: -220)
                        )
                        glow(
                            shellPalette.tintColor(for: .dark).opacity(0.32 * glowScale),
                            diameter: 580,
                            offset: CGSize(width: 140, height: 280)
                        )
                        if style == .full {
                            glow(
                                Color(red: 0.95, green: 0.78, blue: 0.92).opacity(0.10),
                                diameter: 380,
                                offset: CGSize(width: 60, height: 40)
                            )
                        }
                    } else {
                        glow(
                            Color.white.opacity(0.55 * glowScale),
                            diameter: 420,
                            offset: CGSize(width: 90, height: -240)
                        )
                        glow(
                            shellPalette.glowColor(for: .light).opacity(0.34 * glowScale),
                            diameter: 520,
                            offset: CGSize(width: -140, height: 260)
                        )
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .clipped()
        .ignoresSafeArea()
    }

    private var gradientColors: [Color] {
        var colors = shellPalette.gradientColors(for: colorScheme)
        if colorScheme == .light, contrast == .increased {
            colors = colors.map { LightGlassPalette.darkened($0) }
        }
        return colors
    }

    /// A soft radial falloff instead of `Circle().blur(...)`. These sit underneath every
    /// frosted row, so each blur pass was being resampled by every material above it.
    private func glow(_ color: Color, diameter: CGFloat, offset: CGSize) -> some View {
        RadialGradient(
            stops: [
                .init(color: color, location: 0),
                .init(color: color.opacity(0.55), location: 0.42),
                .init(color: color.opacity(0.16), location: 0.72),
                .init(color: .clear, location: 1)
            ],
            center: .center,
            startRadius: 0,
            endRadius: diameter / 2
        )
        .frame(width: diameter, height: diameter)
        .offset(x: offset.width, y: offset.height)
    }
}

struct GlassSurface: View {
    var cornerRadius: CGFloat = GlassTokens.cardRadius
    var topRadius: CGFloat?
    var bottomRadius: CGFloat?
    var density: GlassDensity = .panel
    /// Skip Material blur — used while a sheet/panel is being dragged over a live map.
    var frozen: Bool = false
    /// List rows must not host native Liquid Glass (separate cell hosts).
    var allowsNative: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.glassEngineOverride) private var engineOverride
    @Environment(\.shellPalette) private var shellPalette

    private var engine: GlassEngine {
        GlassEngineResolver.resolve(
            scheme: colorScheme,
            reduceTransparency: reduceTransparency,
            frozen: frozen,
            override: engineOverride,
            allowsNative: allowsNative
        )
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: topRadius ?? cornerRadius,
            bottomLeadingRadius: bottomRadius ?? cornerRadius,
            bottomTrailingRadius: bottomRadius ?? cornerRadius,
            topTrailingRadius: topRadius ?? cornerRadius,
            style: .continuous
        )
    }

    var body: some View {
        ZStack {
            if colorScheme == .dark {
                darkLegacySurface
            } else {
                lightSurface
            }
        }
    }

    @ViewBuilder
    private var darkLegacySurface: some View {
        if reduceTransparency || frozen {
            shape.fill(GlassTokens.solidFallback)
            if frozen, !reduceTransparency {
                shape.fill(
                    shellPalette.tintColor(for: colorScheme).opacity(
                        density.brandTintOpacity(for: colorScheme) * 0.85
                    )
                )
                shape.fill(Color.white.opacity(density.frostOpacity(for: colorScheme) * 0.9))
            }
        } else {
            shape.fill(density.material(for: colorScheme))
            shape.fill(shellPalette.tintColor(for: colorScheme).opacity(density.brandTintOpacity(for: colorScheme)))
            shape.fill(Color.white.opacity(density.frostOpacity(for: colorScheme)))
            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(density.frostOpacity(for: colorScheme) * 1.1),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
            )
        }
    }

    @ViewBuilder
    private var lightSurface: some View {
        let frost = contrast == .increased
            ? LightGlassPalette.increasedContrastPanelFill
            : density.frostOpacity(for: .light)
        switch engine {
        case .native:
            shape.fill(Color.clear)
            shape.strokeBorder(Color.white.opacity(density.rimOpacity(for: .light)), lineWidth: 1)
        case .solid:
            shape.fill(GlassTokens.solidFallback)
            shape.fill(shellPalette.tintColor(for: .light).opacity(density.brandTintOpacity(for: .light)))
            shape.fill(Color.white.opacity(frost * 0.9))
            shape.strokeBorder(Color.white.opacity(density.rimOpacity(for: .light)), lineWidth: 1)
        case .material:
            shape.fill(density.material(for: .light))
            shape.fill(shellPalette.tintColor(for: .light).opacity(density.brandTintOpacity(for: .light)))
            shape.fill(Color.white.opacity(frost))
            shape.fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(LightGlassPalette.panelSheenOpacity),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .center
                )
            )
            shape.strokeBorder(Color.white.opacity(density.rimOpacity(for: .light)), lineWidth: 1)
        }
    }
}

struct GlassSectionRowBackground: View {
    let position: GlassRowPosition

    var body: some View {
        GlassSurface(
            topRadius: position.topRadius,
            bottomRadius: position.bottomRadius,
            density: .panel,
            allowsNative: false
        )
        .padding(.horizontal, GlassTokens.panelHorizontalInset)
    }
}

/// Solid grouped rows for keyboard-heavy forms (no per-row material blur).
struct FormSolidSectionRowBackground: View {
    let position: GlassRowPosition

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.shellPalette) private var shellPalette

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: position.topRadius,
            bottomLeadingRadius: position.bottomRadius,
            bottomTrailingRadius: position.bottomRadius,
            topTrailingRadius: position.topRadius,
            style: .continuous
        )
    }

    var body: some View {
        ZStack {
            if reduceTransparency {
                shape.fill(GlassTokens.solidFallback)
            } else {
                shape.fill(GlassTokens.formPanelFill(for: colorScheme))
                shape.fill(
                    shellPalette.tintColor(for: colorScheme).opacity(
                        colorScheme == .dark ? 0.14 : 0.10
                    )
                )
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.08 : 0.22),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            }
        }
        .padding(.horizontal, GlassTokens.panelHorizontalInset)
    }
}

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = GlassTokens.cardRadius
    var density: GlassDensity = .panel
    var contentInset: CGFloat = GlassTokens.cardContentInset
    var frozen: Bool = false
    var allowsNative: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.glassEngineOverride) private var engineOverride
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        let engine = GlassEngineResolver.resolve(
            scheme: colorScheme,
            reduceTransparency: reduceTransparency,
            frozen: frozen,
            override: engineOverride,
            allowsNative: allowsNative
        )
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let padded = content
            .padding(.horizontal, contentInset)
            .padding(.vertical, contentInset)

        if #available(iOS 26.0, *), engine == .native {
            padded
                .glassEffect(.regular.tint(LightGlassPalette.nativeTint(for: shellPalette)), in: shape)
                .overlay {
                    shape.strokeBorder(Color.white.opacity(density.rimOpacity(for: .light)), lineWidth: 1)
                }
        } else {
            padded
                .background {
                    GlassSurface(cornerRadius: cornerRadius, density: density, frozen: frozen)
                }
                .clipShape(shape)
        }
    }
}

struct GlassChromeModifier: ViewModifier {
    var cornerRadius: CGFloat = GlassTokens.chipRadius
    var frozen: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.glassEngineOverride) private var engineOverride
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        let engine = GlassEngineResolver.resolve(
            scheme: colorScheme,
            reduceTransparency: reduceTransparency,
            frozen: frozen,
            override: engineOverride,
            allowsNative: true
        )
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *), engine == .native {
            content
                .glassEffect(.regular.tint(LightGlassPalette.nativeTint(for: shellPalette)), in: shape)
                .overlay {
                    shape.strokeBorder(Color.white.opacity(GlassDensity.chrome.rimOpacity(for: .light)), lineWidth: 1)
                }
        } else {
            content
                .background {
                    GlassSurface(cornerRadius: cornerRadius, density: .chrome, frozen: frozen)
                }
                .clipShape(shape)
        }
    }
}

struct GlassFieldModifier: ViewModifier {
    var cornerRadius: CGFloat = 8

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(GlassTokens.fieldFill(for: colorScheme))
            }
    }
}

struct GlassInputFieldModifier: ViewModifier {
    var cornerRadius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .glassField(cornerRadius: cornerRadius)
    }
}

/// Backwards-compatible alias for section panels.
struct GlassListRowBackground: View {
    var cornerRadius: CGFloat = GlassTokens.cardRadius
    var verticalInset: CGFloat = 5

    var body: some View {
        GlassSectionRowBackground(position: .only)
            .padding(.vertical, verticalInset)
    }
}

/// Filter chip — selected = brand blue pill, unselected = frosted white (matches Trips filters).
struct GlassFilterChip: View {
    enum Size {
        case regular
        /// Slightly tighter padding/type for stacked trip-list filter rows.
        case compact

        var font: Font { self == .compact ? .caption2 : .caption }
        var horizontalPadding: CGFloat { self == .compact ? 10 : 12 }
        var verticalPadding: CGFloat { self == .compact ? 5 : 7 }
        var avatarSize: CGFloat { self == .compact ? 12 : 16 }
    }

    let title: String
    let isSelected: Bool
    let namespace: Namespace.ID
    var highlightID: String = "glassFilterChipHighlight"
    var expands: Bool = false
    var size: Size = .regular
    /// Optional vehicle identity mark (photo thumb or SF Symbol).
    var avatarSystemImage: String? = nil
    var avatarPhotoFileName: String? = nil
    var avatarIsElectric: Bool = false
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.glassEngineOverride) private var engineOverride
    @Environment(\.shellPalette) private var shellPalette

    private var usesNativeChip: Bool {
        GlassEngineResolver.resolve(
            scheme: colorScheme,
            reduceTransparency: reduceTransparency,
            frozen: false,
            override: engineOverride,
            allowsNative: true
        ) == .native
    }

    private var labelColor: Color {
        if colorScheme == .dark {
            return isSelected ? Color.white : Color.primary
        }
        // Light wells are pale glass — white `shellForeground` vanishes on them.
        return shellPalette.chromeColor(for: .light)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let avatarSystemImage {
                    VehicleAvatarView(
                        systemImage: avatarSystemImage,
                        photoFileName: avatarPhotoFileName,
                        size: size.avatarSize,
                        cornerRadius: size.avatarSize * 0.28,
                        isElectricAccent: avatarIsElectric,
                        symbolColor: labelColor,
                        showsSymbolPlate: false,
                        symbolFitsFrame: true
                    )
                }
                Text(title)
                    .font(size.font.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .frame(maxWidth: expands ? .infinity : nil)
            .foregroundStyle(labelColor)
            .background {
                if usesNativeChip {
                    Color.clear
                } else {
                    chipBackground
                }
            }
            .modifier(NativeFilterChipGlass(isSelected: isSelected, highlightID: highlightID, namespace: namespace))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var chipBackground: some View {
        if isSelected {
            Capsule()
                .fill(colorScheme == .dark ? shellPalette.tintColor(for: .dark) : LightGlassPalette.selectedChipFill)
                .matchedGeometryEffect(id: highlightID, in: namespace)
        } else {
            Capsule()
                .fill(
                    colorScheme == .dark
                        ? Color.white.opacity(0.12)
                        : Color.white.opacity(0.22)
                )
                .overlay {
                    if colorScheme == .light {
                        Capsule().fill(shellPalette.tintColor(for: .light).opacity(0.14))
                    }
                }
        }
    }
}

private struct NativeFilterChipGlass: ViewModifier {
    let isSelected: Bool
    let highlightID: String
    let namespace: Namespace.ID

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.glassEngineOverride) private var engineOverride
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        let engine = GlassEngineResolver.resolve(
            scheme: colorScheme,
            reduceTransparency: reduceTransparency,
            frozen: false,
            override: engineOverride,
            allowsNative: true
        )
        if #available(iOS 26.0, *), engine == .native {
            content
                .glassEffect(
                    .regular.tint(
                        isSelected
                            ? LightGlassPalette.selectedChipFill
                            : LightGlassPalette.nativeTint(for: shellPalette)
                    ).interactive(),
                    in: Capsule()
                )
                .glassEffectID(highlightID, in: namespace)
        } else {
            content
        }
    }
}

/// Navigation bar save control — pill matching Cancel, not the iOS 26 circle.
struct GlassToolbarSaveButton: View {
    let title: String

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        Text(title)
            .font(.body.weight(.semibold))
            .foregroundStyle(colorScheme == .dark ? Color.white : shellPalette.chromeColor(for: .light))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(shellPalette.tintColor(for: colorScheme).opacity(colorScheme == .dark ? 0.22 : 0.16))
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                    }
            }
    }
}

extension View {
    /// Drops the system circular toolbar glass so `GlassToolbarSaveButton` owns the pill.
    func glassToolbarSaveControl() -> some View {
        self.buttonStyle(.plain)
    }
}

/// Empty list state that matches the glass shell instead of the system white card.
struct GlassEmptyState: View {
    let title: String
    let systemImage: String
    let message: String
    var bounceTrigger: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Color.primary.opacity(0.85))
                .symbolEffect(.bounce, value: reduceMotion ? false : bounceTrigger)

            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .combine)
    }
}

/// Persistent caption above an input so glass rows read as editable fields, not static text.
struct GlassFieldLabel<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
                .glassInputField()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GlassSegmentedStyleModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content
            .pickerStyle(.segmented)
            .tint(GlassControlTint.segmented(for: colorScheme, palette: shellPalette))
            .background {
                GlassSegmentedUIKitBridge(
                    tint: TrailhoundTabBarTheme.selectedUIColor(palette: shellPalette, scheme: colorScheme),
                    selectedFill: selectedFill,
                    selectedTitle: selectedTitle,
                    normalTitle: TrailhoundTabBarTheme.unselectedUIColor(palette: shellPalette, scheme: colorScheme)
                )
            }
    }

    private var selectedFill: UIColor {
        if colorScheme == .dark {
            return TrailhoundTabBarTheme.selectedUIColor(palette: shellPalette, scheme: .dark)
        }
        return UIColor.white.withAlphaComponent(0.92)
    }

    private var selectedTitle: UIColor {
        if colorScheme == .dark {
            return .white
        }
        return TrailhoundTabBarTheme.uiColor(shellPalette.atmosphere(for: .light).chrome)
    }
}

/// Paints the system segmented control with the shell palette. SwiftUI `.tint` is ignored on iOS 26.
private struct GlassSegmentedUIKitBridge: UIViewRepresentable {
    var tint: UIColor
    var selectedFill: UIColor
    var selectedTitle: UIColor
    var normalTitle: UIColor

    func makeUIView(context: Context) -> GlassSegmentedProbeView {
        let view = GlassSegmentedProbeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: GlassSegmentedProbeView, context: Context) {
        uiView.paletteTint = tint
        uiView.selectedFill = selectedFill
        uiView.selectedTitle = selectedTitle
        uiView.normalTitle = normalTitle
        uiView.applySoon()
    }
}

final class GlassSegmentedProbeView: UIView {
    var paletteTint: UIColor = .systemBlue
    var selectedFill: UIColor = .white
    var selectedTitle: UIColor = .label
    var normalTitle: UIColor = .secondaryLabel

    func applySoon() {
        apply()
        DispatchQueue.main.async { [weak self] in
            self?.apply()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applySoon()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        apply()
    }

    func apply() {
        guard let control = findSegmentedControl() else { return }
        control.selectedSegmentTintColor = selectedFill
        control.tintColor = paletteTint
        control.setTitleTextAttributes([.foregroundColor: normalTitle], for: .normal)
        control.setTitleTextAttributes([.foregroundColor: selectedTitle], for: .selected)
    }

    private func findSegmentedControl() -> UISegmentedControl? {
        var ancestor: UIView? = superview
        for _ in 0..<8 {
            guard let current = ancestor else { return nil }
            if let found = search(current) { return found }
            ancestor = current.superview
        }
        return nil
    }

    private func search(_ root: UIView) -> UISegmentedControl? {
        if let control = root as? UISegmentedControl { return control }
        for child in root.subviews {
            if let found = search(child) { return found }
        }
        return nil
    }
}

/// Batches chip glass into one render pass on iOS 26 without changing HStack spacing.
struct GlassChipGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

extension View {
    /// Segmented pickers inside glass cards — palette selection instead of AccentColor.
    func glassSegmentedStyle() -> some View {
        modifier(GlassSegmentedStyleModifier())
    }

    func glassCard(
        cornerRadius: CGFloat = GlassTokens.cardRadius,
        density: GlassDensity = .panel,
        contentInset: CGFloat = GlassTokens.cardContentInset,
        frozen: Bool = false,
        allowsNative: Bool = true
    ) -> some View {
        modifier(
            GlassCardModifier(
                cornerRadius: cornerRadius,
                density: density,
                contentInset: contentInset,
                frozen: frozen,
                allowsNative: allowsNative
            )
        )
    }

    func glassChrome(cornerRadius: CGFloat = GlassTokens.chipRadius, frozen: Bool = false) -> some View {
        modifier(GlassChromeModifier(cornerRadius: cornerRadius, frozen: frozen))
    }

    /// Inline inputs on glass panels — frosted tint instead of system grouped black/white.
    func glassField(cornerRadius: CGFloat = 8) -> some View {
        modifier(GlassFieldModifier(cornerRadius: cornerRadius))
    }

    /// Standard frosted text field — matches trip detail place/address inputs.
    func glassInputField(cornerRadius: CGFloat = 8) -> some View {
        modifier(GlassInputFieldModifier(cornerRadius: cornerRadius))
    }

    func glassRow(position: GlassRowPosition) -> some View {
        listRowBackground(GlassSectionRowBackground(position: position))
            .listRowInsets(rowInsets(for: position))
            .listRowSeparator(.hidden)
    }

    /// Single-row glass panel (banners, one-off cards in lists).
    func glassListRow() -> some View {
        glassRow(position: .only)
    }

    func glassListChrome() -> some View {
        scrollContentBackground(.hidden)
            .background {
                AtmosphericBackground(style: .full)
                    .ignoresSafeArea()
            }
            .listSectionSpacing(GlassTokens.sectionSpacing)
            .glassNavigationChrome()
            .onGlassShell()
    }

    /// Lighter shell for text-heavy forms (gradient only, solid section rows).
    func glassFormChrome() -> some View {
        scrollContentBackground(.hidden)
            .background {
                AtmosphericBackground(style: .lightweight)
                    .ignoresSafeArea()
            }
            .listSectionSpacing(GlassTokens.sectionSpacing)
            .glassNavigationChrome()
    }

    func glassFormRow(position: GlassRowPosition) -> some View {
        listRowBackground(FormSolidSectionRowBackground(position: position))
            .listRowInsets(rowInsets(for: position))
            .listRowSeparator(.hidden)
    }

    func glassFormListRow() -> some View {
        glassFormRow(position: .only)
    }

    /// Keeps the nav bar visually merged with the atmospheric shell (no separate grey strip).
    func glassNavigationChrome() -> some View {
        toolbarBackground(.hidden, for: .navigationBar)
    }

    /// Destructive actions stay red even when the app shell uses brand-blue tint.
    func destructiveTint() -> some View {
        tint(.red)
    }

    private func rowInsets(for position: GlassRowPosition) -> EdgeInsets {
        let horizontal = GlassTokens.listContentHorizontalInset
        switch position {
        case .only:
            return EdgeInsets(top: 14, leading: horizontal, bottom: 14, trailing: horizontal)
        case .first:
            return EdgeInsets(top: 14, leading: horizontal, bottom: 10, trailing: horizontal)
        case .middle:
            return EdgeInsets(top: 10, leading: horizontal, bottom: 10, trailing: horizontal)
        case .last:
            return EdgeInsets(top: 10, leading: horizontal, bottom: 14, trailing: horizontal)
        }
    }
}
