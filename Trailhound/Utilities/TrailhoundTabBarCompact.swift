import SwiftUI
import UIKit

/// Selected-tab icon, label, and iOS 26 pill colors from `ShellPalette`.
/// Light selected is white on a dark-atmosphere glass blob. Light unselected
/// uses the same palette tint as Done (`tintColor`). Dark selected is palette tint.
enum TrailhoundTabBarTheme {
    static func selectedUIColor(palette: ShellPalette, scheme: ColorScheme) -> UIColor {
        let hue = scheme == .light
            ? palette.atmosphere(for: .dark).tint
            : palette.atmosphere(for: scheme).tint
        return uiColor(hue)
    }

    /// Light unselected matches Done (`tintColor` for light). Dark unselected stays white.
    static func unselectedUIColor(palette: ShellPalette, scheme: ColorScheme) -> UIColor {
        if scheme == .dark { return .white }
        return uiColor(palette.atmosphere(for: .light).tint)
    }

    /// Light selected is white. Dark selected uses the palette tint.
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

    /// Selected-tab ice blob in Light — dark mid so white glyphs read. Not chip fill, not accent blue.
    static func selectedBlobGlassUIColor(palette: ShellPalette) -> UIColor {
        uiColor(palette.atmosphere(for: .dark).mid)
    }

    /// Outline + fill SF Symbol per tab. Recap uses `star.fill` — `sparkles.fill` /
    /// `sparkle.fill` are missing, so selected Recap was a transparent hole on ice.
    static let itemSymbols: [(outline: String, fill: String)] = [
        ("map", "map.fill"),
        ("car", "car.fill"),
        ("chart.bar", "chart.bar.fill"),
        ("star", "star.fill"),
        ("gearshape", "gearshape.fill")
    ]
}

/// System iOS 26 `UITabBar`. Light selected is white on a dark glass blob.
/// Dark sets palette `tintColor`. Do not copy `UITabBarAppearance` on iOS 26.
@MainActor
enum TrailhoundTabBarCompact {
    static func apply(to tabBar: UITabBar, palette: ShellPalette, scheme: ColorScheme) {
        tabBar.isHidden = false
        tabBar.alpha = 1
        restoreSystemWidthIfNeeded(tabBar)
        restoreSystemDefault(tabBar)
        if scheme == .light {
            applyLightSelectedWhite(to: tabBar, palette: palette)
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
        clearItemInterfaceStylePins(in: tabBar)
    }

    private static func clearInterfaceStylePin(_ tabBar: UITabBar) {
        if tabBar.overrideUserInterfaceStyle != .unspecified {
            tabBar.overrideUserInterfaceStyle = .unspecified
        }
        guard let superview = tabBar.superview else { return }
        for sibling in superview.subviews where sibling !== tabBar {
            guard isTabChromeSibling(sibling, of: tabBar) else { continue }
            if sibling.overrideUserInterfaceStyle != .unspecified {
                sibling.overrideUserInterfaceStyle = .unspecified
            }
        }
    }

    /// Selected icon + title stay white on a dark-atmosphere blob. Unselected
    /// icon + title use the light palette tint — the same ink as Done.
    static func applyLightSelectedWhite(to tabBar: UITabBar, palette: ShellPalette) {
        let unselected = TrailhoundTabBarTheme.unselectedUIColor(palette: palette, scheme: .light)
        if tabBar.tintColor != .white {
            tabBar.tintColor = .white
        }
        if tabBar.unselectedItemTintColor != unselected {
            tabBar.unselectedItemTintColor = unselected
        }
        let symbols = TrailhoundTabBarTheme.itemSymbols
        if let items = tabBar.items, items.count == symbols.count {
            let selectedConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
            let normalConfig = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
            for (item, symbol) in zip(items, symbols) {
                item.image = UIImage(systemName: symbol.outline, withConfiguration: normalConfig)?
                    .withTintColor(unselected, renderingMode: .alwaysOriginal)
                let name = UIImage(systemName: symbol.fill) == nil ? symbol.outline : symbol.fill
                item.selectedImage = UIImage(systemName: name, withConfiguration: selectedConfig)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal)
                item.setTitleTextAttributes([.foregroundColor: unselected], for: .normal)
                item.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
            }
        }
        paintLightSelectedTitle(in: tabBar, ink: .white, unselected: unselected)
        pinSelectedItemDarkGlass(in: tabBar)
        tintLightSelectedBlob(on: tabBar, palette: palette)
    }

