import SwiftData
import SwiftUI

struct VehicleExpenseEditorView: View {
    let vehicleID: UUID
    var expenseID: UUID?
    var prefillCategory: VehicleExpenseCategory = .fuel
    /// When set, save completes this schedule (tracking Mark done) instead of a plain expense insert.
    var completeScheduleID: UUID?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = AppSettings.shared
    @Query private var vehicles: [VehicleProfile]
    @Query private var expenses: [VehicleExpense]
    @Query private var schedules: [VehicleSchedule]

    @State private var draft: VehicleExpenseEditorDraft?
    @State private var isSaving = false

    private var vehicle: VehicleProfile? {
        vehicles.first { $0.id == vehicleID }
    }

    private var expense: VehicleExpense? {
        guard let expenseID else { return nil }
        return expenses.first { $0.id == expenseID }
    }

    private var completeSchedule: VehicleSchedule? {
        guard let completeScheduleID else { return nil }
        return schedules.first { $0.id == completeScheduleID }
    }

    private var isCompletingSchedule: Bool { completeSchedule != nil }

    private var activeDraft: VehicleExpenseEditorDraft {
        draft ?? VehicleExpenseEditorDraft(category: prefillCategory)
    }

    var body: some View {
        Form {
            Section(
                isCompletingSchedule
                    ? L10n.string("vehicles.care.complete")
                    : L10n.string("vehicles.care.expense.section")
            ) {
                if isCompletingSchedule, let schedule = completeSchedule {
                    LabeledContent(L10n.string("vehicles.care.schedule.title")) {
                        Text(schedule.title)
                            .foregroundStyle(.secondary)
                    }
                    .glassRow(position: .first)
                } else {
                    Picker(L10n.string("vehicles.care.expense.category"), selection: draftBinding(\.category)) {
                        ForEach(VehicleExpenseCategory.allCases, id: \.self) { category in
                            Label(category.displayName, systemImage: category.systemImage)
                                .tag(category)
                        }
                    }
                    .glassRow(position: .first)
                }

                GlassFieldLabel(title: L10n.string("vehicles.care.expense.amount")) {
                    HStack {
                        TextField("", text: draftBinding(\.amountText))
                            .keyboardType(.decimalPad)
                        Text(settings.fuelCurrency.symbol)
                            .foregroundStyle(.secondary)
                    }
                }
                .glassRow(position: .middle)

                DatePicker(
                    L10n.string("vehicles.care.expense.date"),
                    selection: draftBinding(\.occurredAt),
                    displayedComponents: .date
                )
                .glassRow(position: .middle)

                GlassFieldLabel(title: L10n.string("vehicles.care.expense.note")) {
                    TextField("", text: draftBinding(\.note), axis: .vertical)
                        .lineLimit(2...4)
                }
                .glassRow(position: .last)
            }

            if expense != nil {
                Section {
                    Button(L10n.delete, role: .destructive) {
                        deleteExpense()
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .destructiveTint()
                    .glassRow(position: .only)
                }
            }
        }
        .glassListChrome()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.pairingTabSave) { save() }
                    .disabled(isSaving || activeDraft.amount == nil)
            }
        }
        .onAppear {
            if draft == nil {
                if let expense {
                    draft = VehicleExpenseEditorDraft(from: expense)
                } else if let schedule = completeSchedule {
                    draft = VehicleExpenseEditorDraft(category: .suggested(for: schedule.kind))
                } else {
                    draft = VehicleExpenseEditorDraft(category: prefillCategory)
                }
            }
        }
    }

    private var navigationTitle: String {
        if isCompletingSchedule {
            return L10n.string("vehicles.care.complete")
        }
        return expenseID == nil
            ? L10n.string("vehicles.care.expense.add")
            : L10n.string("vehicles.care.expense.edit")
    }

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<VehicleExpenseEditorDraft, Value>) -> Binding<Value> {
        Binding(
            get: { activeDraft[keyPath: keyPath] },
            set: { newValue in
                var next = activeDraft
                next[keyPath: keyPath] = newValue
                draft = next
            }
        )
    }

    private func save() {
        guard let vehicle else { return }
        isSaving = true
        do {
            if let expense {
                try activeDraft.apply(to: expense, in: modelContext)
            } else if let schedule = completeSchedule, let amount = activeDraft.amount {
                _ = try VehicleScheduleCompletionService.complete(
                    schedule: schedule,
                    amount: amount,
                    occurredAt: activeDraft.occurredAt,
                    note: activeDraft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? nil
                        : activeDraft.note.trimmingCharacters(in: .whitespacesAndNewlines),
                    in: modelContext
                )
            } else {
                _ = try activeDraft.insert(for: vehicle, in: modelContext)
            }
            ToastPresenter.shared.show(.vehicleExpenseSaved)
            dismiss()
        } catch {
            AppErrorPresenter.shared.present(
                error as? VehicleCareError == .invalidAmount
                    ? L10n.string("vehicles.care.expense.invalid_amount")
                    : error.localizedDescription
            )
            isSaving = false
        }
    }

    private func deleteExpense() {
        guard let expense else { return }
        modelContext.delete(expense)
        try? modelContext.save()
        dismiss()
        Task { @MainActor in
            ToastPresenter.shared.show(.deleted)
        }
    }
}
