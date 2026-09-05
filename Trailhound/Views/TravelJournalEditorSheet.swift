import SwiftData
import SwiftUI

struct TravelJournalEditorDraft: Identifiable {
    var id: UUID
    var title: String
    var note: String
    var selectedTripIDs: Set<UUID>
    var existing: TravelJournal?

    static func create() -> TravelJournalEditorDraft {
        TravelJournalEditorDraft(
            id: UUID(),
            title: "",
            note: "",
            selectedTripIDs: [],
            existing: nil
        )
    }

    static func edit(_ journal: TravelJournal) -> TravelJournalEditorDraft {
        TravelJournalEditorDraft(
            id: journal.id,
            title: journal.title,
            note: journal.note ?? "",
            selectedTripIDs: Set(journal.trips.map(\.id)),
            existing: journal
        )
    }
}

struct TravelJournalEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(filter: #Predicate<Trip> { $0.endedAt != nil }, sort: \Trip.startedAt, order: .reverse)
    private var completedTrips: [Trip]

    @State var draft: TravelJournalEditorDraft

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.journalTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField(L10n.journalTitlePlaceholder, text: $draft.title)
                            .glassInputField()
                    }
                    .glassListRow()

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.journalNote)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField(L10n.journalNotePlaceholder, text: $draft.note, axis: .vertical)
                            .lineLimit(2...4)
                            .glassInputField()
                    }
                    .glassListRow()
                }

                Section(L10n.journalTrips) {
                    ForEach(selectableTrips, id: \.id) { trip in
                        Button {
                            toggle(trip.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(TripListViewModel.routeSummary(for: trip))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    Text(TripListViewModel.dateText(for: trip))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: draft.selectedTripIDs.contains(trip.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(TrailhoundBrandColors.brandBottom)
                                }
                        }
                        .buttonStyle(.plain)
                        .glassListRow()
                    }
                }
            }
            .glassListChrome()
            .navigationTitle(draft.existing == nil ? L10n.journalNew : L10n.journalTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.cancel) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        GlassToolbarSaveButton(title: L10n.journalSave)
                    }
                    .glassToolbarSaveControl()
                }
            }
        }
        .toastHost()
    }

    private var selectableTrips: [Trip] {
        completedTrips.filter { trip in
            trip.journalID == nil || trip.journalID == draft.existing?.id || draft.selectedTripIDs.contains(trip.id)
        }
    }

    private func toggle(_ id: UUID) {
        if draft.selectedTripIDs.contains(id) {
            draft.selectedTripIDs.remove(id)
        } else {
            draft.selectedTripIDs.insert(id)
        }
    }

    private func save() {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            ToastPresenter.shared.show(.journalTitleRequired)
            return
        }
        let journal: TravelJournal
        if let existing = draft.existing {
            journal = existing
            journal.title = title
            journal.note = draft.note.isEmpty ? nil : draft.note
        } else {
            journal = TravelJournal(id: draft.id, title: title, note: draft.note.isEmpty ? nil : draft.note)
            modelContext.insert(journal)
        }

        let members = completedTrips.filter { draft.selectedTripIDs.contains($0.id) }
        let currentMembers = journal.trips
        for trip in currentMembers where !draft.selectedTripIDs.contains(trip.id) {
            TravelJournalTotals.assign(trip: trip, to: nil, in: modelContext)
        }
        for trip in members {
            TravelJournalTotals.assign(trip: trip, to: journal, in: modelContext)
        }
        TravelJournalTotals.refresh(journal)
        try? modelContext.save()
        dismiss()
    }
}
