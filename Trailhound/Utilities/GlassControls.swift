import SwiftUI

private struct GlassControlSchemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        if colorScheme == .dark || shellPalette.usesLightChrome(for: colorScheme) {
            content
        } else {
            content.environment(\.colorScheme, .dark)
        }
    }
}

private struct GlassToggleTintModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content
            .tint(GlassControlTint.toggle(for: colorScheme, palette: shellPalette))
            // Keep the system switch on the real Light/Dark chrome. A dark-scheme
            // switch on a light grouped row is a white pill with no track.
            .environment(\.colorScheme, colorScheme)
    }
}

struct GlassSectionHeader: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(GlassText.secondary(for: colorScheme))
            .textCase(.uppercase)
    }
}

struct GlassSectionFooter: View {
    let title: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(title)
            .font(.footnote)
            .foregroundStyle(GlassText.secondary(for: colorScheme))
    }
}

/// Theme-colored row disclosure. Light uses palette chrome so `>` reads on open glass.
struct GlassDisclosureChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .glassDisclosureInk()
            .accessibilityHidden(true)
    }
}

/// How a nav-bar control draws its chrome.
///
/// - `system`: iOS 26 shared toolbar platter (Material bar item on iOS 18). Use on
///   form/list screens where the bar sits on atmosphere, not a live map.
/// - `frozen`: 36pt solid circle. Use when the bar sits on MapKit so glass does
///   not resample the map every frame.
enum GlassToolbarSampling {
    case system
    case frozen
}

/// Palette-tinted SF Symbol for the navigation bar.
struct GlassToolbarSymbol: View {
    let systemName: String
    var isLoading: Bool = false
    var sampling: GlassToolbarSampling = .system

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        glyph
            .modifier(GlassToolbarFrozenCircle(enabled: sampling == .frozen))
    }

    @ViewBuilder
    private var glyph: some View {
        let tint = shellPalette.tintColor(for: colorScheme)
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .tint(tint)
        } else {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(tint)
                .tint(tint)
        }
    }
}

/// Palette-tinted nav-bar title (Save / Cancel / Done). System path has no
/// custom capsule — the toolbar platter is the chrome.
struct GlassToolbarTitle: View {
    let title: String
    var sampling: GlassToolbarSampling = .system

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        let tint = shellPalette.tintColor(for: colorScheme)
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .tint(tint)
            .modifier(GlassToolbarFrozenCapsule(enabled: sampling == .frozen))
    }
}

/// Adjacent trailing/leading actions share one toolbar platter (Trips merge+bell).
/// Do not copy Trips’ Start-alignment padding onto other screens.
struct GlassToolbarCluster<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 16) {
            content
        }
    }
}

/// Frozen map-chrome circle. Form screens should use `GlassToolbarSymbol` with
/// `.system` instead of this type.
struct GlassNavCircleIcon: View {
    let systemName: String
    var isLoading: Bool = false

    var body: some View {
        GlassToolbarSymbol(systemName: systemName, isLoading: isLoading, sampling: .frozen)
    }
}

private struct GlassToolbarFrozenCircle: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .frame(width: 36, height: 36, alignment: .center)
                .background {
                    GlassToolbarFrozenPlate(shape: Circle())
                }
        } else {
            content
        }
    }
}

private struct GlassToolbarFrozenCapsule: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background {
                    GlassToolbarFrozenPlate(shape: Capsule(style: .continuous))
                }
        } else {
            content
        }
    }
}

extension View {
    /// Forces leaf system controls (DatePicker / menu Picker / TextField) to draw light labels
    /// on the colored shell without flipping Material sampling for ancestors.
    func glassControlScheme() -> some View {
        modifier(GlassControlSchemeModifier())
    }

    func glassToggleStyle() -> some View {
        modifier(GlassToggleTintModifier())
    }

    func glassTextField() -> some View {
        glassInputField()
            .glassControlScheme()
    }

    func glassStepper() -> some View {
        glassControlScheme()
            .modifier(GlassStepperTintModifier())
    }
}

extension ToolbarContent {
    /// Drops the iOS 26 system toolbar platter. Use when the item draws its own
    /// chrome (frozen map circles) or is a semantic opaque pill (`LocationPermissionBadge`).
    @ToolbarContentBuilder
    func hideSharedToolbarBackgroundIfAvailable() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

private struct GlassStepperTintModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    func body(content: Content) -> some View {
        content.tint(shellPalette.shellTint(for: colorScheme))
    }
}
