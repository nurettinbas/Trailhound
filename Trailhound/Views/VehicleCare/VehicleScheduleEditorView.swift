import SwiftData
import SwiftUI

private enum VehicleScheduleFocusedField: Hashable {
    case title
    case notes

    var previous: VehicleScheduleFocusedField? {
        self == .notes ? .title : nil
    }

    var next: VehicleScheduleFocusedField? {
        self == .title ? .notes : nil
    }
}

struct VehicleScheduleEditorView: View {
    let vehicleID: UUID
    var scheduleID: UUID?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var vehicles: [VehicleProfile]
    @Query private var schedules: [VehicleSchedule]

    @State private var draft: VehicleScheduleEditorDraft?
    @State private var isSaving = false
    @FocusState private var focusedField: VehicleScheduleFocusedField?

    private var vehicle: VehicleProfile? {
        vehicles.first { $0.id == vehicleID }
    }

    private var schedule: VehicleSchedule? {
        guard let scheduleID else { return nil }
        return schedules.first { $0.id == scheduleID }
    }

    private var activeDraft: VehicleScheduleEditorDraft {
        draft ?? {
            if let schedule { return VehicleScheduleEditorDraft(from: schedule) }
            return VehicleScheduleEditorDraft()
        }()
    }

    private var focusedFieldTitle: String {
        switch focusedField {
        case .notes:
            return L10n.string("vehicles.care.schedule.notes")
        case .title:
            return L10n.string("vehicles.care.schedule.title")
        case .none:
            return ""
        }
    }

    var body: some View {
        Form {
            Section(L10n.string("vehicles.care.schedule.kind")) {
                Picker(L10n.string("vehicles.care.schedule.kind"), selection: draftBinding(\.kind)) {
                    ForEach(VehicleScheduleKind.allCases, id: \.self) { kind in
                        Text(kind.defaultTitle).tag(kind)
                    }
                }
                .onChange(of: activeDraft.kind) { _, newKind in
                    guard draft != nil else { return }
                    if draft?.title == VehicleScheduleKind.service.defaultTitle
                        || draft?.title == VehicleScheduleKind.inspection.defaultTitle
                        || draft?.title == VehicleScheduleKind.trafficInsurance.defaultTitle
                        || draft?.title == VehicleScheduleKind.casco.defaultTitle
                        || draft?.title == VehicleScheduleKind.custom.defaultTitle
                        || draft?.title.isEmpty == true {
                        draft?.title = newKind.defaultTitle
                    }
                    draft?.intervalMonths = newKind == .inspection ? 24 : 12
                    draft?.intervalKind = newKind == .service ? .everyMonths : .everyYears
                }
                .glassRow(position: .first)

                GlassFieldLabel(title: L10n.string("vehicles.care.schedule.title")) {
                    TextField("", text: draftBinding(\.title))
                        .focused($focusedField, equals: .title)
                }
                .glassRow(position: .middle)

                Toggle(L10n.string("vehicles.care.schedule.enabled"), isOn: draftBinding(\.isEnabled))
                    .glassRow(position: .last)
            }

            Section(L10n.string("vehicles.care.schedule.due")) {
                DatePicker(
                    L10n.string("vehicles.care.schedule.next_due"),
                    selection: draftBinding(\.nextDueDate),
                    displayedComponents: .date
                )
                .glassRow(position: .first)

                Picker(L10n.string("vehicles.care.schedule.interval"), selection: draftBinding(\.intervalKind)) {
                    ForEach(VehicleScheduleIntervalKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .glassRow(position: .middle)

                if activeDraft.intervalKind == .everyMonths
                    || activeDraft.intervalKind == .everyYears
                    || activeDraft.intervalKind == .whicheverFirst {
                    Stepper(
                        value: draftBinding(\.intervalMonths),
                        in: 1...60
                    ) {
                        Text("\(activeDraft.intervalMonths) \(L10n.string("vehicles.care.schedule.months"))")
                    }
                    .glassRow(position: .middle)
                }

                if activeDraft.intervalKind == .everyKm
                    || activeDraft.intervalKind == .whicheverFirst {
                    Stepper(
                        value: draftBinding(\.intervalKm),
                        in: 1_000...50_000,
                        step: 500
                    ) {
                        Text("\(activeDraft.intervalKm) km")
                    }
                    .glassRow(position: .middle)
                }

                GlassFieldLabel(title: L10n.string("vehicles.care.schedule.notes")) {
                    TextField("", text: draftBinding(\.notes), axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focusedField, equals: .notes)
                }
                .glassRow(position: .last)
            }

            if schedule != nil {
                Section {
                    Button(L10n.delete, role: .destructive) {
                        DeleteConfirmPresenter.shared.confirm(.generic) {
                            deleteSchedule()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .destructiveTint()
                    .glassRow(position: .only)
                }
            }
        }
        .glassListChrome()
        .navigationTitle(
            scheduleID == nil
                ? L10n.string("vehicles.care.schedule.add")
                : L10n.string("vehicles.care.schedule.edit")
        )
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
                    .disabled(isSaving)
            }
        }
        .onAppear {
            if draft == nil {
                draft = schedule.map(VehicleScheduleEditorDraft.init(from:))
                    ?? VehicleScheduleEditorDraft()
            }
        }
        .deleteConfirmHost()
    }

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<VehicleScheduleEditorDraft, Value>) -> Binding<Value> {
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
            if let schedule {
                try activeDraft.apply(to: schedule, in: modelContext)
            } else {
                _ = try activeDraft.insert(for: vehicle, in: modelContext)
            }
            TripNotificationService.requestAuthorizationIfNeeded()
            ToastPresenter.shared.show(.vehicleReminderSaved)
            dismiss()
        } catch {
            AppErrorPresenter.shared.present(error.localizedDescription)
            isSaving = false
        }
    }

    private func deleteSchedule() {
        guard let schedule else { return }
        if let vehicle = schedule.vehicle {
            VehicleCareNotificationScheduler.cancelAll(for: vehicle.id)
        }
        modelContext.delete(schedule)
        try? modelContext.save()
        VehicleCareNotificationScheduler.rescheduleAll(in: modelContext)
        dismiss()
        Task { @MainActor in
            ToastPresenter.shared.show(.deleted)
        }
    }
}
