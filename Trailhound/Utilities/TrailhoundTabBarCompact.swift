import SwiftUI
import UIKit

/// Selected-tab icon, label, and iOS 26 pill colors from `ShellPalette`.
/// Light uses the unmodified system bar — these tokens are for Dark only.
enum TrailhoundTabBarTheme {
    static func selectedUIColor(palette: ShellPalette, scheme: ColorScheme) -> UIColor {
        let hue = scheme == .light
            ? palette.atmosphere(for: .dark).tint
            : palette.atmosphere(for: scheme).tint
        return uiColor(hue)
    }

    static func unselectedUIColor(palette _: ShellPalette, scheme _: ColorScheme) -> UIColor {
        .white
    }

    /// Dark selected uses the palette tint. Light selected is white.
    static func selectedGlyphUIColor(palette: ShellPalette, scheme: ColorScheme) -> UIColor {
        scheme == .light ? .white : selectedUIColor(palette: palette, scheme: .dark)
    }

    static func uiColor(_ rgb: ShellRGB, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: rgb.r, green: rgb.g, blue: rgb.b, alpha: alpha)
    }

    static func pagePlateUIColor(palette: ShellPalette, scheme: ColorScheme) -> UIColor {
        uiColor(palette.atmosphere(for: scheme).mid)
    }

    static func clearGlassTintUIColor(palette: ShellPalette) -> UIColor {
        uiColor(
            GlassContrast.nativeGlassTint(palette: palette),
            alpha: CGFloat(GlassContrast.tabBarClearGlassTintOpacity)
        )
    }
}

/// System iOS 26 `UITabBar`. Light selected is white. Dark sets palette `tintColor`.
/// Do not copy `UITabBarAppearance` on iOS 26.
@MainActor
enum TrailhoundTabBarCompact {
    static func apply(to tabBar: UITabBar, palette: ShellPalette, scheme: ColorScheme) {
        tabBar.isHidden = false
        tabBar.alpha = 1
        restoreSystemWidthIfNeeded(tabBar)
        if scheme == .light {
            restoreSystemDefault(tabBar)
            applyLightSelectedWhite(to: tabBar)
            return
        }
        applyDarkSelectionTint(to: tabBar, palette: palette)
    }

    /// Drop leftover Light/Dark pins, custom images, and glass tint from earlier experiments.
    static func restoreSystemDefault(_ tabBar: UITabBar) {
        clearInterfaceStylePin(tabBar)
        if tabBar.tintColor != nil {
            tabBar.tintColor = nil
        }
        if tabBar.unselectedItemTintColor != nil {
            tabBar.unselectedItemTintColor = nil
        }
        restoreTemplateGlyphs(on: tabBar)
        clearGlassTint(on: tabBar)
    }

    private static func clearInterfaceStylePin(_ tabBar: UITabBar) {
        if tabBar.overrideUserInterfaceStyle != .unspecified {
            tabBar.overrideUserInterfaceStyle = .unspecified
        }
        guard let superview = tabBar.superview else { return }
        let barFrame = tabBar.frame
        for sibling in superview.subviews where sibling !== tabBar {
            let isChromeBand = sibling.frame.maxY >= barFrame.minY - 40
                && sibling.frame.height <= barFrame.height + 120
            guard isChromeBand else { continue }
            if sibling.overrideUserInterfaceStyle != .unspecified {
                sibling.overrideUserInterfaceStyle = .unspecified
            }
        }
    }

