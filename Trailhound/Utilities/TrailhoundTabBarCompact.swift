import SwiftUI
import UIKit

/// Selected-tab icon, label, and iOS 26 pill colors from `ShellPalette`.
enum TrailhoundTabBarTheme {
    static func selectedUIColor(palette: ShellPalette, scheme: ColorScheme) -> UIColor {
        uiColor(palette.atmosphere(for: scheme).tint)
    }

    static func unselectedUIColor(palette _: ShellPalette, scheme: ColorScheme) -> UIColor {
        if scheme == .dark {
            return UIColor.secondaryLabel
        }
        // Light floating tab bar is a white glass capsule — white 0.78 disappears.
        return UIColor.label.withAlphaComponent(0.55)
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
}

/// Applies palette tint. Width stays with the system floating bar — shrinking
/// `UITabBar.frame` on iOS 26 fights UIKit and leaves a squeezed mid-layout.
@MainActor
enum TrailhoundTabBarCompact {
    static func apply(to tabBar: UITabBar, palette: ShellPalette, scheme: ColorScheme) {
        applySelectionTint(to: tabBar, palette: palette, scheme: scheme)
        tabBar.backgroundColor = .clear
        tabBar.isTranslucent = true
        restoreSystemWidthIfNeeded(tabBar)
        applyLightGlassTint(to: tabBar, palette: palette, scheme: scheme)
    }

    /// Undo a leftover narrow frame from the old compact hack. Skip once the bar is full width.
    static func restoreSystemWidthIfNeeded(_ tabBar: UITabBar) {
        guard let superview = tabBar.superview else { return }
        let fullWidth = superview.bounds.width
        guard fullWidth > 0, tabBar.bounds.width > 0, tabBar.bounds.width < fullWidth * 0.92 else { return }

        tabBar.itemPositioning = .automatic
        tabBar.itemSpacing = 0
        tabBar.itemWidth = 0

        var frame = tabBar.frame
        frame.origin.x = superview.bounds.minX
        frame.size.width = fullWidth
        tabBar.frame = frame
    }

    static func applySelectionTint(to tabBar: UITabBar, palette: ShellPalette, scheme: ColorScheme) {
        let selected = TrailhoundTabBarTheme.selectedUIColor(palette: palette, scheme: scheme)
        let unselected = TrailhoundTabBarTheme.unselectedUIColor(palette: palette, scheme: scheme)
        if tabBar.tintColor != selected {
            tabBar.tintColor = selected
        }
        if tabBar.unselectedItemTintColor != unselected {
            tabBar.unselectedItemTintColor = unselected
        }

        // iOS 26 Liquid Glass already tints the selected pill from `tintColor`.
        // Mutating UITabBarAppearance can flatten that glass.
        if #available(iOS 26.0, *) { return }

        let appearance = tabBar.standardAppearance.copy()
        applyItemColors(to: appearance, selected: selected, unselected: unselected)
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }

    private static func applyItemColors(
        to appearance: UITabBarAppearance,
        selected: UIColor,
        unselected: UIColor
    ) {
        let layouts = [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance
        ]
        for layout in layouts {
            layout.normal.iconColor = unselected
            layout.normal.titleTextAttributes = [.foregroundColor: unselected]
            layout.selected.iconColor = selected
            layout.selected.titleTextAttributes = [.foregroundColor: selected]
        }
        appearance.selectionIndicatorTintColor = selected
    }

    /// Tints the floating capsule's `UIGlassEffect` without replacing `UITabBarAppearance`
    /// (copying appearance flattens iOS 26 liquid glass).
    static func applyLightGlassTint(to tabBar: UITabBar, palette: ShellPalette, scheme: ColorScheme) {
        guard !UITestSupport.isEnabled else { return }
        guard scheme == .light else { return }
        guard #available(iOS 26.0, *) else { return }
        let tint = TrailhoundTabBarTheme.lightGlassTintUIColor(palette: palette)
        applyLightGlassTint(in: tabBar, matching: tabBar, tint: tint)
        guard let superview = tabBar.superview else { return }
        let barFrame = tabBar.frame
        for sibling in superview.subviews where sibling !== tabBar {
            // Platter sits in the bottom chrome band. Skip the full-screen content sibling.
            let isChromeBand = sibling.frame.maxY >= barFrame.minY - 40
                && sibling.frame.height <= barFrame.height + 120
            guard isChromeBand else { continue }
            applyLightGlassTint(in: sibling, matching: tabBar, tint: tint)
        }
    }

    @available(iOS 26.0, *)
    private static func applyLightGlassTint(in view: UIView, matching tabBar: UITabBar, tint: UIColor) {
        if let effectView = view as? UIVisualEffectView,
           let glass = effectView.effect as? UIGlassEffect,
           isFloatingCapsule(effectView, matching: tabBar) {
            if glass.tintColor != tint {
                glass.tintColor = tint
                effectView.effect = glass
            }
        }
        for subview in view.subviews {
            applyLightGlassTint(in: subview, matching: tabBar, tint: tint)
        }
    }

    /// The selected-tab pill is a small inner glass. Only the wide, short capsule gets the wash.
    private static func isFloatingCapsule(_ effectView: UIView, matching tabBar: UITabBar) -> Bool {
        let width = effectView.bounds.width
        let height = effectView.bounds.height
        let barWidth = tabBar.bounds.width
        guard width > 8, barWidth > 8 else { return false }
        return width > barWidth * 0.45 && height >= 44 && height <= 96
    }
}

/// Hosts a zero-size controller that walks the window and compacts `UITabBar`.
struct TrailhoundTabBarCompactInstaller: UIViewControllerRepresentable {
    var selectedTab: AppTab
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.colorScheme) private var colorScheme

    func makeUIViewController(context: Context) -> TrailhoundTabBarCompactController {
        let controller = TrailhoundTabBarCompactController()
        controller.palette = shellPalette
        controller.colorScheme = colorScheme
        return controller
    }

    func updateUIViewController(_ uiViewController: TrailhoundTabBarCompactController, context: Context) {
        uiViewController.palette = shellPalette
        uiViewController.colorScheme = colorScheme
        uiViewController.apply()
    }
}

final class TrailhoundTabBarCompactController: UIViewController {
    var palette: ShellPalette = .sky
    var colorScheme: ColorScheme = .light

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        apply()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Width only. Re-applying glass tint here mutates `UIVisualEffectView` and
        // can retrigger layout until XCTest's launch assertion times out.
        restoreBarWidthOnly()
    }

    private func restoreBarWidthOnly() {
        guard let tabBar = resolveTabBar() else { return }
        TrailhoundTabBarCompact.restoreSystemWidthIfNeeded(tabBar)
    }

    func apply() {
        guard let tabBar = resolveTabBar() else { return }
        TrailhoundTabBarCompact.apply(to: tabBar, palette: palette, scheme: colorScheme)
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
