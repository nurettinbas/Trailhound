import SwiftData
import SwiftUI

struct TravelJournalRowView: View {
    let journal: TravelJournal
    var reduceMotion: Bool = false

    @Environment(\.modelContext) private var modelContext
    @State private var mosaic: [UIImage] = []

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            mosaicView
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(journal.title)
                    .font(.headline)
                    .lineLimit(2)

                Text(L10n.journalDateRange(start: journal.startedOn, end: journal.endedOn))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    metaChip(icon: "map", text: L10n.journalTripCount(journal.tripCount))
                    metaChip(icon: "road.lanes", text: DateFormatters.formatDistance(journal.distanceMeters))
                    if journal.fuelCost > 0 {
                        metaChip(icon: "fuelpump", text: FuelCostCalculator.formatCost(journal.fuelCost))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .task(id: journal.mosaicTripIDsRaw) {
            await loadMosaic()
        }
    }

    private var accessibilitySummary: String {
        var parts = [
            journal.title,
            L10n.journalDateRange(start: journal.startedOn, end: journal.endedOn),
            L10n.journalTripCount(journal.tripCount),
            DateFormatters.formatDistance(journal.distanceMeters)
        ]
        if journal.fuelCost > 0 {
            parts.append(FuelCostCalculator.formatCost(journal.fuelCost))
        }
        return parts.joined(separator: ", ")
    }

    private var mosaicView: some View {
        HStack(spacing: -10) {
            ForEach(Array(mosaic.prefix(3).enumerated()), id: \.offset) { index, image in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                    }
                    .zIndex(Double(3 - index))
            }
            if mosaic.isEmpty {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(TrailhoundBrandColors.brandBottom.opacity(0.18))
                    .frame(width: 44, height: 44)
                    .overlay {
                        Image(systemName: "map")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(TrailhoundBrandColors.brandBottom)
                    }
            }
        }
        .frame(width: 68, height: 44, alignment: .leading)
        .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: mosaic.count)
    }

    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
    }

    @MainActor
    private func loadMosaic() async {
        var images: [UIImage] = []
        for tripID in journal.mosaicTripIDs.prefix(3) {
            if let cached = TripMapSnapshotCache.shared.cachedImage(for: tripID) {
                images.append(cached)
                continue
            }
            let descriptor = FetchDescriptor<Trip>(predicate: #Predicate { $0.id == tripID })
            guard let trip = try? modelContext.fetch(descriptor).first else { continue }
            if let image = await TripMapSnapshotCache.shared.snapshot(for: trip) {
                images.append(image)
                trip.invalidatePointCaches()
            }
        }
        mosaic = images
    }
}
