import CoreLocation
import SwiftData
import SwiftUI
import UIKit

private enum TripSummaryMetricCardLayout {
    static let titleRowHeight: CGFloat = 16
    static let titleValueSpacing: CGFloat = 4
    static let helpButtonSide: CGFloat = 16
    static let minHeight: CGFloat = 52
}

private enum JournalPickerValue: Hashable {
    case none
    case journal(UUID)
    case createNew
}

private struct FavoritePlaceSheetItem: Identifiable {
    enum Endpoint {
        case start
        case end
    }

    enum Mode {
        case create(PlaceDraft)
        case edit(UUID)
    }

    let mode: Mode
    let endpoint: Endpoint

    var id: String {
        switch mode {
        case .create(let draft):
            return "create-\(endpoint)-\(draft.id.uuidString)"
        case .edit(let placeID):
            return "edit-\(endpoint)-\(placeID.uuidString)"
        }
    }
}

/// Bottom edit sheet for trip detail. Owns keyboard / typing state so MapKit
/// in the parent is not invalidated on every keystroke or keyboard frame.
struct TripDetailEditPanel: View {
    @Bindable var trip: Trip
    let viewModel: TripDetailViewModel
    let glassFrozen: Bool
    let panelRisen: Bool
    let restHeight: CGFloat
    let mapPeek: CGFloat
    let reduceMotion: Bool
    let statCountProgress: [String: Double]
    let speedChartRevealProgress: Double
    @Binding var recordedPointCount: Int
    /// Parent bumps this to clear focus (map tap / fullscreen).
    @Binding var keyboardDismissSignal: Int
    var onDisplayRefresh: () -> Void
    var onRouteInvalidated: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var places: [SavedPlace]
    @Query(sort: \UserCategory.sortOrder) private var categories: [UserCategory]
    @Query private var vehicles: [VehicleProfile]
    @Query(sort: \TravelJournal.endedOn, order: .reverse) private var journals: [TravelJournal]
    @Bindable private var settings = AppSettings.shared

    @State private var noteText: String = ""
    @State private var selectedCategoryID: String = BuiltInCategory.personalID.uuidString
    @State private var selectedVehicleID: UUID?
    @State private var editedFuelConsumption: Double = 7.5
    @State private var editedFuelUnitPrice: Double = 65
    @State private var startAddressText: String = ""
    @State private var endAddressText: String = ""
    @State private var startPlaceNameText: String = ""
    @State private var endPlaceNameText: String = ""
    @State private var originalNoteText: String = ""
    @State private var editedStartedAt: Date = Date()
    @State private var editedEndedAt: Date = Date()
    @State private var trimHeadCount: Int = 0
    @State private var trimTailCount: Int = 0
    @State private var favoritePlaceSheet: FavoritePlaceSheetItem?
    @State private var journalEditor: TravelJournalEditorDraft?
    @State private var keyboardOverlap: CGFloat = 0
    @State private var keyboardAnimationDuration: TimeInterval = 0.25
    @FocusState private var focusedField: TripDetailFocusedField?

    private var isEditing: Bool {
        focusedField != nil || keyboardOverlap > 0.5
    }

    private var containerHeight: CGFloat {
        // Parent lays out by restHeight; recover full height for editing math.
        guard TripDetailKeyboardLayout.restHeightFraction > 0 else { return restHeight }
        return restHeight / TripDetailKeyboardLayout.restHeightFraction
    }

    private var panelHeight: CGFloat {
        TripDetailKeyboardLayout.panelHeight(
            containerHeight: containerHeight,
            isEditing: isEditing,
            mapPeek: mapPeek
        )
    }

    private var scrollBottomInset: CGFloat {
        TripDetailKeyboardLayout.scrollBottomInset(keyboardOverlap: keyboardOverlap)
    }

    private var sortedStops: [TripStop] {
        trip.stops.sorted { $0.startedAt < $1.startedAt }
    }

