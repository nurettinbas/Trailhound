import SwiftData
import SwiftUI

struct TravelJournalEditPanel: View {
    @Bindable var journal: TravelJournal
    let trips: [Trip]
    let selectedTripID: UUID?
    let places: [SavedPlace]
    let restHeight: CGFloat
    let reduceMotion: Bool
    var onSelectTrip: (UUID) -> Void
    var onOpenTrip: (Trip) -> Void
    var onRemoveTrip: (Trip) -> Void
    var onEdit: () -> Void

    @Bindable private var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(journal.title)
                                .font(.headline)
                            Text(L10n.journalDateRange(start: journal.startedOn, end: journal.endedOn))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(L10n.string("journal.edit"), action: onEdit)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TrailhoundBrandColors.brandBottom)
                    }

                    if let note = journal.note, !note.isEmpty {
                        Text(note)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        metric(L10n.journalTripCount(journal.tripCount), icon: "map")
                        metric(DateFormatters.formatDistance(journal.distanceMeters), icon: "road.lanes")
                        if journal.fuelCost > 0 {
                            metric(FuelCostCalculator.formatCost(journal.fuelCost), icon: "fuelpump")
                        }
                    }

                    ForEach(dayGroups, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(DateFormatters.tripDateOnly.string(from: group.day))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(group.trips, id: \.id) { trip in
                                Button {
                                    onSelectTrip(trip.id)
                                } label: {
                                    TripRowView(
                                        trip: trip,
                                        places: places,
                                        privacyRadius: settings.privacyRadiusMeters
                                    )
                                    .padding(8)
                                    .background {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(trip.id == selectedTripID
                                                  ? TrailhoundBrandColors.brandBottom.opacity(0.16)
                                                  : Color.clear)
                                    }
                                }
                                .buttonStyle(.plain)
                                .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: selectedTripID)
                                .contextMenu {
                                    Button { onOpenTrip(trip) } label: {
                                        Text(L10n.string("journal.open.trip"))
                                    }
                                    Button(role: .destructive) {
                                        onRemoveTrip(trip)
                                    } label: {
                                        Text(L10n.journalRemove)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, GlassTokens.listContentHorizontalInset)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.hidden)
            .glassCard(cornerRadius: 18, contentInset: 0)
            .frame(height: restHeight)
    }

    private var dayGroups: [(day: Date, trips: [Trip])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: trips) { calendar.startOfDay(for: $0.startedAt) }
        return grouped.keys.sorted(by: >).map { day in
            (day, (grouped[day] ?? []).sorted { $0.startedAt > $1.startedAt })
        }
    }

    private func metric(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.semibold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(TrailhoundBrandColors.brandBottom)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            Capsule().fill(TrailhoundBrandColors.brandBottom.opacity(0.12))
        }
    }
}
