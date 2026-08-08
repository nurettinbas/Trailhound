import SwiftData
import SwiftUI

/// Unified vehicle screen: profile → tracking/reminders → expenses.
/// Charts live only on Stats — not here.
struct VehicleDetailView: View {
    let vehicleID: UUID

    @Environment(\.modelContext) private var modelContext
    @Bindable private var settings = AppSettings.shared
    @Query private var vehicles: [VehicleProfile]
    @Query private var allSchedules: [VehicleSchedule]
    @Query(sort: \VehicleExpense.occurredAt, order: .reverse) private var allExpenses: [VehicleExpense]

    @State private var showAddExpense = false
    @State private var showAddSchedule = false
    @State private var editingScheduleID: UUID?
    @State private var editingExpenseID: UUID?
    @State private var completingScheduleID: UUID?
    @State private var hasUnsavedVehicleEdits = false
    @State private var vehicleSaveTrigger = 0
    @State private var vehicleSaveDisabled = false

    private var vehicle: VehicleProfile? {
        vehicles.first { $0.id == vehicleID }
    }

    private var schedules: [VehicleSchedule] {
        allSchedules
            .filter { $0.vehicle?.id == vehicleID }
            .sorted { lhs, rhs in
                let l = lhs.nextDueDate ?? .distantFuture
                let r = rhs.nextDueDate ?? .distantFuture
                return l < r
            }
    }

    private var expenses: [VehicleExpense] {
        Array(allExpenses.filter { $0.vehicle?.id == vehicleID }.prefix(100))
    }

    var body: some View {
        Group {
            if let vehicle {
                detailList(vehicle: vehicle)
            } else {
                ContentUnavailableView(L10n.pairingTabVehicleNotFound, systemImage: "car")
            }
        }
        .navigationTitle(vehicle?.name ?? L10n.string("vehicles.care.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    vehicleSaveTrigger += 1
                } label: {
                    GlassToolbarSaveButton(title: L10n.pairingTabSave)
                }
                .buttonStyle(.plain)
                .disabled(vehicleSaveDisabled)
                .opacity(vehicleSaveDisabled ? 0.45 : 1)
            }
        }
        .vehicleEditorUnsavedChangesGuard($hasUnsavedVehicleEdits)
        .sheet(isPresented: $showAddExpense) {
            NavigationStack {
                VehicleExpenseEditorView(vehicleID: vehicleID)
            }
        }
        .sheet(isPresented: $showAddSchedule) {
            NavigationStack {
                VehicleScheduleEditorView(vehicleID: vehicleID)
            }
        }
        .sheet(isPresented: Binding(
            get: { editingScheduleID != nil },
            set: { if !$0 { editingScheduleID = nil } }
        )) {
            if let editingScheduleID {
                NavigationStack {
                    VehicleScheduleEditorView(vehicleID: vehicleID, scheduleID: editingScheduleID)
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { completingScheduleID != nil },
            set: { if !$0 { completingScheduleID = nil } }
        )) {
            if let completingScheduleID {
                NavigationStack {
                    VehicleExpenseEditorView(
                        vehicleID: vehicleID,
                        completeScheduleID: completingScheduleID
                    )
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { editingExpenseID != nil },
            set: { if !$0 { editingExpenseID = nil } }
        )) {
            if let editingExpenseID {
                NavigationStack {
                    VehicleExpenseEditorView(vehicleID: vehicleID, expenseID: editingExpenseID)
                }
            }
        }
    }

    @ViewBuilder
    private func detailList(vehicle: VehicleProfile) -> some View {
        List {
            PairingVehicleEditorForm(
                vehicle: vehicle,
                vehicles: vehicles,
                presentation: .embeddedInList,
                unsavedChanges: $hasUnsavedVehicleEdits,
                saveTrigger: $vehicleSaveTrigger,
                saveDisabled: $vehicleSaveDisabled
            )

            Section {
                if schedules.isEmpty {
                    Text(L10n.string("vehicles.care.schedules.empty"))
                        .foregroundStyle(.secondary)
                        .glassRow(position: .first)
                } else {
                    ForEach(Array(schedules.enumerated()), id: \.element.id) { index, schedule in
                        trackingCardRow(schedule)
                            .listRowInsets(cardRowInsets(index: index))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteSchedule(schedule)
                                } label: {
                                    Label(L10n.delete, systemImage: "trash")
                                }
                                .destructiveTint()
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    completingScheduleID = schedule.id
                                } label: {
                                    Label(L10n.string("vehicles.care.complete"), systemImage: "checkmark.circle")
                                }
                                .tint(TrailhoundBrandColors.brandBottom)
                            }
                    }
                }

                Button {
                    showAddSchedule = true
                } label: {
                    Label(L10n.string("vehicles.care.tracking.add"), systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                }
                .tint(TrailhoundBrandColors.brandBottom)
                .glassRow(position: .last)
            } header: {
                Text(L10n.string("vehicles.care.tracking.section"))
            } footer: {
                Text(L10n.string("vehicles.care.tracking.footer"))
                    .font(.caption)
            }

            Section {
                if expenses.isEmpty {
                    Text(L10n.string("vehicles.care.expenses.empty"))
                        .foregroundStyle(.secondary)
                        .glassRow(position: .first)
                } else {
                    ForEach(Array(expenses.enumerated()), id: \.element.id) { index, expense in
                        expenseCardRow(expense)
                            .listRowInsets(cardRowInsets(index: index))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteExpense(expense)
                                } label: {
                                    Label(L10n.delete, systemImage: "trash")
                                }
                                .destructiveTint()
                            }
                    }
                }

