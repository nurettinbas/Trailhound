import SwiftUI

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
        scheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.48)
    }

    /// Frosted panel look without `Material` (keyboard-friendly forms).
    static func formPanelFill(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.white.opacity(0.55)
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
            scheme == .dark ? 0.06 : 0.18
        case .chrome:
            scheme == .dark ? 0.04 : 0.10
        }
    }

    func brandTintOpacity(for scheme: ColorScheme) -> Double {
        switch self {
        case .panel:
            scheme == .dark ? 0.20 : 0.14
        case .chrome:
            scheme == .dark ? 0.14 : 0.08
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

    var body: some View {
        Group {
            if style == .canvas {
                Color(.systemBackground)
            } else {
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [
                            Color(red: 0.03, green: 0.07, blue: 0.14),
                            Color(red: 0.07, green: 0.13, blue: 0.24),
                            Color(red: 0.04, green: 0.10, blue: 0.20)
                        ]
                        : [
                            Color(red: 0.70, green: 0.88, blue: 0.99),
                            Color(red: 0.82, green: 0.93, blue: 1.00),
                            Color(red: 0.76, green: 0.90, blue: 0.99)
                        ],
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
                    glow(
                        TrailhoundBrandColors.brandTop.opacity((colorScheme == .dark ? 0.38 : 0.42) * glowScale),
                        diameter: 520,
                        offset: CGSize(width: -120, height: -220)
                    )

                    glow(
                        TrailhoundBrandColors.brandBottom.opacity((colorScheme == .dark ? 0.32 : 0.36) * glowScale),
                        diameter: 580,
                        offset: CGSize(width: 140, height: 280)
                    )

                    if style == .full {
                        glow(
                            Color(red: 0.95, green: 0.78, blue: 0.92).opacity(colorScheme == .dark ? 0.10 : 0.18),
                            diameter: 380,
                            offset: CGSize(width: 60, height: 40)
                        )
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .clipped()
        .ignoresSafeArea()
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

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
            if reduceTransparency {
                shape.fill(GlassTokens.solidFallback)
            } else {
                shape.fill(density.material(for: colorScheme))
                shape.fill(TrailhoundBrandColors.brandBottom.opacity(density.brandTintOpacity(for: colorScheme)))
                shape.fill(Color.white.opacity(density.frostOpacity(for: colorScheme)))
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(density.frostOpacity(for: colorScheme) * (colorScheme == .dark ? 1.1 : 0.65)),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            }
        }
    }
}

struct GlassSectionRowBackground: View {
    let position: GlassRowPosition

    var body: some View {
        GlassSurface(
            topRadius: position.topRadius,
            bottomRadius: position.bottomRadius,
            density: .panel
        )
        .padding(.horizontal, GlassTokens.panelHorizontalInset)
    }
}

/// Solid grouped rows for keyboard-heavy forms (no per-row material blur).
struct FormSolidSectionRowBackground: View {
    let position: GlassRowPosition

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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
                    TrailhoundBrandColors.brandBottom.opacity(
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

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, contentInset)
            .padding(.vertical, contentInset)
            .background {
                GlassSurface(cornerRadius: cornerRadius, density: density)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct GlassChromeModifier: ViewModifier {
    var cornerRadius: CGFloat = GlassTokens.chipRadius

    func body(content: Content) -> some View {
        content
            .background {
                GlassSurface(cornerRadius: cornerRadius, density: .chrome)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
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

    private var labelColor: Color {
        isSelected ? Color.white : Color.primary
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
                if isSelected {
                    Capsule()
                        .fill(TrailhoundBrandColors.brandBottom)
                        .matchedGeometryEffect(id: highlightID, in: namespace)
                } else {
                    Capsule()
                        .fill(
                            colorScheme == .dark
                                ? Color.white.opacity(0.12)
                                : Color.white.opacity(0.55)
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Navigation bar save control — icon + title only; toolbar supplies the glass pill.
struct GlassToolbarSaveButton: View {
    let title: String
    var systemImage: String = "square.and.arrow.down"

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
        }
        .foregroundStyle(TrailhoundBrandColors.brandBottom)
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
                .foregroundStyle(TrailhoundBrandColors.brandBottom.opacity(0.85))
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

extension View {
    /// Segmented pickers inside glass cards — blue selection instead of system white.
    func glassSegmentedStyle() -> some View {
        pickerStyle(.segmented)
            .tint(TrailhoundBrandColors.brandBottom)
    }

    func glassCard(
        cornerRadius: CGFloat = GlassTokens.cardRadius,
        density: GlassDensity = .panel,
        contentInset: CGFloat = GlassTokens.cardContentInset
    ) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, density: density, contentInset: contentInset))
    }

    func glassChrome(cornerRadius: CGFloat = GlassTokens.chipRadius) -> some View {
        modifier(GlassChromeModifier(cornerRadius: cornerRadius))
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
