import SwiftData
import SwiftUI

struct PairingVehicleEditorView: View {
    let vehicleID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var vehicles: [VehicleProfile]

    private var vehicle: VehicleProfile? {
        vehicles.first { $0.id == vehicleID }
    }

    var body: some View {
        Group {
            if let vehicle {
                PairingVehicleEditorForm(vehicle: vehicle, vehicles: vehicles)
            } else {
                ContentUnavailableView(L10n.pairingTabVehicleNotFound, systemImage: "car")
            }
        }
        .onChange(of: vehicle?.id) { _, newID in
            if newID == nil {
                dismiss()
            }
        }
    }
}

private struct PairingVehicleEditorForm: View {
    let vehicle: VehicleProfile
    let vehicles: [VehicleProfile]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = AppSettings.shared

    @State private var draft: VehicleEditorDraft?

    private var isOnlyVehicle: Bool { vehicles.count <= 1 }

    private var activeDraft: VehicleEditorDraft {
        draft ?? VehicleEditorDraft(from: vehicle)
    }

    var body: some View {
        Form {
            Section(L10n.pairingTabVehicleSection) {
                TextField(L10n.pairingTabVehicleName, text: draftBinding(\.name))
                    .glassRow(position: .first)
                Picker(L10n.pairingTabFuelType, selection: draftBinding(\.fuelType)) {
                    ForEach(VehicleFuelType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .glassRow(position: .middle)
                LabeledContent(activeDraft.consumptionLabel) {
                    TextField(activeDraft.consumptionLabel, value: draftBinding(\.consumption), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                .glassRow(position: activeDraft.fuelType == .electric ? .middle : .last)
                if activeDraft.fuelType == .electric {
                    LabeledContent(L10n.pairingTabChargePrice) {
                        TextField(
                            "TL/kWh",
                            value: electricChargeBinding,
                            format: .number
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    }
                    .glassRow(position: .last)
                }
            }

            Section {
                VehicleIconPickerGrid(
                    selection: draftBinding(\.iconName),
                    icons: VehicleIconOption.pairingEditorIcons
                )
                .glassListRow()
                .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
            }

            Section {
                Button {
                    guard !isOnlyVehicle else { return }
                    updateDraft { $0.wantsDefault.toggle() }
                } label: {
                    HStack {
                        Text(L10n.pairingTabDefaultVehicle)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: activeDraft.wantsDefault ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundStyle(
                                activeDraft.wantsDefault
                                    ? TrailhoundBrandColors.brandBottom
                                    : Color.secondary
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(isOnlyVehicle)
                .glassListRow()
            }

            Section {
                Button(L10n.pairingTabSave) {
                    saveVehicle()
                }
                .frame(maxWidth: .infinity)
                .tint(TrailhoundBrandColors.brandBottom)
                .glassListRow()
            }
        }
        .glassListChrome()
        .navigationTitle(L10n.pairingTabVehicleSection)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneToolbar()
        .onAppear { reloadDraft() }
        .onChange(of: vehicle.id) { _, _ in reloadDraft() }
    }

    private func reloadDraft() {
        draft = VehicleEditorDraft(from: vehicle)
    }

    private func saveVehicle() {
        let snapshot = activeDraft
        do {
            try snapshot.apply(
                to: vehicle,
                allVehicles: vehicles,
                in: modelContext,
                settings: settings
            )
            ToastPresenter.shared.show(.vehicleSaved)
            dismiss()
        } catch {
            AppErrorPresenter.shared.present(L10n.pairingTabSaveFailed(error.localizedDescription))
        }
    }

    private func updateDraft(_ mutate: (inout VehicleEditorDraft) -> Void) {
        var next = activeDraft
        mutate(&next)
        draft = next
    }

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<VehicleEditorDraft, Value>) -> Binding<Value> {
        Binding(
            get: { activeDraft[keyPath: keyPath] },
            set: { newValue in
                updateDraft { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private var electricChargeBinding: Binding<Double> {
        Binding(
            get: { activeDraft.chargePricePerKWh ?? settings.evChargePricePerKWh },
            set: { newValue in
                updateDraft { $0.chargePricePerKWh = newValue }
            }
        )
    }
}

private struct VehicleIconPickerGrid: View {
    @Binding var selection: String
    let icons: [VehicleIconOption]

    private let iconsPerRow = 5

    private var iconRows: [[VehicleIconOption]] {
        stride(from: 0, to: icons.count, by: iconsPerRow).map { start in
            Array(icons[start ..< min(start + iconsPerRow, icons.count)])
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(iconRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row) { option in
                        iconCell(option)
                    }
                    if row.count < iconsPerRow {
                        ForEach(0 ..< (iconsPerRow - row.count), id: \.self) { _ in
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.pairingTabVehicleIcon)
    }

    @ViewBuilder
    private func iconCell(_ option: VehicleIconOption) -> some View {
        let isSelected = selection == option.rawValue
        Button {
            selection = option.rawValue
            TrailhoundHaptics.selection()
        } label: {
            Image(systemName: option.rawValue)
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? TrailhoundBrandColors.brandBottom : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isSelected
                            ? TrailhoundBrandColors.brandBottom.opacity(0.14)
                            : Color.secondary.opacity(0.08))
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isSelected ? TrailhoundBrandColors.brandBottom : .clear,
                            lineWidth: 2
                        )
                }
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(option.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
