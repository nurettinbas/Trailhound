import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct RecapShareItem: Transferable {
    let image: UIImage
    let caption: String

    static let empty = RecapShareItem(image: UIImage(), caption: "Trailhound")

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            item.image.pngData() ?? Data()
        }
    }
}

@MainActor
enum RecapShareRenderer {
    static let pixelSize = CGSize(width: 1080, height: 1920)
    static let layoutWidth: CGFloat = 390
    static var layoutSize: CGSize {
        CGSize(width: layoutWidth, height: layoutWidth * pixelSize.height / pixelSize.width)
    }

    static func caption(for snapshot: YearRecapSnapshot) -> String {
        var parts = [
            String(format: L10n.string("premium.recap.share.distance"), snapshot.year, DateFormatters.formatDistance(snapshot.distanceMeters))
        ]
        if snapshot.cityCount > 0 {
            parts.append(String(format: L10n.string("premium.recap.share.cities"), snapshot.cityCount))
        }
        if snapshot.topRouteCount >= 2, let start = snapshot.topRouteStart, let end = snapshot.topRouteEnd {
            parts.append("\(start) → \(end)")
        }
        return parts.joined(separator: " · ")
    }

    static func item(
        for snapshot: YearRecapSnapshot,
        page: RecapStoryPage,
        palette: ShellPalette,
        scheme: ColorScheme,
        routeImage: UIImage? = nil
    ) -> RecapShareItem {
        RecapShareItem(
            image: image(
                for: snapshot,
                page: page,
                palette: palette,
                scheme: scheme,
                routeImage: routeImage
            ),
            caption: caption(for: snapshot)
        )
    }

    static func image(
        for snapshot: YearRecapSnapshot,
        page: RecapStoryPage,
        palette: ShellPalette,
        scheme: ColorScheme,
        routeImage: UIImage? = nil
    ) -> UIImage {
        let layout = layoutSize
        let card = RecapShareCardView(
            snapshot: snapshot,
            page: page,
            routeImage: routeImage
        )
        .frame(width: layout.width, height: layout.height)
        .environment(\.shellPalette, palette)
        .environment(\.colorScheme, scheme)
        .environment(\.achievementIdleTime, nil)
        .preferredColorScheme(scheme)

        let renderer = ImageRenderer(content: card)
        renderer.proposedSize = ProposedViewSize(width: layout.width, height: layout.height)
        renderer.scale = pixelSize.width / layout.width
        return renderer.uiImage ?? UIImage()
    }
}

private struct RecapShareCardView: View {
    let snapshot: YearRecapSnapshot
    let page: RecapStoryPage
    var routeImage: UIImage?

    var body: some View {
        ZStack(alignment: .top) {
            RecapPageScene(
                page: page,
                isActive: true,
                reduceMotion: true,
                badgeIDs: RecapStoryBadgeIDs.resolved(from: snapshot),
                motion: 0
            )
            RecapStoryBottomScrim()
            VStack(spacing: 0) {
                TrailhoundBrandMark(showsWordmark: true, symbolSize: 36)
                    .padding(.top, 28)
                Spacer(minLength: 0)
                RecapStoryPageForeground(
                    snapshot: snapshot,
                    page: page,
                    displayedDistance: snapshot.distanceMeters,
                    routeImage: routeImage,
                    motion: 0,
                    reduceMotion: true
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGlassShell()
        }
        .clipped()
    }
}
