import SwiftUI
import UIKit

/// Selected-tab icon, label, and iOS 26 pill colors from `ShellPalette`.
enum TrailhoundTabBarTheme {
    static func selectedUIColor(palette: ShellPalette, scheme: ColorScheme) -> UIColor {
        // Light atmosphere.tint is dark olive on lime glass (reads as black).
        // Dark tab items already use the vivid palette tint — Light matches that.
        let hue = scheme == .light
            ? palette.atmosphere(for: .dark).tint
            : palette.atmosphere(for: scheme).tint
        return uiColor(hue)
    }

    static func unselectedUIColor(palette _: ShellPalette, scheme _: ColorScheme) -> UIColor {
        .white
    }

    /// Tab bar selected icon + title. Light is black on the frost pill; Dark keeps the vivid tint.
    static func selectedGlyphUIColor(palette: ShellPalette, scheme: ColorScheme) -> UIColor {
        scheme == .dark ? selectedUIColor(palette: palette, scheme: .dark) : .black
    }

    static func uiColor(_ rgb: ShellRGB, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
    }

    static func pagePlateUIColor(palette: ShellPalette, scheme: ColorScheme) -> UIColor {
        uiColor(palette.atmosphere(for: scheme).mid)
    }

    /// Mid-family wash on the Light capsule. Dark keeps the system glass.
    static func lightGlassTintUIColor(palette: ShellPalette) -> UIColor {
        uiColor(
            GlassContrast.glassTint(palette: palette),
            alpha: CGFloat(GlassContrast.tabBarGlassTintOpacity)
        )
    }

    /// Same family as card `nativeTint`, lower opacity so the bar is more open.
    static func clearGlassTintUIColor(palette: ShellPalette) -> UIColor {
        uiColor(
            GlassContrast.nativeGlassTint(palette: palette),
            alpha: CGFloat(GlassContrast.tabBarClearGlassTintOpacity)
        )
    }
}

/// SwiftUI floating tab bar. Colors stay in SwiftUI so Light liquid glass
/// cannot remap white glyphs to black, and layout cannot chameleon-stamp UIKit.
struct TrailhoundFloatingTabBar: View {
    @Binding var selection: AppTab
    var isRecording: Bool = false
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.colorScheme) private var colorScheme

    private var selectedColor: Color {
        Color(uiColor: TrailhoundTabBarTheme.selectedGlyphUIColor(palette: shellPalette, scheme: colorScheme))
    }

    var body: some View {
        HStack(spacing: 0) {
            tab(.trips, title: L10n.tabTrips, systemImage: "map", identifier: "tab.trips", badge: isRecording)
            tab(
                .pairing,
                title: L10n.string("vehicles.tab.title"),
                systemImage: "car",
                identifier: "tab.pairing"
            )
            tab(.stats, title: L10n.tabStats, systemImage: "chart.bar", identifier: "tab.stats")
            tab(.settings, title: L10n.tabSettings, systemImage: "gearshape", identifier: "tab.settings")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .glassTabBar()
        .padding(.horizontal, GlassTokens.panelHorizontalInset)
        .padding(.bottom, 6)
        .accessibilityElement(children: .contain)
    }

    private func tab(
        _ id: AppTab,
        title: String,
        systemImage: String,
        identifier: String,
        badge: Bool = false
    ) -> some View {
        let selected = selection == id
        return Button {
            selection = id
        } label: {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: selected ? "\(systemImage).fill" : systemImage)
                        .font(.system(size: 22, weight: .medium))
                        .environment(\.symbolVariants, .none)
                        .symbolRenderingMode(.monochrome)
                    if badge {
                        Circle()
                            .fill(GlassSemantic.notificationBadge)
                            .frame(width: 8, height: 8)
                            .offset(x: 5, y: -3)
                            .accessibilityHidden(true)
                    }
                }
                Text(title)
                    .font(.system(size: 10, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? selectedColor : Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if selected {
                    Capsule()
                        .fill(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.22))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Hides the system `UITabBar` so iOS 26 cannot draw a second liquid platter.
@MainActor
enum TrailhoundTabBarCompact {
    static func hideSystemBar(_ tabBar: UITabBar) {
        tabBar.isHidden = true
        tabBar.alpha = 0
    }
}

struct TrailhoundTabBarCompactInstaller: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> TrailhoundTabBarCompactController {
        TrailhoundTabBarCompactController()
    }

    func updateUIViewController(_ uiViewController: TrailhoundTabBarCompactController, context: Context) {
        uiViewController.hide()
    }
}

final class TrailhoundTabBarCompactController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hide()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        hide()
    }

    func hide() {
        guard let tabBar = resolveTabBar() else { return }
        TrailhoundTabBarCompact.hideSystemBar(tabBar)
    }

    private func resolveTabBar() -> UITabBar? {
        if let tabBar = tabBarController?.tabBar { return tabBar }
        guard let root = view.window?.rootViewController else { return nil }
        return findTabBarController(from: root)?.tabBar
    }

    private func findTabBarController(from controller: UIViewController) -> UITabBarController? {
        if let tab = controller as? UITabBarController { return tab }
        if let tab = controller.tabBarController { return tab }
        for child in controller.children {
            if let found = findTabBarController(from: child) { return found }
        }
        if let presented = controller.presentedViewController {
            return findTabBarController(from: presented)
        }
        return nil
    }
}