                Button {
                    showAddExpense = true
                } label: {
                    Label(L10n.string("vehicles.care.expense.add"), systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                }
                .tint(TrailhoundBrandColors.brandBottom)
                .glassRow(position: .last)
            } header: {
                Text(L10n.string("vehicles.care.expenses.section"))
            } footer: {
                Text(L10n.string("vehicles.care.expenses.footer"))
                    .font(.caption)
            }
        }
        .listStyle(.insetGrouped)
        .glassListChrome()
        .keyboardDoneToolbar()
    }

    private func cardRowInsets(index: Int) -> EdgeInsets {
        EdgeInsets(
            top: index == 0 ? 4 : 2,
            leading: 0,
            bottom: 2,
            trailing: 0
        )
    }

    /// Matches Araçlar → vehicle card: glass card, leading icon tile, title, due date trailing.
    private func trackingCardRow(_ schedule: VehicleSchedule) -> some View {
        let state = VehicleCareDueCalculator.dueState(nextDueDate: schedule.nextDueDate)
        let subtitle = VehicleCareDueCalculator.shortSubtitle(for: state)
            ?? L10n.string("vehicles.care.due.none")

        return PairingCardContainer {
            Button {
                editingScheduleID = schedule.id
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: schedule.kind.systemImage)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(TrailhoundBrandColors.brandBottom)
                        )

                    Text(schedule.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(state.isOverdue ? Color.red : Color.secondary)
                        .lineLimit(1)
                        .multilineTextAlignment(.trailing)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// Matches tracking cards: glass card, leading icon tile, title, subtitle, chevron.
    private func expenseCardRow(_ expense: VehicleExpense) -> some View {
        let date = DateFormatters.chartDay.string(from: expense.occurredAt)
        let note = expense.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNote = !(note?.isEmpty ?? true)

        return PairingCardContainer {
            Button {
                editingExpenseID = expense.id
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: expense.category.systemImage)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(TrailhoundBrandColors.brandBottom)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(expense.category.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("·")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text(date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        if hasNote, let note {
                            Text(note)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(formatAmount(expense.amount))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func formatAmount(_ amount: Double) -> String {
        String(format: "%.2f %@", amount, settings.fuelCurrency.symbol)
    }

    private func deleteSchedule(_ schedule: VehicleSchedule) {
        if let vehicle = schedule.vehicle {
            VehicleCareNotificationScheduler.cancelAll(for: vehicle.id)
        }
        modelContext.delete(schedule)
        try? modelContext.save()
        VehicleCareNotificationScheduler.rescheduleAll(in: modelContext)
        ToastPresenter.shared.show(.deleted)
    }

    private func deleteExpense(_ expense: VehicleExpense) {
        modelContext.delete(expense)
        try? modelContext.save()
        ToastPresenter.shared.show(.deleted)
    }
}

/// Compatibility alias used by older call sites / docs.
typealias VehicleCareDetailView = VehicleDetailView
