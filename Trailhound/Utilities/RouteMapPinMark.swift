import SwiftUI
import UIKit

/// Shared trip-route map pin kinds — same vocabulary as trip detail.
enum RouteMapPinKind: Hashable {
    case start
    case end
    case stop

    var systemName: String {
        switch self {
        case .start: "flag.fill"
        case .end: "mappin.circle.fill"
        case .stop: "pause.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .start: .green
        case .end: .red
        case .stop: .orange
        }
    }

    var uiColor: UIColor {
        switch self {
        case .start: .systemGreen
        case .end: .systemRed
        case .stop: .systemOrange
        }
    }

    /// Endpoints use a white ring and larger padding; stops are slightly smaller.
    var isEndpoint: Bool {
        switch self {
        case .start, .end: true
        case .stop: false
        }
    }

    /// Matches trip detail `routeAnnotationMark` visibleScale when popped.
    var visibleScale: CGFloat { isEndpoint ? 0.8 : 0.6375 }

    var padding: CGFloat { isEndpoint ? 8 : 6 }
}

/// Circular badge pin matching trip detail map annotations.
struct RouteMapPinMark: View {
    let kind: RouteMapPinKind
    var popped: Bool = true
    var reduceMotion: Bool = false

    var body: some View {
        RouteMapPinBadge(kind: kind)
            .scaleEffect(popped ? kind.visibleScale : 0.35)
            .opacity(popped ? 1 : 0)
            .shadow(color: kind.color.opacity(0.45), radius: popped ? 5 : 0, y: 1)
            .animation(reduceMotion ? nil : TrailhoundMotion.pinPop, value: popped)
    }
}

/// Badge chrome only (no pop animation) — used by SwiftUI maps and ImageRenderer.
struct RouteMapPinBadge: View {
    let kind: RouteMapPinKind

    var body: some View {
        Image(systemName: kind.systemName)
            .font(kind.isEndpoint ? .body.weight(.semibold) : .body)
            .padding(kind.padding)
            .background(kind.color, in: Circle())
            .foregroundStyle(.white)
            .overlay {
                if kind.isEndpoint {
                    Circle()
                        .strokeBorder(.white, lineWidth: 2)
                }
            }
    }
}

/// Renders pin badges to a bitmap for MapKit annotation views.
@MainActor
enum RouteMapPinImage {
    /// Cached images keyed by pin kind (fully popped visual size + shadow).
    private static var cache: [RouteMapPinKind: UIImage] = [:]

    static func uiImage(for kind: RouteMapPinKind) -> UIImage {
        if let cached = cache[kind] {
            return cached
        }
        let mark = RouteMapPinBadge(kind: kind)
            .shadow(color: kind.color.opacity(0.45), radius: 5, y: 1)
            // Extra padding so the shadow is not clipped by ImageRenderer.
            .padding(6)
        let renderer = ImageRenderer(content: mark)
        renderer.scale = UITraitCollection.current.displayScale
        let full = renderer.uiImage ?? fallbackUIImage(for: kind)
        // Match trip detail popped scale without leaving scaleEffect transparent margins.
        let image = scaled(full, by: kind.visibleScale)
        cache[kind] = image
        return image
    }

    private static func scaled(_ image: UIImage, by factor: CGFloat) -> UIImage {
        guard factor > 0, factor != 1 else { return image }
        let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// UIKit fallback if ImageRenderer fails (rare). Unscaled; caller applies `visibleScale`.
    private static func fallbackUIImage(for kind: RouteMapPinKind) -> UIImage {
        let diameter: CGFloat = kind.isEndpoint ? 36 : 28
        let pad: CGFloat = 6
        let size = CGSize(width: diameter + pad * 2, height: diameter + pad * 2)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            let rect = CGRect(
                x: (size.width - diameter) / 2,
                y: (size.height - diameter) / 2,
                width: diameter,
                height: diameter
            )
            let path = UIBezierPath(ovalIn: rect)
            kind.uiColor.setFill()
            path.fill()
            if kind.isEndpoint {
                UIColor.white.setStroke()
                path.lineWidth = 2
                path.stroke()
            }
            let pointSize: CGFloat = kind.isEndpoint ? 14 : 12
            let config = UIImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            guard let symbol = UIImage(systemName: kind.systemName, withConfiguration: config)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) else { return }
            let symbolSize = symbol.size
            symbol.draw(
                at: CGPoint(
                    x: (size.width - symbolSize.width) / 2,
                    y: (size.height - symbolSize.height) / 2
                )
            )
        }
    }
}
