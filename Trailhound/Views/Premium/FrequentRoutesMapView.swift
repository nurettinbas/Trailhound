import MapKit
import SwiftUI

struct FrequentRoutesMapView: View {
    let aggregates: [FrequentRouteAggregate]
    @Environment(\.dismiss) private var dismiss
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
                    Button(L10n.string("action.close")) { dismiss() }
                        .font(.subheadline.weight(.semibold))
                    Spacer()
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
            .glassCard(cornerRadius: 20)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .accessibilityIdentifier("stats.premium.routes.map")
    }
}

struct FrequentRoutesPreviewCard: View {
    let aggregates: [FrequentRouteAggregate]
    var onOpen: () -> Void
    @State private var preview: UIImage?

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.string("premium.routes.title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
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
                        .foregroundStyle(.secondary)
                } else {
                    Text(L10n.string("premium.routes.empty"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .task(id: aggregates.map(\.pairKey).joined()) {
            preview = await FrequentRoutesSnapshotCache.shared.snapshot(for: aggregates)
        }
        .accessibilityIdentifier("stats.premium.routes")
    }
}
