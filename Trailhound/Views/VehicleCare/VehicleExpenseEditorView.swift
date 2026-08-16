import SwiftData
import SwiftUI

private enum VehicleExpenseFocusedField: Hashable {
    case amount
    case note

    var previous: VehicleExpenseFocusedField? {
        self == .note ? .amount : nil
    }

    var next: VehicleExpenseFocusedField? {
        self == .amount ? .note : nil
    }
}

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
    @State private var showDeletePlanConfirm = false
    @FocusState private var focusedField: VehicleExpenseFocusedField?

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

    private var focusedFieldTitle: String {
        switch focusedField {
        case .note:
            return L10n.string("vehicles.care.expense.note")
        case .amount:
            return amountFieldTitle
        case .none:
            return ""
        }
    }

    var body: some View {
        Form {
            Section {
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

                GlassFieldLabel(title: amountFieldTitle) {
                    HStack {
                        TextField("", text: draftBinding(\.amountText))
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .amount)
                        Text(settings.fuelCurrency.symbol)
                            .foregroundStyle(.secondary)
                    }
                }
                .glassRow(position: .middle)

                Stepper(
                    value: draftBinding(\.installmentCount),
                    in: VehicleExpenseInstallmentPlan.minCount...VehicleExpenseInstallmentPlan.maxCount
                ) {
                    Text(installmentStepperLabel)
                }
                .glassRow(position: .middle)

                if activeDraft.isInstallmentPlan, let preview = installmentPreviewText {
                    Text(preview)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .glassRow(position: .middle)
                }

                DatePicker(
                    dateFieldTitle,
                    selection: draftBinding(\.occurredAt),
                    displayedComponents: .date
                )
                .glassRow(position: .middle)

                GlassFieldLabel(title: L10n.string("vehicles.care.expense.note")) {
                    TextField("", text: draftBinding(\.note), axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focusedField, equals: .note)
                }
                .glassRow(position: .last)
            } header: {
                Text(
                    isCompletingSchedule
                        ? L10n.string("vehicles.care.complete")
                        : L10n.string("vehicles.care.expense.section")
                )
            } footer: {
                if activeDraft.isInstallmentPlan {
                    Text(
                        expense?.isInstallment == true
                            ? L10n.string("vehicles.care.expense.installments.edit_footer")
                            : L10n.string("vehicles.care.expense.installments.preview_footer")
                    )
                }
            }

            if expense != nil {
                Section {
                    if expense?.isInstallment == true {
                        Button(L10n.string("vehicles.care.expense.delete_this"), role: .destructive) {
                            deleteThisInstallment()
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .destructiveTint()
                        .glassRow(position: .first)

                        Button(deletePlanLabel, role: .destructive) {
                            showDeletePlanConfirm = true
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .destructiveTint()
                        .glassRow(position: .last)
                    } else {
                        Button(L10n.delete, role: .destructive) {
                            deleteExpense()
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .destructiveTint()
                        .glassRow(position: .only)
                    }
                }
            }
        }
        .glassListChrome()
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .dismissKeyboardOnTap(focus: $focusedField)
        .dismissKeyboardOnScroll()
        .fieldKeyboardAccessory(
            title: focusedFieldTitle,
            focusID: focusedField.map { AnyHashable($0) },
            onDone: {
                focusedField = nil
                KeyboardDismiss.dismiss()
            }
        )
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(L10n.cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L10n.pairingTabSave) { save() }
                    .disabled(isSaving || activeDraft.amount == nil)
            }
        }
        .confirmationDialog(
            L10n.string("vehicles.care.expense.delete_plan_title"),
            isPresented: $showDeletePlanConfirm,
            titleVisibility: .visible
        ) {
            Button(deletePlanLabel, role: .destructive) {
                deletePlan()
            }
            Button(L10n.cancel, role: .cancel) {}
        }
        .onAppear {
            if draft == nil {
                if let expense {
                    let siblings = VehicleExpenseInstallmentService.siblings(of: expense, in: modelContext)
                    draft = VehicleExpenseEditorDraft(from: expense, siblings: siblings)
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

    private var amountFieldTitle: String {
        activeDraft.isInstallmentPlan
            ? L10n.string("vehicles.care.expense.total")
            : L10n.string("vehicles.care.expense.amount")
    }

    private var dateFieldTitle: String {
        activeDraft.isInstallmentPlan
            ? L10n.string("vehicles.care.expense.first_payment")
            : L10n.string("vehicles.care.expense.date")
    }

    private var installmentStepperLabel: String {
        if activeDraft.installmentCount <= 1 {
            return L10n.string("vehicles.care.expense.installments.one")
        }
        return String(
            format: L10n.string("vehicles.care.expense.installments.count"),
            activeDraft.installmentCount
        )
    }

    private var deletePlanLabel: String {
        let count = expense?.installmentCount ?? activeDraft.installmentCount
        return String(format: L10n.string("vehicles.care.expense.delete_plan"), count)
    }

    private var installmentPreviewText: String? {
        guard let amount = activeDraft.amount, activeDraft.installmentCount > 1 else { return nil }
        let slices = VehicleExpenseInstallmentPlan.slices(
            total: amount,
            count: activeDraft.installmentCount,
            start: activeDraft.occurredAt
        )
        guard let first = slices.first, let last = slices.last else { return nil }
        let monthly = String(format: "%.2f %@", first.amount, settings.fuelCurrency.symbol)
        let start = DateFormatters.monthYear.string(from: first.dueDate)
        let end = DateFormatters.monthYear.string(from: last.dueDate)
        return String(
            format: L10n.string("vehicles.care.expense.installments.preview"),
            slices.count,
            monthly,
            start,
            end
        )
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
                    installmentCount: activeDraft.installmentCount,
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
        VehicleExpenseInstallmentService.deleteOne(expense, in: modelContext)
        dismiss()
        Task { @MainActor in
            ToastPresenter.shared.show(.deleted)
        }
    }

    private func deleteThisInstallment() {
        deleteExpense()
    }

    private func deletePlan() {
        guard let expense else { return }
        VehicleExpenseInstallmentService.deleteGroup(of: expense, in: modelContext)
        dismiss()
        Task { @MainActor in
            ToastPresenter.shared.show(.deleted)
        }
    }
}