    private var sortedDetailVehicles: [VehicleProfile] {
        vehicles.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var vehiclePhotoPrefetchID: String {
        VehiclePhotoStore.prefetchTaskID(for: sortedDetailVehicles)
    }

    private var selectedDetailVehicle: VehicleProfile? {
        selectedVehicleID.flatMap { id in
            sortedDetailVehicles.first(where: { $0.id == id })
        }
    }

    private var previewFuelCost: Double {
        FuelCostCalculator.estimateCost(
            distanceMeters: trip.distanceMeters,
            vehicle: selectedDetailVehicle,
            consumptionPer100: editedFuelConsumption,
            unitPrice: editedFuelUnitPrice
        )
    }

    /// Cheap keyboard preview: scale stored dynamic by ΔC₀ × Δprice without walking points.
    private var previewDynamicFuelCost: Double? {
        guard let stored = trip.dynamicFuelCost, stored > 0 else { return nil }
        let baseC0 = trip.fuelConsumptionPer100 ?? editedFuelConsumption
        let basePrice = trip.fuelUnitPrice ?? editedFuelUnitPrice
        guard baseC0 > 0, basePrice > 0, editedFuelConsumption > 0, editedFuelUnitPrice > 0 else {
            return stored
        }
        return stored * (editedFuelConsumption / baseC0) * (editedFuelUnitPrice / basePrice)
    }

    private var consumptionFieldTitle: String {
        selectedDetailVehicle?.consumptionLabel ?? L10n.fuelUnitLPer100km
    }

    private var fuelPriceFieldTitle: String {
        fuelUnitPriceLabel(for: selectedDetailVehicle)
    }

    private var focusedFieldTitle: String {
        guard let focusedField else { return "" }
        return focusedField.title(
            consumptionLabel: consumptionFieldTitle,
            fuelPriceLabel: fuelPriceFieldTitle
        )
    }

    private var maxTrimHead: Int {
        max(0, recordedPointCount - trimTailCount - 2)
    }

    private var maxTrimTail: Int {
        max(0, recordedPointCount - trimHeadCount - 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            panelGrabber

            if panelRisen {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        detailPanelContent
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .dismissKeyboardOnScroll()
                    .onChange(of: focusedField) { _, field in
                        scrollToFocusedField(field, proxy: proxy)
                    }
                    .onChange(of: keyboardOverlap) { _, _ in
                        scrollToFocusedField(focusedField, proxy: proxy)
                    }
                    .onChange(of: panelHeight) { _, _ in
                        scrollToFocusedField(focusedField, proxy: proxy)
                    }
                }
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: panelHeight)
        .frame(maxWidth: .infinity)
        .onKeyboardOverlap($keyboardOverlap, animationDuration: $keyboardAnimationDuration)
        .animation(panelHeightAnimation, value: panelHeight)
        .animation(panelHeightAnimation, value: scrollBottomInset)
        .dismissKeyboardOnTap(focus: $focusedField)
        .fieldKeyboardAccessory(
            title: focusedFieldTitle,
            focusID: focusedField.map { AnyHashable($0) },
            onDone: { dismissKeyboard() }
        )
        .sheet(item: $favoritePlaceSheet) { item in
            NavigationStack {
                favoritePlacePicker(for: item)
            }
        }
        .sheet(item: $journalEditor) { draft in
            TravelJournalEditorSheet(draft: draft)
        }
        .onAppear {
            loadEditStateFromTrip()
        }
        .onChange(of: keyboardDismissSignal) { _, _ in
            dismissKeyboard()
        }
        .onChange(of: trip.id) { _, _ in
            loadEditStateFromTrip()
        }
    }

    private var panelHeightAnimation: Animation? {
        if reduceMotion { return nil }
        return .easeOut(duration: max(0.15, keyboardAnimationDuration))
    }

    private func scrollToFocusedField(
        _ field: TripDetailFocusedField?,
        proxy: ScrollViewProxy
    ) {
        guard let field else { return }
        let action = {
            proxy.scrollTo(field, anchor: UnitPoint(x: 0.5, y: 0.24))
        }
        if reduceMotion {
            action()
        } else {
            withAnimation(.easeOut(duration: 0.22), action)
        }
    }

    private func dismissKeyboard() {
        focusedField = nil
        KeyboardDismiss.dismiss()
    }

    private func loadEditStateFromTrip() {
        noteText = trip.note ?? ""
        originalNoteText = noteText
        selectedCategoryID = trip.categoryID
        selectedVehicleID = trip.vehicleID
        loadFuelEditDefaults(for: selectedVehicleID, preferTripSnapshot: true)
        startAddressText = trip.startAddress ?? ""
        endAddressText = trip.endAddress ?? ""
        startPlaceNameText = trip.startPlaceName ?? ""
        endPlaceNameText = trip.endPlaceName ?? ""
        editedStartedAt = trip.startedAt
        editedEndedAt = trip.endedAt ?? Date()
        trimHeadCount = 0
        trimTailCount = 0
    }

    private var panelGrabber: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }

