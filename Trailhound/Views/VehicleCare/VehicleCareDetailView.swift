import SwiftData
import SwiftUI

/// Unified vehicle screen: profile → tracking/reminders → expenses.
/// Charts live only on Stats — not here.
struct VehicleDetailView: View {
    let vehicleID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Bindable private var settings = AppSettings.shared
    @Query private var vehicles: [VehicleProfile]
    @Query private var allSchedules: [VehicleSchedule]
    @Query(sort: \VehicleExpense.occurredAt, order: .reverse) private var allExpenses: [VehicleExpense]

    @State private var showAddExpense = false
    @State private var showAddSchedule = false
    @State private var editingScheduleID: UUID?
    @State private var editingExpenseID: UUID?
    @State private var completingScheduleID: UUID?
    /// Add and edit forms fill the trailing half on the widest book.
    @State private var trailingEditor: TrailingCareEditor?
    @State private var hasUnsavedVehicleEdits = false
    @State private var vehicleSaveTrigger = 0
    @State private var vehicleSaveDisabled = false
    @State private var photoSheet: VehiclePhotoSheetRoute?
    @State private var pendingFramingImage: UIImage?
    @FocusState private var vehicleEditorFocus: PairingVehicleFocusedField?
    @State private var vehicleKeyboardNav = VehicleEditorKeyboardNav()
    @Environment(\.trailhoundLayout) private var layout

    /// Widest open book only. The profile stays on the leading half.
    /// Tracking and expenses scroll together on the trailing half.
    /// Phone, upright fold, and iPad stay one list.
    private var splitsAfterTracking: Bool {
        guard layout.isLandscape, layout.layoutClass != .pad else { return false }
        if layout.layoutClass == .duoOpen { return true }
        return layout.size.width >= TrailhoundLayoutResolver.openFoldSpan
    }

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

    private var startOfTomorrow: Date {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
    }

    /// Due or already paid — future installment slices stay in Upcoming until their date.
    private var expenses: [VehicleExpense] {
        Array(
            allExpenses
                .filter { $0.vehicle?.id == vehicleID && $0.occurredAt < startOfTomorrow }
                .prefix(100)
        )
    }

