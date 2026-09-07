import UIKit

/// Maps `ShellPalette` to a bundled alternate Home Screen icon.
/// Sky keeps the primary Liquid Glass `Trailhound` icon (`nil`).
enum AppIconSync {
    @MainActor private static var pendingTask: Task<Void, Never>?
    @MainActor private static var inFlightTarget: String?

    static func alternateIconName(for palette: ShellPalette) -> String? {
        guard palette != .sky else { return nil }
        let raw = palette.rawValue
        let first = raw.prefix(1).uppercased(with: Locale(identifier: "en_US_POSIX"))
        return "AppIcon\(first)\(raw.dropFirst())"
    }

    static var alternateIconNames: [String] {
        ShellPalette.allCases.compactMap { alternateIconName(for: $0) }
    }

    static func needsUpdate(currentAlternateIconName: String?, palette: ShellPalette) -> Bool {
        alternateIconName(for: palette) != currentAlternateIconName
    }

    @MainActor
    static func apply(_ palette: ShellPalette) {
        guard !UITestSupport.isEnabled, !UITestSupport.isUnitTesting else { return }
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let targetName = alternateIconName(for: palette)
        let targetKey = targetName ?? "__primary__"
        guard UIApplication.shared.alternateIconName != targetName,
              inFlightTarget != targetKey else { return }

        // Coalesce repeated SwiftUI changes before asking iOS. The public API
        // always presents exactly one system confirmation.
        pendingTask?.cancel()
        pendingTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            guard UIApplication.shared.alternateIconName != targetName,
                  inFlightTarget != targetKey else { return }

            AppearanceWindowStyle.sync(AppSettings.shared.appearanceMode)
            await Task.yield()
            guard !Task.isCancelled else { return }

            inFlightTarget = targetKey
            UIApplication.shared.setAlternateIconName(targetName) { error in
                Task { @MainActor in
                    inFlightTarget = nil
                    if let error {
                        DevLog.shared.error(.general, "App icon sync failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}

/// Keeps UIKit windows on the same Light/Dark as SwiftUI `preferredColorScheme`.
enum AppearanceWindowStyle {
    @MainActor
    static func sync(_ mode: AppearanceMode) {
        let style: UIUserInterfaceStyle
        switch mode {
        case .system: style = .unspecified
        case .light: style = .light
        case .dark: style = .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                if window.overrideUserInterfaceStyle != style {
                    window.overrideUserInterfaceStyle = style
                }
            }
        }
    }
}
