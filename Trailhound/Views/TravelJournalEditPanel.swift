import SwiftData
import SwiftUI

struct TravelJournalEditPanel: View {
    @Bindable var journal: TravelJournal
    let trips: [Trip]
    let selectedTripID: UUID?
    let places: [SavedPlace]
    let restHeight: CGFloat
    let isExpanded: Bool
    let reduceMotion: Bool
    var onSelectTrip: (UUID) -> Void
    var onOpenTrip: (Trip) -> Void
    var onRemoveTrip: (Trip) -> Void
    var onEdit: () -> Void
    var onToggleExpanded: () -> Void
    var onGrabberDragChanged: (CGFloat) -> Void
    var onGrabberDragEnded: (CGFloat) -> Void

    @Bindable private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            panelGrabber

            List {
                Section {
                    panelHeader
                        .listRowInsets(
                            EdgeInsets(
                                top: 4,
                                leading: GlassTokens.listContentHorizontalInset,
                                bottom: 8,
                                trailing: GlassTokens.listContentHorizontalInset
                            )
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }

                if isExpanded {
                    ForEach(dayGroups, id: \.day) { group in
                        Section {
                            ForEach(group.trips, id: \.id) { trip in
                                tripRow(trip)
                            }
                        } header: {
                            Text(DateFormatters.tripDateOnly.string(from: group.day))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDisabled(!isExpanded)
            .contentMargins(.bottom, TripDetailKeyboardLayout.restingScrollBottomInset, for: .scrollContent)
        }
        .frame(height: restHeight)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : TrailhoundMotion.sheetRise, value: isExpanded)
    }

    private var panelGrabber: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 5)
            Image(systemName: "chevron.compact.up")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .padding(.top, 4)
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    guard abs(value.translation.height) >= 8 else { return }
                    onGrabberDragChanged(value.translation.height)
                }
                .onEnded { value in
                    if abs(value.translation.height) < 8 {
                        onToggleExpanded()
                    } else {
                        onGrabberDragEnded(value.predictedEndTranslation.height)
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isExpanded
            ? L10n.string("journal.map.collapse")
            : L10n.journalTrips)
    }

    private var panelHeader: some View {
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
                    .lineLimit(isExpanded ? 4 : 2)
            }

            HStack(spacing: 8) {
                Button(action: onToggleExpanded) {
                    metric(L10n.journalTripCount(journal.tripCount), icon: "map")
                }
                .buttonStyle(.plain)
                .accessibilityHint(isExpanded
                    ? L10n.string("journal.map.collapse")
                    : L10n.string("journal.map.expand"))

                metric(DateFormatters.formatDistance(journal.distanceMeters), icon: "road.lanes")
                if journal.fuelCost > 0 {
                    metric(FuelCostCalculator.formatCost(journal.fuelCost), icon: "fuelpump")
                }
            }
        }
    }

    private func tripRow(_ trip: Trip) -> some View {
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
        .listRowInsets(
            EdgeInsets(
                top: 3,
                leading: GlassTokens.listContentHorizontalInset,
                bottom: 3,
                trailing: GlassTokens.listContentHorizontalInset
            )
        )
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onRemoveTrip(trip)
            } label: {
                Label(L10n.journalRemove, systemImage: "trash")
            }
            .destructiveTint()
        }
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