    private var upcomingInstallments: [VehicleExpense] {
        allExpenses
            .filter { $0.vehicle?.id == vehicleID && $0.occurredAt >= startOfTomorrow && $0.isInstallment }
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    var body: some View {
        Group {
            if let vehicle {
                detailList(vehicle: vehicle)
            } else {
                ContentUnavailableView(L10n.pairingTabVehicleNotFound, systemImage: "car")
                    .onGlassShell()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        AtmosphericBackground(style: .full)
                            .ignoresSafeArea()
                    }
            }
        }
        .glassNavigationChrome()
        .navigationTitle(vehicle?.name ?? L10n.string("vehicles.care.detail.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            GlassToolbarNavTitleItem(
                title: vehicle?.name ?? L10n.string("vehicles.care.detail.title")
            )
        }
        .vehicleEditorUnsavedChangesGuard($hasUnsavedVehicleEdits)
        .vehiclePhotoFlowSheets(
            photoSheet: $photoSheet,
            pendingFramingImage: $pendingFramingImage
        )
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
        if splitsAfterTracking {
            TrailhoundPaneSplit {
                careList(showsAtmosphere: false, widePane: true) {
                    profileBlock(vehicle: vehicle)
                }
                .vehicleFieldKeyboard(
                    focusedField: $vehicleEditorFocus,
                    consumptionLabel: vehicleKeyboardNav.consumptionLabel
                )
            } focus: {
                if let trailingEditor {
                    trailingEditorForm(trailingEditor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    careList(showsAtmosphere: false, widePane: true) {
                        trackingBlock
                        expensesBlock
                    }
                }
            }
        } else {
            careList(showsAtmosphere: true, widePane: false) {
                profileBlock(vehicle: vehicle)
                trackingBlock
                expensesBlock
            }
            .vehicleFieldKeyboard(
                focusedField: $vehicleEditorFocus,
                consumptionLabel: vehicleKeyboardNav.consumptionLabel
            )
        }
    }

    private func openAddExpense() {
        if splitsAfterTracking {
            trailingEditor = .addExpense
        } else {
            showAddExpense = true
        }
    }

    private func openAddSchedule() {
        if splitsAfterTracking {
            trailingEditor = .addSchedule
        } else {
            showAddSchedule = true
        }
    }

    private func openEditExpense(_ id: UUID) {
        if splitsAfterTracking {
            trailingEditor = .editExpense(id)
        } else {
            editingExpenseID = id
        }
    }

    private func openEditSchedule(_ id: UUID) {
        if splitsAfterTracking {
            trailingEditor = .editSchedule(id)
        } else {
            editingScheduleID = id
        }
    }

    private func openCompleteSchedule(_ id: UUID) {
        if splitsAfterTracking {
            trailingEditor = .completeSchedule(id)
        } else {
            completingScheduleID = id
        }
    }

    private func closeTrailingEditor() {
        trailingEditor = nil
    }

    @ViewBuilder
    private func trailingEditorForm(_ editor: TrailingCareEditor) -> some View {
        switch editor {
        case .addExpense:
            VehicleExpenseEditorView(vehicleID: vehicleID, onFinish: closeTrailingEditor)
        case .editExpense(let id):
            VehicleExpenseEditorView(vehicleID: vehicleID, expenseID: id, onFinish: closeTrailingEditor)
        case .completeSchedule(let id):
            VehicleExpenseEditorView(vehicleID: vehicleID, completeScheduleID: id, onFinish: closeTrailingEditor)
        case .addSchedule:
            VehicleScheduleEditorView(vehicleID: vehicleID, onFinish: closeTrailingEditor)
        case .editSchedule(let id):
            VehicleScheduleEditorView(vehicleID: vehicleID, scheduleID: id, onFinish: closeTrailingEditor)
        }
    }

    private func careList<Content: View>(
        showsAtmosphere: Bool,
        widePane: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        List {
            content()
        }
        .listStyle(.insetGrouped)
        .glassListChrome(showsAtmosphere: showsAtmosphere)
        .modifier(VehicleCarePaneListWidth(enabled: widePane))
    }

    @ViewBuilder
    private func profileBlock(vehicle: VehicleProfile) -> some View {
        PairingVehicleEditorForm(
            vehicle: vehicle,
            vehicles: vehicles,
            presentation: .embeddedInList,
            focusedField: $vehicleEditorFocus,
            keyboardNav: $vehicleKeyboardNav,
            unsavedChanges: $hasUnsavedVehicleEdits,
            saveTrigger: $vehicleSaveTrigger,
            saveDisabled: $vehicleSaveDisabled,
            photoSheet: $photoSheet,
            pendingFramingImage: $pendingFramingImage
        )
    }

    @ViewBuilder
    private var trackingBlock: some View {
        Section {
                if schedules.isEmpty {
                    Text(L10n.string("vehicles.care.schedules.empty"))
                        .foregroundStyle(careRowSecondaryInk)
                        .glassRow(position: .only)
                } else {
                    ForEach(Array(schedules.enumerated()), id: \.element.id) { index, schedule in
                        trackingCardRow(schedule)
                            .glassRow(position: GlassRowPosition.index(index, in: schedules.count))
                            .confirmingDeleteSwipe {
                                deleteSchedule(schedule)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    openCompleteSchedule(schedule.id)
                                } label: {
                                    Label(L10n.string("vehicles.care.complete"), systemImage: "checkmark.circle")
                                }
                                .tint(shellPalette.tintColor(for: colorScheme))
                            }
                    }
                }
            } header: {
                GlassSectionHeaderAction(
                    title: L10n.string("vehicles.care.tracking.section"),
                    actionTitle: L10n.string("vehicles.care.tracking.add"),
                    action: { openAddSchedule() }
                )
            } footer: {
                Text(L10n.string("vehicles.care.tracking.footer"))
                    .font(.caption)
            }
    }

