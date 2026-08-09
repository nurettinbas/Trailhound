import SwiftData
import SwiftUI

private enum VehicleNavDestination: Hashable {
    case detail(UUID)
}

struct PairingTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationService.self) private var locationService
    @Bindable private var settings = AppSettings.shared
    @Bindable private var tabSelection = TabSelection.shared
    @Query private var vehicles: [VehicleProfile]
    @Query private var schedules: [VehicleSchedule]

    @State private var vehiclePendingDeleteID: UUID?
    @State private var showDeleteConfirmation = false
    @State private var navigationPath = NavigationPath()
    @State private var showShortcutsAutomationGuide = false

    private var sortedVehicles: [VehicleProfile] {
        vehicles.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            pairingList
                .navigationDestination(for: VehicleNavDestination.self) { destination in
                    switch destination {
                    case .detail(let id):
                        VehicleDetailView(vehicleID: id)
                    }
                }
        }
        .background(Color.clear)
        .onAppear {
            consumePendingCareDeepLink()
        }
        .onChange(of: tabSelection.pendingVehicleCareID) { _, _ in
            consumePendingCareDeepLink()
        }
        .task(id: vehiclePhotoPrefetchID) {
            await VehiclePhotoStore.shared.prefetch(vehicles: sortedVehicles)
        }
    }

    private var vehiclePhotoPrefetchID: String {
        sortedVehicles
            .map { "\($0.id.uuidString):\($0.photoFileName ?? "")" }
            .joined(separator: "|")
    }

    private var pairingList: some View {
        List {
            Section {
                PairingShortcutsAutomationCard {
                    showShortcutsAutomationGuide = true
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            if locationService.authorizationState != .authorizedAlways {
                Section {
                    LocationAlwaysRequiredBanner()
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }

            if sortedVehicles.isEmpty {
                Section {
                    PairingEmptyState {
                        addFirstVehicle()
                    }
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 12, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            } else {
                Section(sortedVehicles.count == 1 ? L10n.pairingTabVehicleSection : L10n.pairingTabSavedVehicles) {
                    ForEach(Array(sortedVehicles.enumerated()), id: \.element.id) { index, vehicle in
                        vehicleRow(vehicle)
                            .glassRow(position: GlassRowPosition.index(index, in: sortedVehicles.count + 1))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    vehiclePendingDeleteID = vehicle.id
                                    showDeleteConfirmation = true
                                } label: {
                                    Label(L10n.delete, systemImage: "trash")
                                }
                                .destructiveTint()
                            }
                    }

                    Button(action: addVehiclePrompt) {
                        Label(L10n.pairingTabAddVehicle, systemImage: "plus.circle.fill")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 4)
                    }
                    .tint(TrailhoundBrandColors.brandBottom)
                    .glassRow(position: .last)
                }
            }
        }
        .listStyle(.insetGrouped)
        .glassListChrome()
        .navigationTitle(L10n.string("vehicles.tab.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                LocationPermissionBadge(state: locationService.authorizationState)
            }
            .hideSharedToolbarBackgroundIfAvailable()
        }
        .sheet(isPresented: $showShortcutsAutomationGuide) {
            PairingShortcutsAutomationGuideView()
        }
        .alert(L10n.pairingTabDeleteVehicleTitle, isPresented: $showDeleteConfirmation) {
            Button(L10n.delete, role: .destructive) {
                deletePendingVehicle()
            }
            Button(L10n.cancel, role: .cancel) {
                vehiclePendingDeleteID = nil
            }
        } message: {
            Text(L10n.pairingTabDeleteVehicleMessage)
        }
    }

    private func vehicleRow(_ vehicle: VehicleProfile) -> some View {
        PairingCardContainer {
            PairingVehicleRow(
                vehicle: vehicle,
                subtitle: vehicleSubtitle(vehicle),
                onOpen: { openDetail(for: vehicle.id) }
            )
            .padding(12)
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func vehicleSubtitle(_ vehicle: VehicleProfile) -> String {
        let vehicleSchedules = schedules.filter { $0.vehicle?.id == vehicle.id && $0.isEnabled }
        if let urgent = VehicleCareDueCalculator.dueItems(from: vehicleSchedules, urgentOnly: true).first {
            return VehicleCareDueCalculator.subtitle(for: urgent.state, title: urgent.title)
        }
        let consumption = String(format: "%.1f %@", vehicle.consumption, vehicle.consumptionLabel)
        return [vehicle.fuelType.displayName, consumption].joined(separator: " · ")
    }

    private func suggestedVehicleName() -> String {
        let base = L10n.vehicleDefaultName
        let existing = Set(vehicles.map(\.name))
        if !existing.contains(base) { return base }
        var index = 2
        while existing.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }

    private func openDetail(for vehicleID: UUID) {
        Task { @MainActor in
            await Task.yield()
            navigationPath.append(VehicleNavDestination.detail(vehicleID))
        }
    }

    private func consumePendingCareDeepLink() {
        guard let vehicleID = tabSelection.consumePendingVehicleCareID() else { return }
        openDetail(for: vehicleID)
    }

    private func addFirstVehicle() {
        let vehicle = VehicleProfile(
            name: suggestedVehicleName(),
            consumption: settings.fuelLitersPer100km
        )
        modelContext.insert(vehicle)
        guard (try? modelContext.save()) != nil else { return }
        VehiclePairingService.setDefaultVehicle(vehicle, in: modelContext)
        settings.skipCarSetup()
        openDetail(for: vehicle.id)
    }

    private func addVehiclePrompt() {
        let vehicle = VehicleProfile(
            name: suggestedVehicleName(),
            consumption: settings.fuelLitersPer100km
        )
        modelContext.insert(vehicle)
        guard (try? modelContext.save()) != nil else { return }
        openDetail(for: vehicle.id)
    }

    private func deletePendingVehicle() {
        guard let vehiclePendingDeleteID,
              let vehicle = vehicles.first(where: { $0.id == vehiclePendingDeleteID }) else {
            self.vehiclePendingDeleteID = nil
            return
        }

        if !navigationPath.isEmpty {
            navigationPath = NavigationPath()
        }

        if VehiclePairingService.deleteVehicle(vehicle, in: modelContext) {
            ToastPresenter.shared.show(.deleted)
        }
        self.vehiclePendingDeleteID = nil
    }
}

#Preview {
    PairingTabView()
        .modelContainer(PreviewData.shared.container)
        .environment(LocationService())
        .environment(PreviewData.shared.recordingService)
}
