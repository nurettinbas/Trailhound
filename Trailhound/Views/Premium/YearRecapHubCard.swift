import CoreLocation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct YearRecapHubCard: View {
    let snapshot: YearRecapSnapshot
    var onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(format: L10n.string("premium.recap.year_title"), snapshot.year))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if snapshot.hasData {
                Text(DateFormatters.formatDistance(snapshot.distanceMeters))
                    .font(.title.weight(.bold).monospacedDigit())
                HStack(spacing: 12) {
                    labeled(String(snapshot.tripCount), L10n.string("premium.recap.trips"))
                    if snapshot.cityCount > 0 {
                        labeled("\(snapshot.cityCount)", L10n.string("premium.recap.cities"))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Button(L10n.string("premium.recap.play"), action: onPlay)
                    .buttonStyle(.borderedProminent)
                    .tint(TrailhoundBrandColors.brandBottom)
                    .accessibilityIdentifier("stats.premium.recap.play")
            } else {
                Text(L10n.string("premium.recap.empty"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityIdentifier("stats.premium.recap")
    }

    private func labeled(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline.weight(.semibold).monospacedDigit())
            Text(title)
        }
    }
}

private enum RecapStoryPage: Int, CaseIterable, Hashable {
    case intro
    case distance
    case cities
    case route
    case time
    case categories
    case cost
    case badges
    case closing
}

struct YearRecapStoryView: View {
    let snapshot: YearRecapSnapshot
    var onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page: RecapStoryPage = .intro
    @State private var displayedDistance: Double = 0
    @State private var advanceTask: Task<Void, Never>?
    @State private var shareItem = RecapShareItem.empty

    private var pages: [RecapStoryPage] {
        RecapStoryPage.allCases.filter { page in
            switch page {
            case .cities: snapshot.cityCount > 0
            case .time: snapshot.longestStreak > 0 || snapshot.busiestMonth != nil || snapshot.nightDistanceMeters > 0
            case .categories: snapshot.businessDistanceMeters > 0 || snapshot.personalDistanceMeters > 0
            case .route: snapshot.topRouteCount >= 2
            case .cost: snapshot.estimatedFuelCost > 0 || snapshot.paidExpenses > 0
            case .badges: !snapshot.unlockedAchievementIDs.isEmpty
            default: true
            }
        }
    }

    var body: some View {
        ZStack {
            AtmosphericBackground()
            VStack(spacing: 24) {
                pageContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 28)
                HStack {
                    Button(L10n.string("action.close"), action: close)
                    Spacer()
                    ShareLink(item: shareItem, preview: SharePreview("Trailhound", image: Image(uiImage: shareItem.image))) {
                        Label(L10n.string("action.share"), systemImage: "square.and.arrow.up")
                    }
                    Button(L10n.string("premium.recap.next"), action: advance)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            shareItem = RecapShareRenderer.item(for: snapshot)
            animateDistance()
            scheduleAdvance()
        }
        .onChange(of: page) { _, _ in
            animateDistance()
            scheduleAdvance()
        }
        .onDisappear {
            advanceTask?.cancel()
            FrequentRoutesSnapshotCache.shared.dropMemory()
        }
        .onTapGesture { advance() }
        .accessibilityIdentifier("stats.premium.recap.story")
        .accessibilityLabel(String(format: L10n.string("premium.recap.page_a11y"), pageIndex + 1, pages.count))
    }

    @ViewBuilder
    private var pageContent: some View {
        switch page {
        case .intro:
            VStack(spacing: 16) {
                TrailhoundBrandMark()
                Text(String(format: L10n.string("premium.recap.intro"), snapshot.year))
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
            }
        case .distance:
            VStack(spacing: 8) {
                Text(DateFormatters.formatDistance(displayedDistance))
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(String(format: L10n.string("premium.recap.distance_body"), snapshot.tripCount))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        case .cities:
            VStack(spacing: 12) {
                Text("\(snapshot.cityCount)")
                    .font(.system(size: 56, weight: .bold, design: .rounded).monospacedDigit())
                Text(L10n.string("premium.recap.cities_body"))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                ForEach(snapshot.topCities, id: \.self) { city in
                    Text(city).font(.headline)
                }
            }
        case .route:
            VStack(spacing: 10) {
                Text(L10n.string("premium.recap.route_title"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                RecapRouteMiniMap(snapshot: snapshot)
                Text("\(snapshot.topRouteStart ?? "") → \(snapshot.topRouteEnd ?? "")")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(String(format: L10n.string("premium.recap.route_count"), snapshot.topRouteCount))
                    .foregroundStyle(.secondary)
            }
        case .time:
            VStack(spacing: 12) {
                if snapshot.nightDistanceMeters > 0 {
                    Text(String(format: L10n.string("premium.recap.night"), DateFormatters.formatDistance(snapshot.nightDistanceMeters)))
                        .font(.title2.weight(.bold))
                }
                if snapshot.longestStreak > 0 {
                    Text(String(format: L10n.string("premium.recap.streak"), snapshot.longestStreak))
                        .font(.title2.weight(.bold))
                }
                if let month = snapshot.busiestMonth {
                    Text(String(format: L10n.string("premium.recap.busiest_month"), monthName(month)))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
        case .categories:
            VStack(spacing: 10) {
                Text(L10n.string("premium.recap.categories_title"))
                    .font(.headline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 28) {
                    VStack {
                        Text(DateFormatters.formatDistance(snapshot.businessDistanceMeters))
                            .font(.title3.weight(.bold).monospacedDigit())
                        Text(L10n.string("premium.recap.business"))
                            .foregroundStyle(.secondary)
                    }
                    VStack {
                        Text(DateFormatters.formatDistance(snapshot.personalDistanceMeters))
                            .font(.title3.weight(.bold).monospacedDigit())
                        Text(L10n.string("premium.recap.personal"))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }
        case .cost:
            VStack(spacing: 10) {
                Text(FuelCostCalculator.formatCost(snapshot.estimatedFuelCost))
                    .font(.title.weight(.bold).monospacedDigit())
                Text(L10n.string("premium.recap.fuel"))
                    .foregroundStyle(.secondary)
                if snapshot.paidExpenses > 0 {
                    Text(FuelCostCalculator.formatCost(snapshot.paidExpenses))
                        .font(.title2.weight(.semibold).monospacedDigit())
                    Text(L10n.string("premium.recap.paid"))
                        .foregroundStyle(.secondary)
                }
            }
        case .badges:
            VStack(spacing: 12) {
                Text(L10n.string("premium.recap.badges_title"))
                    .font(.headline)
                ForEach(snapshot.unlockedAchievementIDs, id: \.self) { id in
                    if let achievement = AchievementID(rawValue: id) {
                        Label(L10n.string(achievement.titleKey), systemImage: achievement.systemImage)
                    }
                }
            }
        case .closing:
            VStack(spacing: 16) {
                Text(L10n.string("premium.recap.closing"))
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Button(L10n.string("premium.recap.done"), action: close)
                    .buttonStyle(.borderedProminent)
                    .tint(TrailhoundBrandColors.brandBottom)
            }
        }
    }

    private var pageIndex: Int {
        pages.firstIndex(of: page) ?? 0
    }

    private func advance() {
        let next = pageIndex + 1
        if next < pages.count {
            withAnimation(TrailhoundMotion.recapPage(reduceMotion: reduceMotion)) {
                page = pages[next]
            }
        } else {
            close()
        }
    }

    private func close() {
        advanceTask?.cancel()
        TrailhoundHaptics.badgeUnlocked()
        onClose()
    }

    private func scheduleAdvance() {
        advanceTask?.cancel()
        guard !reduceMotion, page != .closing else { return }
        advanceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(4.5))
            guard !Task.isCancelled else { return }
            advance()
        }
    }

    private func animateDistance() {
        guard page == .distance else { return }
        displayedDistance = reduceMotion ? snapshot.distanceMeters : 0
        withAnimation(TrailhoundMotion.recapCountUp(reduceMotion: reduceMotion)) {
            displayedDistance = snapshot.distanceMeters
        }
    }

    private func monthName(_ month: Int) -> String {
        var components = DateComponents()
        components.month = month
        let date = Calendar.current.date(from: components) ?? Date()
        return DateFormatters.monthYear.string(from: date)
    }
}

private struct RecapRouteMiniMap: View {
    let snapshot: YearRecapSnapshot
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .task {
            guard
                let slat = snapshot.topRouteStartLatitude,
                let slon = snapshot.topRouteStartLongitude,
                let elat = snapshot.topRouteEndLatitude,
                let elon = snapshot.topRouteEndLongitude
            else { return }
            image = await FrequentRoutesSnapshotCache.shared.snapshot(
                start: CLLocationCoordinate2D(latitude: slat, longitude: slon),
                end: CLLocationCoordinate2D(latitude: elat, longitude: elon),
                count: snapshot.topRouteCount,
                isBusiness: false
            )
        }
        .accessibilityHidden(true)
    }
}

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

enum RecapShareRenderer {
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

    static func item(for snapshot: YearRecapSnapshot) -> RecapShareItem {
        RecapShareItem(image: image(for: snapshot), caption: caption(for: snapshot))
    }

    static func image(for snapshot: YearRecapSnapshot) -> UIImage {
        let size = CGSize(width: 1080, height: 1920)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            let colors = [
                UIColor(red: 0.38, green: 0.66, blue: 0.92, alpha: 1).cgColor,
                UIColor(red: 0.23, green: 0.56, blue: 0.85, alpha: 1).cgColor
            ]
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: colors as CFArray,
                locations: [0, 1]
            )!
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: size.height),
                options: []
            )

            let card = rect.insetBy(dx: 72, dy: 180)
            let cardPath = UIBezierPath(roundedRect: card, cornerRadius: 44)
            UIColor.white.withAlphaComponent(0.16).setFill()
            cardPath.fill()
            UIColor.white.withAlphaComponent(0.28).setStroke()
            cardPath.lineWidth = 2
            cardPath.stroke()

            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let yearAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 28, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.85),
                .paragraphStyle: paragraph
            ]
            let kmAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 72, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let bodyAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 32, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.92),
                .paragraphStyle: paragraph
            ]
            let brandAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .semibold),
                .foregroundColor: UIColor.white.withAlphaComponent(0.8),
                .paragraphStyle: paragraph
            ]

            ("Trailhound" as NSString).draw(
                in: CGRect(x: card.minX, y: card.minY + 48, width: card.width, height: 40),
                withAttributes: brandAttrs
            )
            (String(format: L10n.string("premium.recap.intro"), snapshot.year) as NSString).draw(
                in: CGRect(x: card.minX + 24, y: card.minY + 220, width: card.width - 48, height: 80),
                withAttributes: yearAttrs
            )
            (DateFormatters.formatDistance(snapshot.distanceMeters) as NSString).draw(
                in: CGRect(x: card.minX + 24, y: card.midY - 80, width: card.width - 48, height: 90),
                withAttributes: kmAttrs
            )
            (caption(for: snapshot) as NSString).draw(
                in: CGRect(x: card.minX + 36, y: card.midY + 40, width: card.width - 72, height: 220),
                withAttributes: bodyAttrs
            )
        }
    }
}