    private var detailPanelContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            tripHeader

            statsStrip

            if !viewModel.speedSamples.isEmpty {
                speedChartCard
            }

            if !sortedStops.isEmpty {
                detailSelectionSection(title: L10n.tripStopsSection) {
                    VStack(spacing: 10) {
                        ForEach(sortedStops, id: \.persistentModelID) { stop in
                            TripStopEditRow(stop: stop, glassFrozen: glassFrozen)
                        }
                    }
                }
            }

            if trip.endedAt != nil {
                detailSplitSection(title: L10n.tripEditTimesSection) {
                    tripTimePicker(
                        title: L10n.tripStartedAt,
                        selection: $editedStartedAt
                    )
                } right: {
                    tripTimePicker(
                        title: L10n.tripEndedAt,
                        selection: $editedEndedAt
                    )
                }
            } else {
                detailSection(title: L10n.tripEditTimesSection) {
                    tripTimePicker(
                        title: L10n.tripStartedAt,
                        selection: $editedStartedAt
                    )
                }
            }

            detailSplitSection(title: L10n.tripTrimPointsSection) {
                trimStepperCell(
                    title: L10n.tripTrimHead,
                    value: $trimHeadCount,
                    range: 0...maxTrimHead
                )
            } right: {
                trimStepperCell(
                    title: L10n.tripTrimTail,
                    value: $trimTailCount,
                    range: 0...maxTrimTail
                )
            }

            detailSection(title: L10n.tripLocationOverrides) {
                compactTextField(
                    L10n.tripStartPlaceName,
                    text: $startPlaceNameText,
                    field: .startPlace
                )
                favoritePlaceAction(
                    endpoint: .start,
                    coordinate: trip.startCoordinate,
                    accessibilityLabel: L10n.tripAddStartToFavorites
                )
                compactTextField(
                    L10n.tripEndPlaceName,
                    text: $endPlaceNameText,
                    field: .endPlace
                )
                favoritePlaceAction(
                    endpoint: .end,
                    coordinate: trip.endCoordinate,
                    accessibilityLabel: L10n.tripAddEndToFavorites
                )
                compactTextField(
                    L10n.tripStartAddress,
                    text: $startAddressText,
                    field: .startAddress
                )
                compactTextField(
                    L10n.tripEndAddress,
                    text: $endAddressText,
                    field: .endAddress
                )
            }

