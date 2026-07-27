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
                PairingVehicleEditorForm(vehicle: vehicle)
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
    @Bindable var vehicle: VehicleProfile
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable private var settings = AppSettings.shared
    @Query private var vehicles: [VehicleProfile]

    private var isOnlyVehicle: Bool { vehicles.count <= 1 }

    private var selectedIcon: VehicleIconOption {
        VehicleIconOption.resolved(vehicle.iconName)
    }

    var body: some View {
        Form {
            Section(L10n.pairingTabVehicleSection) {
                TextField(L10n.pairingTabVehicleName, text: $vehicle.name)
                    .glassRow(position: .first)
                Picker(L10n.pairingTabFuelType, selection: Binding(
                    get: { vehicle.fuelType },
                    set: { vehicle.fuelType = $0 }
                )) {
                    ForEach(VehicleFuelType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .glassRow(position: .middle)
                LabeledContent(vehicle.consumptionLabel) {
                    TextField(vehicle.consumptionLabel, value: $vehicle.consumption, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                .glassRow(position: vehicle.fuelType == .electric ? .middle : .last)
                if vehicle.fuelType == .electric {
                    LabeledContent(L10n.pairingTabChargePrice) {
                        TextField("TL/kWh", value: Binding(
                            get: { vehicle.chargePricePerKWh ?? settings.evChargePricePerKWh },
                            set: { vehicle.chargePricePerKWh = $0 }
                        ), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    }
                    .glassRow(position: .last)
                }
            }

            Section(L10n.pairingTabVehicleIcon) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
                    spacing: 8
                ) {
                    ForEach(VehicleIconOption.available) { option in
                        Button {
                            vehicle.iconName = option.rawValue
                            TrailhoundHaptics.selection()
                        } label: {
                            Image(systemName: option.rawValue)
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(
                                    selectedIcon == option
                                        ? TrailhoundBrandColors.brandBottom
                                        : Color.secondary
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(
                                            selectedIcon == option
                                                ? TrailhoundBrandColors.brandBottom.opacity(0.14)
                                                : Color.secondary.opacity(0.08)
                                        )
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            selectedIcon == option
                                                ? TrailhoundBrandColors.brandBottom
                                                : Color.clear,
                                            lineWidth: 2
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(option.rawValue)
                        .accessibilityAddTraits(selectedIcon == option ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
                .glassListRow()
            }

            Section {
                Button {
                    guard !isOnlyVehicle else { return }
                    if vehicle.isDefault {
                        defaultVehicleBinding.wrappedValue = false
                    } else {
                        defaultVehicleBinding.wrappedValue = true
                    }
                } label: {
                    HStack {
                        Text(L10n.pairingTabDefaultVehicle)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: vehicle.isDefault ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundStyle(
                                vehicle.isDefault
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
                    do {
                        try modelContext.save()
                        dismiss()
                    } catch {
                        AppErrorPresenter.shared.present(L10n.pairingTabSaveFailed(error.localizedDescription))
                    }
                }
                .frame(maxWidth: .infinity)
                .tint(TrailhoundBrandColors.brandBottom)
                .glassListRow()
            }
        }
        .glassListChrome()
        .navigationTitle(vehicle.name)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneToolbar()
    }

    private var defaultVehicleBinding: Binding<Bool> {
        Binding(
            get: { vehicle.isDefault },
            set: { shouldBeDefault in
                if shouldBeDefault {
                    VehiclePairingService.setDefaultVehicle(vehicle, in: modelContext)
                    settings.recordingVehicleID = vehicle.id
                } else if vehicle.isDefault, let next = vehicles.first(where: { $0.id != vehicle.id }) {
                    VehiclePairingService.setDefaultVehicle(next, in: modelContext)
                }
            }
        )
    }
}
