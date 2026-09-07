import UIKit

/// Maps `ShellPalette` to a bundled alternate Home Screen icon.
/// Sky keeps the primary Liquid Glass `Trailhound` icon (`nil`).
enum AppIconSync {
    static func alternateIconName(for palette: ShellPalette) -> String? {
        guard palette != .sky else { return nil }
        let raw = palette.rawValue
        let first = raw.prefix(1).uppercased(with: Locale(identifier: "en_US_POSIX"))
        return "AppIcon\(first)\(raw.dropFirst())"
    }

    static var alternateIconNames: [String] {
        ShellPalette.allCases.compactMap { alternateIconName(for: $0) }
    }

    @MainActor
    static func apply(_ palette: ShellPalette) {
        guard !UITestSupport.isEnabled, !UITestSupport.isUnitTesting else { return }
        guard UIApplication.shared.supportsAlternateIcons else { return }
        let name = alternateIconName(for: palette)
        guard UIApplication.shared.alternateIconName != name else { return }
        UIApplication.shared.setAlternateIconName(name) { error in
            if let error {
                DevLog.shared.error(.general, "App icon sync failed: \(error.localizedDescription)")
            }
        }
    }
}
