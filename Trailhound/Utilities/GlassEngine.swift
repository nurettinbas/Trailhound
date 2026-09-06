import SwiftUI

enum GlassEngine: String, Sendable {
    case native
    case material
    case solid
}

enum GlassEngineOverride: String, CaseIterable, Identifiable, Sendable {
    case auto
    case material
    case native

    var id: String { rawValue }
}

enum GlassEngineResolver {
    /// Dark always uses the legacy Material (or solid) recipe.
    /// Light uses native Liquid Glass on iOS 26+ unless overridden or disallowed.
    /// List rows pass `allowsNative: false` so each cell is not its own glass host.
    static func resolve(
        scheme: ColorScheme,
        reduceTransparency: Bool,
        frozen: Bool,
        override: GlassEngineOverride = .auto,
        allowsNative: Bool = true
    ) -> GlassEngine {
        if reduceTransparency || frozen {
            return .solid
        }
        if scheme == .dark {
            return .material
        }
        let wantsNative: Bool
        switch override {
        case .material: wantsNative = false
        case .native, .auto: wantsNative = true
        }
        if wantsNative, allowsNative, isNativeAvailable {
            return .native
        }
        return .material
    }

    static var isNativeAvailable: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }
}
