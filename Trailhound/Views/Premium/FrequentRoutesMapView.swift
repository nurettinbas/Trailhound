import MapKit
import SwiftUI
import UIKit

struct FrequentRoutesMapLegend: View {
    let aggregates: [FrequentRouteAggregate]
    var selected: FrequentRouteAggregate?
    var bottomInset: CGFloat = 34
    @Binding var isDark: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer(minLength: 0)
                Picker("style", selection: $isDark) {
                    Text(L10n.string("premium.routes.map.standard")).tag(false)
                    Text(L10n.string("premium.routes.map.dark")).tag(true)
                }
                .glassSegmentedStyle()
                .frame(maxWidth: 180)
            }
            if let selected {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(selected.startDisplay) → \(selected.endDisplay)")
                        .font(.subheadline.weight(.semibold))
                    Text(String(format: L10n.string("premium.routes.map.meta"), selected.count, DateFormatters.formatDistance(selected.totalDistanceMeters)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(selected.lastStartedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else if aggregates.isEmpty {
                Text(L10n.string("premium.routes.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(L10n.string("premium.routes.map.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 20, frozen: true, allowsNative: false)
        .padding(.horizontal, 16)
        .padding(.bottom, max(20, bottomInset))
    }
}

struct FrequentRoutesCardGlobalFrameKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1, next.height > 1 {
            value = next
        }
    }
}

struct FrequentRoutesExpandOverlay: View {
    let aggregates: [FrequentRouteAggregate]
    let sourceGlobal: CGRect
    @Binding var isExpanded: Bool
    var onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var selected: FrequentRouteAggregate?
    @State private var isDark = false

    var body: some View {
        GeometryReader { proxy in
            let dest = proxy.size
            let overlayGlobal = proxy.frame(in: .global)
            let frame = AchievementGalleryExpandLayout.localSurface(
                sourceGlobal: sourceGlobal,
                overlayGlobal: overlayGlobal,
                expanded: isExpanded
            )
            let radius = AchievementGalleryExpandLayout.cornerRadius(expanded: isExpanded)
            let scaleX = frame.width / max(dest.width, 1)
            let scaleY = frame.height / max(dest.height, 1)
            let window = windowSafeInsets
            let topInset = max(proxy.safeAreaInsets.top, window.top, 54)
            let bottomInset = max(proxy.safeAreaInsets.bottom, window.bottom, 34)
            ZStack {
                Color.clear
                    .allowsHitTesting(false)
                Color.clear
                    .frame(width: frame.width, height: frame.height)
                    .overlay(alignment: .topLeading) {
                        FrequentRoutesMapKitView(
                            aggregates: aggregates,
                            isDark: isDark || colorScheme == .dark,
                            onSelect: { selected = $0 }
                        )
                        .transaction { $0.animation = nil }
                        .frame(width: dest.width, height: dest.height)
                        .scaleEffect(x: scaleX, y: scaleY, anchor: .topLeading)
                        .allowsHitTesting(isExpanded)
                        .accessibilityIdentifier("stats.premium.routes.map")
                    }
                    .overlay(alignment: .top) {
                        FrequentRoutesPreviewCard(
                            aggregates: aggregates,
                            isExpanded: true,
                            onOpen: {}
                        )
                        .padding(StatsCardTokens.contentInset)
                        .opacity(isExpanded ? 0 : 1)
                        .allowsHitTesting(false)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .position(x: frame.midX, y: frame.midY)
                FrequentRoutesMapLegend(
                    aggregates: aggregates,
                    selected: selected,
                    bottomInset: bottomInset,
                    isDark: $isDark
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .opacity(isExpanded ? 1 : 0)
                .allowsHitTesting(isExpanded)
                .animation(TrailhoundMotion.badgeGalleryAppear(reduceMotion: reduceMotion), value: isExpanded)
                GlassToolbarCollapseButton(
                    accessibilityIdentifier: "stats.premium.routes.expanded.close",
                    action: onClose
                )
                .opacity(isExpanded ? 1 : 0)
                .animation(TrailhoundMotion.badgeGalleryAppear(reduceMotion: reduceMotion), value: isExpanded)
                .allowsHitTesting(isExpanded)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, topInset)
                .padding(.trailing, 12)
            }
            .onGlassShell()
            .animation(TrailhoundMotion.badgeCardExpand(reduceMotion: reduceMotion), value: isExpanded)
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("stats.premium.routes.expanded")
    }

    private var windowSafeInsets: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let inset = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.safeAreaInsets {
            return inset
        }
        return scenes.flatMap(\.windows).first?.safeAreaInsets
            ?? UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
    }
}

struct FrequentRoutesPreviewCard: View {
    let aggregates: [FrequentRouteAggregate]
    var isExpanded: Bool
    var onOpen: () -> Void
    @State private var preview: UIImage?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("premium.routes.title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                    .padding(.trailing, 44)
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityHidden(true)
                }
                if let top = FrequentRouteOverlayBudget.habitCorridors(aggregates).first
                    ?? FrequentRouteOverlayBudget.topAggregates(aggregates).first {
                    Text("\(top.startDisplay) → \(top.endDisplay)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(String(format: L10n.string("premium.routes.count"), top.count))
                        .font(.caption)
                        .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                } else {
                    Text(L10n.string("premium.routes.empty"))
                        .font(.caption)
                        .foregroundStyle(StatsTextColor.tertiary(for: colorScheme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onOpen) {
                GlassToolbarSymbol(systemName: "arrow.up.left.and.arrow.down.right")
                    .frame(minWidth: 44, minHeight: 44, alignment: .topTrailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.glassPlainHit)
            .accessibilityLabel(L10n.mapFullscreen)
            .accessibilityIdentifier("stats.premium.routes")
            .allowsHitTesting(!isExpanded)
            .offset(x: StatsCardTokens.expandGlyphOffset.width, y: StatsCardTokens.expandGlyphOffset.height)
        }
        .padding(.vertical, 4)
        .task(id: aggregates.map(\.pairKey).joined()) {
            preview = await FrequentRoutesSnapshotCache.shared.snapshot(for: aggregates)
        }
    }
}