    @ViewBuilder
    private var expensesBlock: some View {
        Section {
                if expenses.isEmpty {
                    Text(L10n.string("vehicles.care.expenses.empty"))
                        .foregroundStyle(careRowSecondaryInk)
                        .glassRow(position: .only)
                } else {
                    ForEach(Array(expenses.enumerated()), id: \.element.id) { index, expense in
                        expenseCardRow(expense)
                            .glassRow(position: GlassRowPosition.index(index, in: expenses.count))
                            .confirmingDeleteSwipe {
                                deleteExpense(expense)
                            }
                    }
                }
            } header: {
                GlassSectionHeaderAction(
                    title: L10n.string("vehicles.care.expenses.section"),
                    actionTitle: L10n.string("vehicles.care.expense.add"),
                    action: { openAddExpense() }
                )
            } footer: {
                Text(L10n.string("vehicles.care.expenses.footer"))
                    .font(.caption)
            }

            if !upcomingInstallments.isEmpty {
                Section {
                    ForEach(Array(upcomingInstallments.enumerated()), id: \.element.id) { index, expense in
                        expenseCardRow(expense)
                            .glassRow(position: GlassRowPosition.index(index, in: upcomingInstallments.count))
                            .confirmingDeleteSwipe {
                                deleteExpense(expense)
                            }
                    }
                } header: {
                    Text(L10n.string("vehicles.care.expenses.upcoming"))
                } footer: {
                    Text(L10n.string("vehicles.care.expenses.upcoming.footer"))
                        .font(.caption)
                }
            }
    }

    private var careRowSecondaryInk: Color {
        GlassText.secondary(for: colorScheme, palette: shellPalette)
    }

    /// Matches Vehicles tab vehicle card: grouped plate, leading icon tile, title, due date trailing.
    private func trackingCardRow(_ schedule: VehicleSchedule) -> some View {
        CareTrackingCardRow(
            schedule: schedule,
            onEdit: { openEditSchedule(schedule.id) },
            onComplete: { openCompleteSchedule(schedule.id) }
        )
    }

    /// Matches tracking cards: glass card, leading icon tile, title, subtitle, chevron.
    private func expenseCardRow(_ expense: VehicleExpense) -> some View {
        let date = DateFormatters.chartDay.string(from: expense.occurredAt)
        let note = expense.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasNote = !(note?.isEmpty ?? true)

        return Button {
                openEditExpense(expense.id)
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: expense.category.systemImage)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(shellPalette.tintColor(for: colorScheme))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(expense.category.displayName)
                                .font(.subheadline.weight(.semibold))
                                .glassPrimaryInk()
                                .lineLimit(1)
                            Text("·")
                                .font(.caption2)
                                .glassTertiaryInk()
                            Text(date)
                                .font(.caption)
                                .glassSecondaryInk()
                                .lineLimit(1)
                            if let badge = installmentBadge(for: expense) {
                                Text("·")
                                    .font(.caption2)
                                    .glassTertiaryInk()
                                Text(badge)
                                    .font(.caption2.weight(.semibold))
                                    .glassAccentForeground()
                                    .lineLimit(1)
                            }
                        }