    /// iOS 26 title vibrancy remaps the selected label to accent blue. Lift
    /// vibrancy on the title only — never `UIGlassEffect`. Unselected titles
    /// are stamped with the Done tint so they do not fall back to black.
    static func paintLightSelectedTitle(in tabBar: UITabBar, ink: UIColor, unselected: UIColor) {
        let selectedTitle = tabBar.selectedItem?.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let titles = Set(
            (tabBar.items ?? []).compactMap { item -> String? in
                let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let title, !title.isEmpty else { return nil }
                return title
            }
        )
        paintLightSelectedTitleChrome(
            in: tabBar,
            selectedTitle: selectedTitle,
            titles: titles,
            ink: ink,
            unselected: unselected
        )
        guard let superview = tabBar.superview else { return }
        for sibling in superview.subviews where sibling !== tabBar {
            guard isTabChromeSibling(sibling, of: tabBar) else { continue }
            paintLightSelectedTitleChrome(
                in: sibling,
                selectedTitle: selectedTitle,
                titles: titles,
                ink: ink,
                unselected: unselected
            )
        }
    }

    private static func paintLightSelectedTitleChrome(
        in view: UIView,
        selectedTitle: String?,
        titles: Set<String>,
        ink: UIColor,
        unselected: UIColor
    ) {
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

        if let control = view as? UIControl, !(view is UITabBar) {
            let style: UIUserInterfaceStyle = control.isSelected ? .dark : .unspecified
            if control.overrideUserInterfaceStyle != style {
                control.overrideUserInterfaceStyle = style
            }
            if control.isSelected, control.tintColor != ink {
                control.tintColor = ink
            }
        }

        if let imageView = view as? UIImageView, let itemInk = tabItemInk(
            for: imageView,
            selected: ink,
            unselected: unselected
        ) {
            imageView.tintColor = itemInk
            if let image = imageView.image {
                imageView.image = image.withTintColor(itemInk, renderingMode: .alwaysOriginal)
            }
        }

        if let label = view as? UILabel {
            let text = (label.text ?? label.attributedText?.string ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if isLightSelectedTitle(text, selectedTitle: selectedTitle, in: label) {
                applyLabelInk(label, text: text, ink: ink)
            } else if titles.contains(text), tabItemControl(containing: label)?.isSelected == false {
                applyLabelInk(label, text: text, ink: unselected)
            }
        }

        if let button = view as? UIButton {
            let text = (button.currentTitle
                ?? button.configuration?.title
                ?? button.titleLabel?.text
                ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let buttonInk: UIColor?
            if button.isSelected {
                buttonInk = ink
            } else if titles.contains(text) {
                buttonInk = unselected
            } else {
                buttonInk = nil
            }
            if let buttonInk {
                button.setTitleColor(buttonInk, for: button.isSelected ? .selected : .normal)
                if button.isSelected {
                    button.setTitleColor(buttonInk, for: .normal)
                }
                button.titleLabel?.textColor = buttonInk
                if var config = button.configuration {
                    config.baseForegroundColor = buttonInk
                    let titleText = text.isEmpty && button.isSelected ? (selectedTitle ?? "") : text
                    if !titleText.isEmpty {
                        var title = AttributedString(titleText)
                        title.foregroundColor = Color(uiColor: buttonInk)
                        config.attributedTitle = title
                    }
                    button.configuration = config
                }
            }
        }

        if let effectView = view as? UIVisualEffectView {
            paintLightSelectedTitleChrome(
                in: effectView.contentView,
                selectedTitle: selectedTitle,
                titles: titles,
                ink: ink,
                unselected: unselected
            )
        }
        for subview in view.subviews {
            paintLightSelectedTitleChrome(
                in: subview,
                selectedTitle: selectedTitle,
                titles: titles,
                ink: ink,
                unselected: unselected
            )
        }
    }

    private static func applyLabelInk(_ label: UILabel, text: String, ink: UIColor) {
        label.textColor = ink
        label.tintColor = ink
        guard !text.isEmpty else { return }
        var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: ink]
        if let font = label.font { attributes[.font] = font }
        label.attributedText = NSAttributedString(string: text, attributes: attributes)
    }

    /// Selected items stay white. Unselected tab glyphs use the Done tint.
    private static func tabItemInk(for view: UIView, selected: UIColor, unselected: UIColor) -> UIColor? {
        guard let control = tabItemControl(containing: view) else { return nil }
        return control.isSelected ? selected : unselected
    }

    private static func tabItemControl(containing view: UIView) -> UIControl? {
        var node: UIView? = view
        while let current = node {
            if let control = current as? UIControl, !(current is UITabBar) {
                return control
            }
            node = current.superview
        }
        return nil
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

    /// Selected item draws Dark glass so the white glyph sits on a dark blob, not ice.
    static func pinSelectedItemDarkGlass(in root: UIView) {
        if let control = root as? UIControl, !(root is UITabBar) {
            let style: UIUserInterfaceStyle = control.isSelected ? .dark : .unspecified
            if control.overrideUserInterfaceStyle != style {
                control.overrideUserInterfaceStyle = style
            }
        }
        for subview in root.subviews {
            pinSelectedItemDarkGlass(in: subview)
        }
    }

    private static func clearItemInterfaceStylePins(in view: UIView) {
        if let control = view as? UIControl, !(view is UITabBar),
           control.overrideUserInterfaceStyle != .unspecified {
            control.overrideUserInterfaceStyle = .unspecified
        }
        for subview in view.subviews {
            clearItemInterfaceStylePins(in: subview)
        }
    }

    /// The side/bottom platter exists before the selection circle. Launch styling
    /// that runs too early leaves the system capsule until the next tab change.
    static func lightSelectionBlobIsReady(_ tabBar: UITabBar) -> Bool {
        guard #available(iOS 26.0, *) else { return true }
        guard tabBar.bounds.width > 8, tabBar.bounds.height > 8 else { return false }
        if containsSelectionBlob(in: tabBar, matching: tabBar) { return true }
        guard let superview = tabBar.superview else { return false }
        for sibling in superview.subviews where sibling !== tabBar {
            guard isTabChromeSibling(sibling, of: tabBar) else { continue }
            if containsSelectionBlob(in: sibling, matching: tabBar) { return true }
        }
        return false
    }

    @available(iOS 26.0, *)
    private static func containsSelectionBlob(in view: UIView, matching tabBar: UITabBar) -> Bool {
        if let effectView = view as? UIVisualEffectView,
           effectView.effect is UIGlassEffect,
           effectView.bounds.width > 8,
           !isFloatingCapsule(effectView, matching: tabBar) {
            return true
        }
        if let effectView = view as? UIVisualEffectView,
           containsSelectionBlob(in: effectView.contentView, matching: tabBar) {
            return true
        }
        for subview in view.subviews {
            if containsSelectionBlob(in: subview, matching: tabBar) { return true }
        }
        return false
    }

    /// Tint every non-capsule `UIGlassEffect` in the bar with dark mid — the selection blob.
    static func tintLightSelectedBlob(on tabBar: UITabBar, palette: ShellPalette) {
        guard #available(iOS 26.0, *) else { return }
        let tint = TrailhoundTabBarTheme.selectedBlobGlassUIColor(palette: palette)
        tintSelectedBlob(in: tabBar, matching: tabBar, tint: tint)
        guard let superview = tabBar.superview else { return }
        for sibling in superview.subviews where sibling !== tabBar {
            guard isTabChromeSibling(sibling, of: tabBar) else { continue }
            tintSelectedBlob(in: sibling, matching: tabBar, tint: tint)
        }
    }

    @available(iOS 26.0, *)
    private static func tintSelectedBlob(in view: UIView, matching tabBar: UITabBar, tint: UIColor) {
        if let effectView = view as? UIVisualEffectView,
           let glass = effectView.effect as? UIGlassEffect,
           !isFloatingCapsule(effectView, matching: tabBar) {
            glass.tintColor = tint
            effectView.effect = glass
        }
        if let effectView = view as? UIVisualEffectView {
            tintSelectedBlob(in: effectView.contentView, matching: tabBar, tint: tint)
        }
        for subview in view.subviews {
            tintSelectedBlob(in: subview, matching: tabBar, tint: tint)
        }
    }

    private static func restoreTemplateGlyphs(on tabBar: UITabBar) {
        let symbols = TrailhoundTabBarTheme.itemSymbols
        guard let items = tabBar.items, items.count == symbols.count else { return }
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .medium)
        for (item, symbol) in zip(items, symbols) {
            item.image = UIImage(systemName: symbol.outline, withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate)
            item.selectedImage = UIImage(systemName: symbol.fill, withConfiguration: config)?
                .withRenderingMode(.alwaysTemplate)
            item.setTitleTextAttributes(nil, for: .normal)
            item.setTitleTextAttributes(nil, for: .selected)
        }
    }

    private static func clearGlassTint(on tabBar: UITabBar) {
        guard #available(iOS 26.0, *) else { return }
        clearGlassTint(in: tabBar, matching: tabBar)
        guard let superview = tabBar.superview else { return }
        for sibling in superview.subviews where sibling !== tabBar {
            guard isTabChromeSibling(sibling, of: tabBar) else { continue }
            clearGlassTint(in: sibling, matching: tabBar)
        }
    }

    @available(iOS 26.0, *)
    private static func clearGlassTint(in view: UIView, matching tabBar: UITabBar) {
        if let effectView = view as? UIVisualEffectView,
           let glass = effectView.effect as? UIGlassEffect,
           glass.tintColor != nil {
            glass.tintColor = nil
            effectView.effect = glass
        }
        if let effectView = view as? UIVisualEffectView {
            clearGlassTint(in: effectView.contentView, matching: tabBar)
        }
        for subview in view.subviews {
            clearGlassTint(in: subview, matching: tabBar)
        }
    }

    /// Bottom platter is wide and short. A side bar's platter is tall. A selection
    /// circle on that side bar is almost as wide as the bar, so width alone must
    /// not treat it as the platter — that left the selected tab on system blue.
    private static func isFloatingCapsule(_ effectView: UIView, matching tabBar: UITabBar) -> Bool {
        let width = effectView.bounds.width
        let height = effectView.bounds.height
        let barWidth = tabBar.bounds.width
        let barHeight = tabBar.bounds.height
        guard width > 8, barWidth > 8, barHeight > 8 else { return false }
        if barHeight > barWidth * 1.4 {
            return height > barHeight * 0.72 && width > barWidth * 0.55
        }
        return width > barWidth * 0.45 && height >= 44 && height <= 96
    }

    /// Bottom chrome sits under the bar. Side chrome sits in the leading column.
    private static func isTabChromeSibling(_ sibling: UIView, of tabBar: UITabBar) -> Bool {
        let bar = tabBar.frame
        let frame = sibling.frame
        if bar.height > bar.width * 1.4 {
            let overlapsY = frame.maxY > bar.minY - 24 && frame.minY < bar.maxY + 24
            let nearX = abs(frame.midX - bar.midX) < max(bar.width, 80) + 48
            let notContent = frame.width < bar.width + 180
            return overlapsY && nearX && notContent
        }
        return frame.maxY >= bar.minY - 40 && frame.height <= bar.height + 120
    }

    /// Undo a leftover narrow frame from the old compact hack. Skip once the bar is full width.
    /// A side tab bar is supposed to be narrow — stretching it wipes the liquid glass column.
    static func restoreSystemWidthIfNeeded(_ tabBar: UITabBar) {
        guard tabBar.bounds.width >= tabBar.bounds.height else { return }
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
    private var glassRetryCount = 0
    private var glassRetryScheduled = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        glassRetryCount = 0
        apply()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let tabBar = resolveTabBar() else { return }
        TrailhoundTabBarCompact.restoreSystemWidthIfNeeded(tabBar)
        guard colorScheme == .light else { return }
        TrailhoundTabBarCompact.applyLightSelectedWhite(to: tabBar, palette: palette)
        if !TrailhoundTabBarCompact.lightSelectionBlobIsReady(tabBar) {
            scheduleGlassRetry()
        }
    }

    func apply() {
        guard let tabBar = resolveTabBar() else {
            scheduleGlassRetry()
            return
        }
        TrailhoundTabBarCompact.apply(to: tabBar, palette: palette, scheme: colorScheme)
        guard colorScheme == .light else { return }
        if TrailhoundTabBarCompact.lightSelectionBlobIsReady(tabBar) {
            glassRetryCount = 0
        } else {
            scheduleGlassRetry()
        }
    }

    /// iOS 26 builds the selection circle after the first layout. Until it exists,
    /// styling hits only the platter and the bar stays the system capsule.
    private func scheduleGlassRetry() {
        guard glassRetryCount < 24, !glassRetryScheduled else { return }
        glassRetryCount += 1
        glassRetryScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.glassRetryScheduled = false
            self.apply()
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