    /// Selected icon + title are white. Unselected stays system default.
    static func applyLightSelectedWhite(to tabBar: UITabBar) {
        if tabBar.tintColor != .white {
            tabBar.tintColor = .white
        }
        let symbols = ["map", "car", "chart.bar", "gearshape"]
        if let items = tabBar.items, items.count == symbols.count {
            let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
            for (item, name) in zip(items, symbols) {
                item.selectedImage = UIImage(systemName: "\(name).fill", withConfiguration: config)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal)
                item.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
            }
        }
        paintLightSelectedTitle(in: tabBar)
    }

    /// iOS 26 title vibrancy remaps the selected label to accent blue. Lift
    /// vibrancy on the title only — never `UIGlassEffect`.
    static func paintLightSelectedTitle(in tabBar: UITabBar) {
        let selectedTitle = tabBar.selectedItem?.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        paintLightSelectedTitleChrome(in: tabBar, selectedTitle: selectedTitle)
        guard let superview = tabBar.superview else { return }
        let barFrame = tabBar.frame
        for sibling in superview.subviews where sibling !== tabBar {
            let isChromeBand = sibling.frame.maxY >= barFrame.minY - 40
                && sibling.frame.height <= barFrame.height + 120
            guard isChromeBand else { continue }
            paintLightSelectedTitleChrome(in: sibling, selectedTitle: selectedTitle)
        }
    }

    private static func paintLightSelectedTitleChrome(in view: UIView, selectedTitle: String?) {
        if let effectView = view as? UIVisualEffectView {
            let isTitleVibrancy: Bool
            if #available(iOS 26.0, *) {
                isTitleVibrancy = !(effectView.effect is UIGlassEffect) && effectView.bounds.height < 36
            } else {
                isTitleVibrancy = effectView.effect is UIVibrancyEffect
            }
            if isTitleVibrancy || effectView.effect is UIVibrancyEffect {
                effectView.effect = nil
            }
        }

        if let control = view as? UIControl, !(view is UITabBar), control.isSelected {
            if control.tintColor != .white {
                control.tintColor = .white
            }
        }

        if let label = view as? UILabel {
            let text = (label.text ?? label.attributedText?.string ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if isLightSelectedTitle(text, selectedTitle: selectedTitle, in: label) {
                label.textColor = .white
                label.tintColor = .white
                if !text.isEmpty {
                    var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: UIColor.white]
                    if let font = label.font { attributes[.font] = font }
                    label.attributedText = NSAttributedString(string: text, attributes: attributes)
                }
            }
        }

        if let button = view as? UIButton, button.isSelected {
            let text = (button.currentTitle
                ?? button.configuration?.title
                ?? button.titleLabel?.text
                ?? selectedTitle
                ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            button.setTitleColor(.white, for: .selected)
            button.setTitleColor(.white, for: .normal)
            button.titleLabel?.textColor = .white
            if var config = button.configuration {
                config.baseForegroundColor = .white
                if !text.isEmpty {
                    var title = AttributedString(text)
                    title.foregroundColor = .white
                    config.attributedTitle = title
                }
                button.configuration = config
            }
        }

        if let effectView = view as? UIVisualEffectView {
            paintLightSelectedTitleChrome(in: effectView.contentView, selectedTitle: selectedTitle)
        }
        for subview in view.subviews {
            paintLightSelectedTitleChrome(in: subview, selectedTitle: selectedTitle)
        }
    }

    private static func isLightSelectedTitle(
        _ text: String,
        selectedTitle: String?,
        in view: UIView
    ) -> Bool {
        guard !text.isEmpty, text.count <= 24 else { return false }
        if let selectedTitle, text == selectedTitle { return true }
        var node: UIView? = view
        while let current = node {
            if let control = current as? UIControl {
                return control.isSelected && text.count <= 24
            }
            node = current.superview
        }
        return false
    }

    private static func restoreTemplateGlyphs(on tabBar: UITabBar) {
        let symbols = ["map", "car", "chart.bar", "gearshape"]
        guard let items = tabBar.items, items.count == symbols.count else { return }
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        for (item, name) in zip(items, symbols) {
            item.image = UIImage(systemName: name, withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate)
            item.selectedImage = UIImage(systemName: "\(name).fill", withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate)
            item.setTitleTextAttributes(nil, for: .normal)
            item.setTitleTextAttributes(nil, for: .selected)
        }
    }

    private static func clearGlassTint(on tabBar: UITabBar) {
        guard #available(iOS 26.0, *) else { return }
        clearGlassTint(in: tabBar, matching: tabBar)
        guard let superview = tabBar.superview else { return }
        let barFrame = tabBar.frame
        for sibling in superview.subviews where sibling !== tabBar {
            let isChromeBand = sibling.frame.maxY >= barFrame.minY - 40
                && sibling.frame.height <= barFrame.height + 120
            guard isChromeBand else { continue }
            clearGlassTint(in: sibling, matching: tabBar)
        }
    }

    @available(iOS 26.0, *)
    private static func clearGlassTint(in view: UIView, matching tabBar: UITabBar) {
        if let effectView = view as? UIVisualEffectView,
           let glass = effectView.effect as? UIGlassEffect,
           isFloatingCapsule(effectView, matching: tabBar),
           glass.tintColor != nil {
            glass.tintColor = nil
            effectView.effect = glass
        }
        for subview in view.subviews {
            clearGlassTint(in: subview, matching: tabBar)
        }
    }

    private static func isFloatingCapsule(_ effectView: UIView, matching tabBar: UITabBar) -> Bool {
        let width = effectView.bounds.width
        let height = effectView.bounds.height
        let barWidth = tabBar.bounds.width
        guard width > 8, barWidth > 8 else { return false }
        return width > barWidth * 0.45 && height >= 44 && height <= 96
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

    static func applyDarkSelectionTint(to tabBar: UITabBar, palette: ShellPalette) {
        let selected = TrailhoundTabBarTheme.selectedGlyphUIColor(palette: palette, scheme: .dark)
        let unselected = TrailhoundTabBarTheme.unselectedUIColor(palette: palette, scheme: .dark)
        if tabBar.tintColor != selected {
            tabBar.tintColor = selected
        }
        if tabBar.unselectedItemTintColor != unselected {
            tabBar.unselectedItemTintColor = unselected
        }

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
}

/// Hosts a zero-size controller that walks the window and styles `UITabBar`.
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
        guard let tabBar = resolveTabBar() else { return }
        TrailhoundTabBarCompact.restoreSystemWidthIfNeeded(tabBar)
        if colorScheme == .light {
            if tabBar.tintColor != .white {
                tabBar.tintColor = .white
            }
            TrailhoundTabBarCompact.paintLightSelectedTitle(in: tabBar)
        }
    }

    func apply() {
        guard let tabBar = resolveTabBar() else { return }
        TrailhoundTabBarCompact.apply(to: tabBar, palette: palette, scheme: colorScheme)
        if colorScheme == .light {
            DispatchQueue.main.async { [weak self] in
                guard let self, let tabBar = self.resolveTabBar() else { return }
                TrailhoundTabBarCompact.paintLightSelectedTitle(in: tabBar)
            }
        }
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