                        if hasNote, let note {
                            Text(note)
                                .font(.caption2)
                                .glassTertiaryInk()
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(
                        FuelCostCalculator.formatCost(
                            expense.amount,
                            currencyCode: settings.fuelCurrency.rawValue,
                            locale: Locale(identifier: "tr_TR")
                        )
                    )
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .glassPrimaryInk()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .glassDisclosureInk()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.glassPlainHit)
    }

    private func installmentBadge(for expense: VehicleExpense) -> String? {
        guard expense.isInstallment,
              let index = expense.installmentIndex,
              let count = expense.installmentCount
        else { return nil }
        return String(format: L10n.string("vehicles.care.expense.installments.badge"), index, count)
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

/// Reminder row with urgency-tinted icon tile + due chip + visible Done.
private struct CareTrackingCardRow: View {
    let schedule: VehicleSchedule
    let onEdit: () -> Void
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playChipEntrance = false

    private var state: VehicleCareDueState {
        VehicleCareDueCalculator.dueState(nextDueDate: schedule.nextDueDate)
    }

    private var band: VehicleCareUrgencyBand? {
        VehicleCareUrgencyStyle.band(for: state)
    }

    private var plainSubtitle: String {
        VehicleCareDueCalculator.shortSubtitle(for: state)
            ?? L10n.string("vehicles.care.due.none")
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
                Button(action: onEdit) {
                    HStack(alignment: .center, spacing: 10) {
                        VehicleCareUrgencyIconTile(
                            systemImage: schedule.kind.systemImage,
                            scheduleID: schedule.id,
                            band: band
                        )

                        Text(schedule.title)
                            .font(.body.weight(.semibold))
                            .glassPrimaryInk()
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        if let band, let chipText = VehicleCareUrgencyStyle.chipText(for: state) {
                            VehicleCareDueChip(
                                text: chipText,
                                band: band,
                                playEntrance: playChipEntrance
                            )
                        } else {
                            Text(plainSubtitle)
                                .font(.caption)
                                .glassSecondaryInk()
                                .lineLimit(1)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.glassPlainHit)

                Button(action: onComplete) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .glassAccentForeground()
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.string("vehicles.care.complete"))

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .glassDisclosureInk()
            }
        .onAppear(perform: consumeChipEntranceIfNeeded)
    }

    private func consumeChipEntranceIfNeeded() {
        guard let band, !reduceMotion else { return }
        playChipEntrance = VehicleCareUrgencyEntranceStore.consume(
            role: .chip,
            scheduleID: schedule.id,
            band: band
        )
    }
}

/// Compatibility alias used by older call sites / docs.
typealias VehicleCareDetailView = VehicleDetailView

/// Add and edit forms that fill the trailing half on the widest book.
private enum TrailingCareEditor: Equatable {
    case addExpense
    case editExpense(UUID)
    case completeSchedule(UUID)
    case addSchedule
    case editSchedule(UUID)
}

/// Back, title, and Save for a care form that fills the trailing half.
/// A nested navigation stack here blanks the whole vehicle screen.
struct VehicleCarePaneEditorBar: View {
    let title: String
    var saveDisabled: Bool
    var onBack: () -> Void
    var onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            GlassToolbarCircleButton(systemName: "chevron.backward", action: onBack)
                .accessibilityLabel(Text("onboarding.back"))
            GlassToolbarNavTitle(title: title)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onSave) {
                Text(L10n.pairingTabSave)
            }
            .buttonStyle(.glassPlainHit)
            .trailhoundCompactProminentButton()
            .disabled(saveDisabled)
            .opacity(saveDisabled ? 0.45 : 1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}

extension View {
    /// List chrome for a care form hosted in the trailing pane. Skips navigation-bar
    /// hiding so the parent vehicle screen keeps its bar.
    func vehicleCareEmbeddedListChrome() -> some View {
        scrollContentBackground(.hidden)
            .listSectionSpacing(GlassTokens.sectionSpacing)
            .onGlassShell()
            .modifier(VehicleCarePaneListWidth(enabled: true))
    }
}

/// Wide panes are regular-width, so List adds iPad side margins.
private struct VehicleCarePaneListWidth: ViewModifier {
    var enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            if #available(iOS 26.0, *) {
                content
                    .contentMargins(.horizontal, 0, for: .scrollContent)
                    .listSectionMargins(.horizontal, 0)
            } else {
                content.contentMargins(.horizontal, 0, for: .scrollContent)
            }
        } else {
            content
        }
    }
}