            if vehicles.isEmpty {
                detailSection(title: L10n.tripEditCategory) {
                    detailMenuPicker(title: L10n.tripEditCategory, selection: $selectedCategoryID) {
                        ForEach(categories) { category in
                            Label(category.name, systemImage: category.systemImage)
                                .tag(category.id.uuidString)
                        }
                    }
                    .onChange(of: selectedCategoryID) { _, _ in
                        dismissKeyboard()
                    }
                }
            } else {
                detailSplitSection(title: L10n.tripEditCategory) {
                    detailMenuPicker(title: L10n.tripEditCategory, selection: $selectedCategoryID) {
                        ForEach(categories) { category in
                            Label(category.name, systemImage: category.systemImage)
                                .tag(category.id.uuidString)
                        }
                    }
                    .onChange(of: selectedCategoryID) { _, _ in
                        dismissKeyboard()
                    }
                } right: {
                    detailMenuPicker(
                        title: L10n.string("trip.edit.vehicle"),
                        selection: $selectedVehicleID,
                        leading: {
                            if let selected = sortedDetailVehicles.first(where: { $0.id == selectedVehicleID }) {
                                VehicleAvatarView(
                                    systemImage: selected.systemImage,
                                    photoFileName: selected.photoFileName,
                                    size: 22,
                                    cornerRadius: 6,
                                    isElectricAccent: selected.fuelType == .electric
                                )
                            } else {
                                Image(systemName: "car")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22, height: 22)
                            }
                        }
                    ) {
                        Text(L10n.string("trip.edit.vehicle_none"))
                            .tag(UUID?.none)
                        ForEach(sortedDetailVehicles) { vehicle in
                            Text(vehicle.name)
                                .tag(Optional(vehicle.id))
                        }
                    }
                    .onChange(of: selectedVehicleID) { _, newID in
                        dismissKeyboard()
                        loadFuelEditDefaults(for: newID, preferTripSnapshot: false)
                    }
                    .task(id: vehiclePhotoPrefetchID) {
                        await VehiclePhotoStore.shared.prefetch(vehicles: sortedDetailVehicles)
                    }
                }
            }

            detailSplitSection(
                title: L10n.tripEditFuelSection,
                helpTitle: L10n.tripEditFuelHelpTitle,
                helpBody: L10n.tripEditFuelHelpBody
            ) {
                fuelNumberField(
                    title: consumptionFieldTitle,
                    value: $editedFuelConsumption,
                    field: .fuelConsumption
                )
            } right: {
                fuelNumberField(
                    title: fuelPriceFieldTitle,
                    value: $editedFuelUnitPrice,
                    field: .fuelPrice
                )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.tripEditFuelPreview(FuelCostCalculator.formatCost(
                    previewFuelCost,
                    currencyCode: settings.fuelCurrency.rawValue
                )))
                if let previewDynamic = previewDynamicFuelCost {
                    Text("\(L10n.dynamicFuel): \(FuelCostCalculator.formatCost(previewDynamic, currencyCode: settings.fuelCurrency.rawValue))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, -6)

            detailSection(title: L10n.tripEditNote) {
                TextField(L10n.tripEditNotePlaceholder, text: $noteText, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($focusedField, equals: .note)
                    .submitLabel(.done)
                    .glassInputField()
                    .onSubmit { dismissKeyboard() }
                    .id(TripDetailFocusedField.note)
            }

            if trip.endedAt != nil {
                journalMembershipRow
            }

            Button(L10n.tripEditSave) {
                saveEdits()
                dismissKeyboard()
            }
            .accessibilityIdentifier("tripDetail.save")
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .tint(TrailhoundBrandColors.brandBottom)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, GlassTokens.listContentHorizontalInset)
        .padding(.bottom, scrollBottomInset)
    }

    private var tripHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.routeSummary)
                .font(.headline)
                .lineLimit(2)

            Text(viewModel.dateText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var journalMembershipRow: some View {
        detailSection(
            title: L10n.journalAdd,
            helpTitle: L10n.journalAddHelpTitle,
            helpBody: L10n.journalAddHelpBody,
            helpSheetHeight: 380
        ) {
            detailMenuPicker(
                title: L10n.journalAdd,
                selection: journalPickerValue,
                leading: {
                    Image(systemName: trip.journalID == nil ? "map" : "map.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
            ) {
                Section {
                    Label(L10n.journalNew, systemImage: "plus")
                        .tag(JournalPickerValue.createNew)
                }
                Section {
                    Text(L10n.journalNone)
                        .tag(JournalPickerValue.none)
                    ForEach(journals, id: \.id) { journal in
                        Text(journal.title)
                            .tag(JournalPickerValue.journal(journal.id))
                    }
                }
            }
            .accessibilityLabel(L10n.journalAdd)
            .accessibilityValue(selectedJournalTitle)
        }
    }

    private var selectedJournalTitle: String {
        guard let journalID = trip.journalID,
              let journal = journals.first(where: { $0.id == journalID }) else {
            return L10n.journalNone
        }
        return journal.title
    }

    private var journalPickerValue: Binding<JournalPickerValue> {
        Binding(
            get: {
                guard let journalID = trip.journalID,
                      journals.contains(where: { $0.id == journalID }) else {
                    return .none
                }
                return .journal(journalID)
            },
            set: { newValue in
                switch newValue {
                case .none:
                    journalSelection.wrappedValue = nil
                case .journal(let id):
                    journalSelection.wrappedValue = id
                case .createNew:
                    openNewTravelEditor()
                }
            }
        )
    }

    private func openNewTravelEditor() {
        dismissKeyboard()
        TrailhoundHaptics.selection()
        let tripID = trip.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            journalEditor = .create(preselectedTripIDs: [tripID])
        }
    }

    private var journalSelection: Binding<UUID?> {
        Binding(
            get: { trip.journalID },
            set: { newValue in
                dismissKeyboard()
                let journal = newValue.flatMap { id in journals.first { $0.id == id } }
                TravelJournalTotals.assign(trip: trip, to: journal, in: modelContext)
                try? modelContext.save()
                TrailhoundHaptics.selection()
            }
        )
    }

    @ViewBuilder
    private var statsStrip: some View {
        let fuelCurrencyCode = settings.fuelCurrency.rawValue
        statsMetricGrid(metrics: viewModel.summaryMetrics)
            .id(fuelCurrencyCode)
    }

    private func statsMetricGrid(metrics: [TripSummaryMetric]) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(metrics) { metric in
                statsMetricCard(for: metric)
            }
        }
    }

    private func statsMetricCard(for metric: TripSummaryMetric) -> some View {
        let progress = statCountProgress[metric.id] ?? (panelRisen ? 1 : 0)
        return VStack(alignment: .leading, spacing: TripSummaryMetricCardLayout.titleValueSpacing) {
            HStack(alignment: .center, spacing: 4) {
                Label(metric.title, systemImage: metric.icon)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if metric.showsHelp, let helpTitle = metric.helpTitle, let helpBody = metric.helpBody {
                    HelpPopoverButton(
                        accessibilityLabel: helpTitle,
                        message: helpBody,
                        side: TripSummaryMetricCardLayout.helpButtonSide
                    )
                }
            }
            .frame(height: TripSummaryMetricCardLayout.titleRowHeight)

            Text(metric.formatted(progress: progress))
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : TrailhoundMotion.snappy, value: progress)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(
            maxWidth: .infinity,
            minHeight: TripSummaryMetricCardLayout.minHeight,
            alignment: .topLeading
        )
        .glassChrome(cornerRadius: 10, frozen: glassFrozen)
        .opacity(progress > 0.01 || reduceMotion ? 1 : 0.35)
        .scaleEffect(progress > 0.01 || reduceMotion ? 1 : 0.94)
    }

    private var speedChartCard: some View {
        let progress = speedChartRevealProgress

        return VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tripSpeedChart)
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(L10n.formatSpeedKmh(viewModel.speedChartMaxKmh))
                        .font(.caption2)
                    Spacer(minLength: 0)
                    Text(L10n.formatSpeedKmh(0))
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 120)

                SpeedChartRouteCanvas(
                    samples: viewModel.speedSamples,
                    maxKmh: viewModel.speedChartMaxKmh,
                    progress: progress,
                    tripStartedAt: trip.startedAt,
                    tripEndedAt: trip.endedAt ?? trip.startedAt,
                    sampleMedianIntervalSeconds: viewModel.speedSampleMedianIntervalSeconds
                )
                .frame(maxWidth: .infinity)
                .frame(height: 120)
            }
        }
        .padding(12)
        .glassChrome(cornerRadius: 12, frozen: glassFrozen)
        .opacity(progress > 0.01 || reduceMotion ? 1 : 0.35)
        .scaleEffect(progress > 0.01 || reduceMotion ? 1 : 0.98)
    }

    private func tripTimePicker(title: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            DatePicker(title, selection: selection, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .buttonStyle(.plain)
                .tint(TrailhoundBrandColors.brandBottom)
                .frame(maxWidth: .infinity, alignment: .leading)

            DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .buttonStyle(.plain)
                .tint(TrailhoundBrandColors.brandBottom)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private func trimStepperCell(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                detailCompactStepButton(systemImage: "minus") {
                    value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
                }
                .disabled(value.wrappedValue <= range.lowerBound)

                Text("\(value.wrappedValue)")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)

                detailCompactStepButton(systemImage: "plus") {
                    value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
                }
                .disabled(value.wrappedValue >= range.upperBound)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailCompactStepButton(
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
                .frame(width: 26, height: 26)
                .glassField(cornerRadius: 6)
        }
        .buttonStyle(.plain)
    }

    private func detailMenuPicker<Selection: Hashable, Content: View>(
        title: String,
        selection: Binding<Selection>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        detailMenuPicker(title: title, selection: selection, leading: { EmptyView() }, content: content)
    }

    private func detailMenuPicker<Selection: Hashable, Leading: View, Content: View>(
        title: String,
        selection: Binding<Selection>,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            HStack(spacing: 8) {
                leading()
                Picker(title, selection: selection, content: content)
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .buttonStyle(.plain)
                    .font(.callout)
                    .tint(.primary)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private func detailMiniCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .glassChrome(cornerRadius: 12, frozen: glassFrozen)
    }

    private func detailSplitSection<Left: View, Right: View>(
        title: String,
        helpTitle: String? = nil,
        helpBody: String? = nil,
        @ViewBuilder left: () -> Left,
        @ViewBuilder right: () -> Right
    ) -> some View {
        detailSelectionSection(title: title, helpTitle: helpTitle, helpBody: helpBody) {
            HStack(alignment: .top, spacing: 10) {
                detailMiniCard(content: left)
                    .frame(minWidth: 0, maxWidth: .infinity)
                detailMiniCard(content: right)
                    .frame(minWidth: 0, maxWidth: .infinity)
            }
        }
    }

    private func detailSelectionSection<Content: View>(
        title: String,
        helpTitle: String? = nil,
        helpBody: String? = nil,
        helpSheetHeight: CGFloat = 240,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let helpTitle, let helpBody {
                    HelpPopoverButton(
                        accessibilityLabel: helpTitle,
                        message: helpBody,
                        side: 22,
                        sheetHeight: helpSheetHeight
                    )
                }
            }

            content()
        }
    }

    private func detailSection<Content: View>(
        title: String,
        helpTitle: String? = nil,
        helpBody: String? = nil,
        helpSheetHeight: CGFloat = 240,
        @ViewBuilder content: () -> Content
    ) -> some View {
        detailSelectionSection(
            title: title,
            helpTitle: helpTitle,
            helpBody: helpBody,
            helpSheetHeight: helpSheetHeight
        ) {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .padding(12)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .glassChrome(cornerRadius: 12, frozen: glassFrozen)
        }
    }

    private func compactTextField(
        _ title: String,
        text: Binding<String>,
        field: TripDetailFocusedField
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: text)
                .focused($focusedField, equals: field)
                .glassInputField()
        }
        .id(field)
    }

    private func fuelNumberField(
        title: String,
        value: Binding<Double>,
        field: TripDetailFocusedField
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, value: value, format: .number.precision(.fractionLength(0...2)))
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: field)
                .glassInputField()
        }
        .id(field)
    }

    @ViewBuilder
    private func favoritePlaceAction(
        endpoint: FavoritePlaceSheetItem.Endpoint,
        coordinate: CLLocationCoordinate2D?,
        accessibilityLabel: String
    ) -> some View {
        if let coordinate {
            let existing = places.first(where: { $0.contains(coordinate) })
            Button {
                dismissKeyboard()
                if let existing {
                    favoritePlaceSheet = FavoritePlaceSheetItem(
                        mode: .edit(existing.id),
                        endpoint: endpoint
                    )
                } else {
                    favoritePlaceSheet = FavoritePlaceSheetItem(
                        mode: .create(draft(for: endpoint, coordinate: coordinate)),
                        endpoint: endpoint
                    )
                }
            } label: {
                Label(
                    existing == nil ? L10n.tripAddToFavorites : L10n.placeAlreadySaved,
                    systemImage: existing == nil ? "star" : "star.fill"
                )
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(existing == nil ? accessibilityLabel : L10n.tripEditFavoritePlace)
        }
    }

    private func draft(
        for endpoint: FavoritePlaceSheetItem.Endpoint,
        coordinate: CLLocationCoordinate2D
    ) -> PlaceDraft {
        let placeName: String
        let address: String?
        switch endpoint {
        case .start:
            placeName = startPlaceNameText.trimmingCharacters(in: .whitespacesAndNewlines)
            address = startAddressText.trimmingCharacters(in: .whitespacesAndNewlines)
        case .end:
            placeName = endPlaceNameText.trimmingCharacters(in: .whitespacesAndNewlines)
            address = endAddressText.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let resolvedName: String
        if !placeName.isEmpty {
            resolvedName = placeName
        } else if let address, !address.isEmpty {
            resolvedName = address
        } else {
            resolvedName = ""
        }

        return PlaceDraft(
            name: resolvedName,
            coordinate: coordinate,
            address: (address?.isEmpty == false) ? address : nil,
            kind: .other
        )
    }

    @ViewBuilder
    private func favoritePlacePicker(for item: FavoritePlaceSheetItem) -> some View {
        switch item.mode {
        case .create(let draft):
            PlacePickerView(draft: draft) { savedName in
                applyFavoritePlaceName(savedName, to: item.endpoint)
            }
        case .edit(let placeID):
            if let place = places.first(where: { $0.id == placeID }) {
                PlacePickerView(editingPlace: place) { savedName in
                    applyFavoritePlaceName(savedName, to: item.endpoint)
                }
            } else {
                Text(L10n.placeAlreadySaved)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func applyFavoritePlaceName(_ name: String, to endpoint: FavoritePlaceSheetItem.Endpoint) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch endpoint {
        case .start:
            startPlaceNameText = trimmed
            trip.startPlaceName = trimmed
        case .end:
            endPlaceNameText = trimmed
            trip.endPlaceName = trimmed
        }

        TripDerivedMetrics.refreshSearchIndex(
            for: trip,
            places: places,
            privacyRadius: settings.privacyRadiusMeters
        )
        try? modelContext.save()
        onDisplayRefresh()
    }

    private func loadFuelEditDefaults(for vehicleID: UUID?, preferTripSnapshot: Bool) {
        let vehicle = vehicleID.flatMap { id in
            sortedDetailVehicles.first(where: { $0.id == id })
        }
        if preferTripSnapshot {
            editedFuelConsumption = FuelCostCalculator.resolvedConsumption(
                tripConsumption: trip.fuelConsumptionPer100,
                vehicle: vehicle
            )
            editedFuelUnitPrice = FuelCostCalculator.resolvedUnitPrice(
                tripUnitPrice: trip.fuelUnitPrice,
                vehicle: vehicle
            )
        } else {
            editedFuelConsumption = FuelCostCalculator.resolvedConsumption(vehicle: vehicle)
            editedFuelUnitPrice = FuelCostCalculator.resolvedUnitPrice(vehicle: vehicle)
        }
    }

    private func fuelUnitPriceLabel(for vehicle: VehicleProfile?) -> String {
        vehicle?.fuelType == .electric ? L10n.fuelUnitCostPerKWh : L10n.fuelUnitCostPerLiter
    }

    private func saveEdits() {
        let previousRollup = TripRollupService.snapshot(of: trip)

        trip.note = noteText.isEmpty ? nil : noteText
        if selectedCategoryID != trip.categoryID {
            trip.categoryOrigin = .user
            trip.clearPendingSuggestion()
        }
        trip.categoryID = selectedCategoryID
        let vehicle = selectedVehicleID.flatMap { VehicleResolver.vehicle(withID: $0, in: modelContext) }
        VehicleResolver.assign(vehicle: vehicle, to: trip)
        trip.startAddress = startAddressText.isEmpty ? nil : startAddressText
        trip.endAddress = endAddressText.isEmpty ? nil : endAddressText
        trip.startPlaceName = startPlaceNameText.isEmpty ? nil : startPlaceNameText
        trip.endPlaceName = endPlaceNameText.isEmpty ? nil : endPlaceNameText
        trip.startedAt = editedStartedAt
        if trip.endedAt != nil {
            trip.endedAt = max(editedEndedAt, editedStartedAt)
        }
        let didTrim = applyGPSTrimIfNeeded()
        FuelCostCalculator.applyEstimate(
            to: trip,
            distanceMeters: trip.distanceMeters,
            vehicle: vehicle,
            consumptionPer100: editedFuelConsumption,
            unitPrice: editedFuelUnitPrice
        )
        TripDerivedMetrics.recompute(
            for: trip,
            places: places,
            privacyRadius: settings.privacyRadiusMeters,
            fuelType: vehicle?.fuelType ?? .petrol
        )
        TripRollupService.update(trip, from: previousRollup, in: modelContext)
        if let journal = trip.journal {
            TravelJournalTotals.refresh(journal)
        } else {
            TravelJournalTotals.refresh(journalID: trip.journalID, in: modelContext)
        }
        originalNoteText = noteText
        try? modelContext.save()
        ToastPresenter.shared.show(.tripSaved)
        onDisplayRefresh()
        if didTrim {
            onRouteInvalidated()
        }
    }

    @discardableResult
    private func applyGPSTrimIfNeeded() -> Bool {
        guard trimHeadCount > 0 || trimTailCount > 0 else { return false }

        var sorted = trip.sortedPoints
        guard sorted.count > trimHeadCount + trimTailCount else { return false }

        if trimHeadCount > 0 {
            sorted.removeFirst(trimHeadCount)
        }
        if trimTailCount > 0 {
            sorted.removeLast(trimTailCount)
        }

        for point in trip.points {
            modelContext.delete(point)
        }
        trip.points.removeAll()

        var distance: Double = 0
        var previousLocation: CLLocation?
        for (index, oldPoint) in sorted.enumerated() {
            let point = TripPoint(
                timestamp: oldPoint.timestamp,
                latitude: oldPoint.latitude,
                longitude: oldPoint.longitude,
                sequence: index,
                speedMps: oldPoint.speedMps,
                trip: trip
            )
            trip.points.append(point)
            modelContext.insert(point)

            let location = CLLocation(latitude: oldPoint.latitude, longitude: oldPoint.longitude)
            if let previousLocation {
                distance += location.distance(from: previousLocation)
            }
            previousLocation = location
        }

        trip.distanceMeters = distance
        trip.invalidatePointCaches()
        TripDetailViewModel.invalidateSpeedSegmentCache(for: trip.id)
        TripRoutePathCache.shared.remove(for: trip.id)
        DevLog.shared.log(
            .tripDetail,
            "gps trim trip=\(trip.id.uuidString.prefix(8)) head=\(trimHeadCount) tail=\(trimTailCount)"
        )
        trimHeadCount = 0
        trimTailCount = 0
        recordedPointCount = trip.points.count
        return true
    }
}

private struct TripStopEditRow: View {
    @Bindable var stop: TripStop
    var glassFrozen: Bool
    @State private var startedAt: Date = Date()

    private let durationRange = 1...240

    private var durationMinutes: Binding<Int> {
        Binding(
            get: {
                max(durationRange.lowerBound, Int((stop.durationSeconds / 60.0).rounded()))
            },
            set: { newValue in
                let clamped = min(durationRange.upperBound, max(durationRange.lowerBound, newValue))
                stop.durationSeconds = TimeInterval(clamped * 60)
            }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            stopMiniCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tripStartedAt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    DatePicker(L10n.tripStartedAt, selection: $startedAt, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .buttonStyle(.plain)
                        .tint(TrailhoundBrandColors.brandBottom)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    DatePicker(L10n.tripStartedAt, selection: $startedAt, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .buttonStyle(.plain)
                        .tint(TrailhoundBrandColors.brandBottom)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                .onChange(of: startedAt) { _, newValue in
                    stop.startedAt = newValue
                }
            }

            stopMiniCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.duration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    HStack(spacing: 6) {
                        stopStepButton(systemImage: "minus") {
                            durationMinutes.wrappedValue -= 1
                        }
                        .disabled(durationMinutes.wrappedValue <= durationRange.lowerBound)

                        Text(DateFormatters.formatDuration(TimeInterval(durationMinutes.wrappedValue * 60)))
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)

                        stopStepButton(systemImage: "plus") {
                            durationMinutes.wrappedValue += 1
                        }
                        .disabled(durationMinutes.wrappedValue >= durationRange.upperBound)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            startedAt = stop.startedAt
        }
    }

    private func stopMiniCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .glassChrome(cornerRadius: 12, frozen: glassFrozen)
    }

    private func stopStepButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
                .glassField(cornerRadius: 6)
        }
        .buttonStyle(.plain)
    }
}
