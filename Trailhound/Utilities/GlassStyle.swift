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

    static func fieldFill(for scheme: ColorScheme, palette: ShellPalette = .sky) -> Color {
        if scheme == .dark {
            return Color.white.opacity(0.10)
        }
        return palette.glassReadabilityTint(for: .light).opacity(LightGlassPalette.fieldFillOpacity)
    }

    /// Frosted panel look without `Material` (keyboard-friendly forms).
    static func formPanelFill(for scheme: ColorScheme, palette: ShellPalette = .sky) -> Color {
        if scheme == .dark {
            return Color.white.opacity(0.12)
        }
        return palette.glassReadabilityTint(for: .light).opacity(LightGlassPalette.formPanelFillOpacity)
    }

    static func solidFallback(for scheme: ColorScheme, palette: ShellPalette) -> Color {
        if scheme == .dark {
            return Color(.secondarySystemGroupedBackground)
        }
        return palette.opaquePanelFill(for: .light)
    }

    /// Frozen nav chrome over a map: Light is a near-white palette frost, Dark
    /// keeps the grouped solid. Never `Material` — MapKit must not be sampled.
    static func toolbarFrozenFill(for scheme: ColorScheme, palette: ShellPalette) -> Color {
        if scheme == .dark {
            return solidFallback(for: .dark, palette: palette)
        }
        return GlassContrast.toolbarLightFill(palette: palette).color
    }

    static func toolbarFrozenRim(for scheme: ColorScheme, palette: ShellPalette) -> Color {
        if scheme == .dark {
            return Color.white.opacity(0.28)
        }
        return Color.white.opacity(0.72)
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

    func brandTintOpacity(for scheme: ColorScheme, palette: ShellPalette = .sky, increasedContrast: Bool = false) -> Double {
        switch self {
        case .panel:
            scheme == .dark
                ? 0.20
                : GlassContrast.materialTintOpacity(palette: palette, increasedContrast: increasedContrast)
        case .chrome:
            scheme == .dark
                ? 0.14
                : GlassContrast.chromeTintOpacity(palette: palette, increasedContrast: increasedContrast)
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
                            Color.white.opacity(GlassContrast.atmosphereWhiteGlowOpacity * glowScale),
                            diameter: 460,
                            offset: CGSize(width: 88, height: -250)
                        )
                        glow(
                            shellPalette.atmosphere(for: .light).top.color.opacity(0.50 * glowScale),
                            diameter: 520,
                            offset: CGSize(width: 70, height: -200)
                        )
                        glow(
                            shellPalette.atmosphere(for: .light).bottom.color.opacity(0.30 * glowScale),
                            diameter: 560,
                            offset: CGSize(width: -130, height: 300)
                        )
                    }
                }
                .allowsHitTesting(false)
            }
        }
        // Cheap frost: a white veil, not `.blur`. Live blur under glass cards gets
        // resampled by every Material above it (see docs/PERFORMANCE.md).
        .overlay {
            if colorScheme != .dark {
                Color.white.opacity(
                    style == .full
                        ? LightGlassPalette.atmosphereVeilOpacity
                        : LightGlassPalette.atmosphereVeilOpacity * 0.6
                )
                    .allowsHitTesting(false)
            }
        }
        .clipped()
        .ignoresSafeArea()
    }

    private var gradientColors: [Color] {
        shellPalette.gradientColors(for: colorScheme)
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
    @Environment(\.shellPalette) private var shellPalette

    private var engine: GlassEngine {
        GlassEngineResolver.resolve(
            scheme: colorScheme,
            reduceTransparency: reduceTransparency,
            frozen: frozen,
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
            shape.fill(GlassTokens.solidFallback(for: colorScheme, palette: shellPalette))
            if frozen, !reduceTransparency {
                shape.fill(
                    shellPalette.tintColor(for: colorScheme).opacity(
                        density.brandTintOpacity(for: colorScheme, palette: shellPalette) * 0.85
                    )
                )
                shape.fill(Color.white.opacity(density.frostOpacity(for: colorScheme) * 0.9))
            }
        } else {
            shape.fill(density.material(for: colorScheme))
            shape.fill(
                shellPalette.tintColor(for: colorScheme).opacity(
                    density.brandTintOpacity(for: colorScheme, palette: shellPalette)
                )
            )
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
        let increased = contrast == .increased
        let frost = density.frostOpacity(for: .light)
        let tintOpacity = density.brandTintOpacity(
            for: .light,
            palette: shellPalette,
            increasedContrast: increased
        )
        let rim = density.rimOpacity(for: .light) + (increased ? 0.10 : 0)
        switch engine {
        case .native:
            shape.fill(Color.clear)
            shape.strokeBorder(Color.white.opacity(rim), lineWidth: 1)
        case .solid:
            shape.fill(GlassTokens.solidFallback(for: .light, palette: shellPalette))
            shape.strokeBorder(Color.white.opacity(rim), lineWidth: 1)
        case .material:
            shape.fill(density.material(for: .light))
            shape.fill(shellPalette.glassReadabilityTint(for: .light).opacity(tintOpacity))
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
            shape.strokeBorder(Color.white.opacity(rim), lineWidth: 1)
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
            shape.fill(GlassTokens.solidFallback(for: colorScheme, palette: shellPalette))
            if !reduceTransparency, colorScheme == .dark {
                shape.fill(shellPalette.tintColor(for: .dark).opacity(0.10))
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
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
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        let engine = GlassEngineResolver.resolve(
            scheme: colorScheme,
            reduceTransparency: reduceTransparency,
            frozen: frozen,
            allowsNative: allowsNative
        )
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let padded = content
            .padding(.horizontal, contentInset)
            .padding(.vertical, contentInset)

        if #available(iOS 26.0, *), engine == .native {
            padded
                .glassEffect(
                    .regular.tint(
                        LightGlassPalette.nativeTint(
                            for: shellPalette,
                            increasedContrast: contrast == .increased
                        )
                    ),
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(
                        Color.white.opacity(density.rimOpacity(for: .light) + (contrast == .increased ? 0.10 : 0)),
                        lineWidth: 1
                    )
                }
        } else {
            padded
                .background {
                    GlassSurface(
                        cornerRadius: cornerRadius,
                        density: density,
                        frozen: frozen,
                        allowsNative: allowsNative
                    )
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
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        let engine = GlassEngineResolver.resolve(
            scheme: colorScheme,
            reduceTransparency: reduceTransparency,
            frozen: frozen,
            allowsNative: true
        )
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *), engine == .native {
            content
                .glassEffect(
                    .regular.tint(
                        LightGlassPalette.nativeTint(
                            for: shellPalette,
                            increasedContrast: contrast == .increased
                        )
                    ),
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(
                        Color.white.opacity(
                            GlassDensity.chrome.rimOpacity(for: .light) + (contrast == .increased ? 0.10 : 0)
                        ),
                        lineWidth: 1
                    )
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
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(GlassTokens.fieldFill(for: colorScheme, palette: shellPalette))
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

/// Filter chip — Light selected = palette chrome + white type; unselected = frost + white.
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
    @Environment(\.shellPalette) private var shellPalette

    private var usesNativeChip: Bool {
        GlassEngineResolver.resolve(
            scheme: colorScheme,
            reduceTransparency: reduceTransparency,
            frozen: false,
            allowsNative: true
        ) == .native
    }

    private var labelColor: Color {
        if colorScheme == .dark {
            return isSelected ? Color.white : Color.primary
        }
        return Color.white
    }

    private var selectionFill: Color {
        colorScheme == .dark
            ? shellPalette.tintColor(for: .dark)
            : LightGlassPalette.selectedChipFill(for: shellPalette)
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
                .fill(selectionFill)
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
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        let engine = GlassEngineResolver.resolve(
            scheme: colorScheme,
            reduceTransparency: reduceTransparency,
            frozen: false,
            allowsNative: true
        )
        if #available(iOS 26.0, *), engine == .native {
            content
                .glassEffect(
                    .regular.tint(
                        isSelected
                            ? selectedTint
                            : LightGlassPalette.nativeTint(
                                for: shellPalette,
                                increasedContrast: contrast == .increased
                            )
                    ).interactive(),
                    in: Capsule()
                )
                .glassEffectID(highlightID, in: namespace)
        } else {
            content
        }
    }

    private var selectedTint: Color {
        colorScheme == .dark
            ? shellPalette.tintColor(for: .dark)
            : LightGlassPalette.selectedChipFill(for: shellPalette)
    }
}

/// Shared material/tint/rim treatment for custom toolbar and overlay controls.
/// Never uses native `glassEffect` — live maps and camera previews must not
/// resample Liquid Glass every frame (`allowsNative` stays off).
struct GlassToolbarControlBackground<ControlShape: InsettableShape>: View {
    let shape: ControlShape
    var frozen: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        let useSolid = reduceTransparency || frozen
        ZStack {
            if useSolid {
                shape.fill(GlassTokens.solidFallback(for: colorScheme, palette: shellPalette))
            } else {
                shape.fill(.ultraThinMaterial)
                if colorScheme == .dark {
                    shape.fill(shellPalette.tintColor(for: .dark).opacity(0.22))
                } else {
                    shape.fill(
                        shellPalette.glassReadabilityTint(for: .light).opacity(
                            GlassContrast.chromeTintOpacity(palette: shellPalette, increasedContrast: false)
                        )
                    )
                }
            }
            shape.strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
        }
    }
}

/// Frozen map-toolbar plate. Light stays a pale frost so palette glyphs read;
/// overlay chrome (`GlassToolbarControlBackground`) is unchanged.
struct GlassToolbarFrozenPlate<ControlShape: InsettableShape>: View {
    let shape: ControlShape

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        ZStack {
            shape.fill(GlassTokens.toolbarFrozenFill(for: colorScheme, palette: shellPalette))
            shape.strokeBorder(
                GlassTokens.toolbarFrozenRim(for: colorScheme, palette: shellPalette),
                lineWidth: 1
            )
        }
    }
}

/// Localized Save / Cancel label. Defaults to the system toolbar platter.
struct GlassToolbarSaveButton: View {
    let title: String
    var sampling: GlassToolbarSampling = .system

    var body: some View {
        GlassToolbarTitle(title: title, sampling: sampling)
    }
}

/// Back chevron. Defaults to the system toolbar platter.
struct GlassToolbarBackButton: View {
    var sampling: GlassToolbarSampling = .system

    var body: some View {
        GlassToolbarSymbol(systemName: "chevron.backward", sampling: sampling)
    }
}

/// Empty list state that matches the glass shell instead of the system white card.
struct GlassEmptyState: View {
    let title: String
    let systemImage: String
    let message: String
    var bounceTrigger: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(GlassText.primary(for: colorScheme).opacity(0.85))
                .symbolEffect(.bounce, value: reduceMotion ? false : bounceTrigger)

            Text(title)
                .font(.headline)
                .foregroundStyle(GlassText.primary(for: colorScheme))
                .multilineTextAlignment(.center)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(GlassText.secondary(for: colorScheme))
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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(GlassText.secondary(for: colorScheme))
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
                    normalTitle: unselectedTitle
                )
            }
    }

    private var selectedFill: UIColor {
        if colorScheme == .dark {
            return TrailhoundTabBarTheme.selectedUIColor(palette: shellPalette, scheme: .dark)
        }
        return TrailhoundTabBarTheme.uiColor(GlassContrast.selectedChipFill(palette: shellPalette))
    }

    private var selectedTitle: UIColor {
        .white
    }

    /// Glass segmented labels stay white; tab-bar unselected ink is a separate system capsule.
    private var unselectedTitle: UIColor {
        if colorScheme == .dark {
            return UIColor.secondaryLabel
        }
        return UIColor.white.withAlphaComponent(CGFloat(GlassContrast.textSecondaryOpacity))
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
    var content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
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
            .onGlassShell()
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
