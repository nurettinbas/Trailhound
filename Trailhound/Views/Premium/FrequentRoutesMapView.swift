import MapKit
import SwiftUI
import UIKit

struct FrequentRoutesMapView: View {
    let aggregates: [FrequentRouteAggregate]
    var onClose: () -> Void
    var topInset: CGFloat = 54
    var bottomInset: CGFloat = 34
    @Environment(\.colorScheme) private var colorScheme
    @State private var selected: FrequentRouteAggregate?
    @State private var isDark = false

    var body: some View {
        ZStack(alignment: .bottom) {
            FrequentRoutesMapKitView(
                aggregates: aggregates,
                isDark: isDark || colorScheme == .dark,
                onSelect: { selected = $0 }
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Spacer(minLength: 0)
                    Picker("style", selection: $isDark) {
                        Text(L10n.string("premium.routes.map.standard")).tag(false)
                        Text(L10n.string("premium.routes.map.dark")).tag(true)
                    }
                    .pickerStyle(.segmented)
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
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                GlassNavCircleIcon(systemName: "arrow.down.right.and.arrow.up.left")
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.mapExitFullscreen)
            .accessibilityIdentifier("stats.premium.routes.expanded.close")
            .padding(.top, topInset)
            .padding(.trailing, 12)
        }
        .onGlassShell()
        .accessibilityIdentifier("stats.premium.routes.map")
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

    var body: some View {
        GeometryReader { proxy in
            let overlayGlobal = proxy.frame(in: .global)
            let frame = AchievementGalleryExpandLayout.localSurface(
                sourceGlobal: sourceGlobal,
                overlayGlobal: overlayGlobal,
                expanded: isExpanded
            )
            let radius = AchievementGalleryExpandLayout.cornerRadius(expanded: isExpanded)
            let window = windowSafeInsets
            let topInset = max(proxy.safeAreaInsets.top, window.top, 54)
            let bottomInset = max(proxy.safeAreaInsets.bottom, window.bottom, 34)
            ZStack {
                Color.clear
                    .allowsHitTesting(false)
                surface(radius: radius, topInset: topInset, bottomInset: bottomInset)
                    .frame(width: frame.width, height: frame.height, alignment: .top)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                    .position(x: frame.midX, y: frame.midY)
            }
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

    @ViewBuilder
    private func surface(radius: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        ZStack(alignment: .top) {
            FrequentRoutesPreviewCard(
                aggregates: aggregates,
                isExpanded: true,
                onOpen: {}
            )
            .padding(StatsCardTokens.contentInset)
            .glassCard(cornerRadius: radius, contentInset: 0, frozen: true, allowsNative: false)
            .opacity(isExpanded ? 0 : 1)
            .allowsHitTesting(false)
            FrequentRoutesMapView(
                aggregates: aggregates,
                onClose: onClose,
                topInset: topInset,
                bottomInset: bottomInset
            )
            .opacity(isExpanded ? 1 : 0)
            .allowsHitTesting(isExpanded)
        }
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
                if let top = aggregates.first {
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
            .buttonStyle(.plain)
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
