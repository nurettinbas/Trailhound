import SwiftUI

struct PairingVehicleRow: View {
    let vehicle: VehicleProfile
    /// Fuel / consumption line when there is no urgent care item.
    let subtitle: String
    /// Urgent reminder title shown inside the due chip.
    var careTitle: String? = nil
    var careSystemImage: String? = nil
    var dueState: VehicleCareDueState? = nil
    var scheduleID: UUID? = nil
    let onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playEntrance = false

    private var band: VehicleCareUrgencyBand? {
        guard let dueState else { return nil }
        return VehicleCareUrgencyStyle.band(for: dueState)
    }

    private var chipText: String? {
        guard let dueState else { return nil }
        return VehicleCareUrgencyStyle.chipText(for: dueState)
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 12) {
                VehicleAvatarView(
                    systemImage: vehicle.systemImage,
                    photoFileName: vehicle.photoFileName,
                    size: 36,
                    cornerRadius: 8,
                    isElectricAccent: isElectricAccent,
                    showsPhotoShine: vehicle.photoFileName != nil
                )
                .id(vehicle.photoFileName ?? "none")

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(vehicle.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if vehicle.isDefault {
                            Text(L10n.pairingTabDefaultVehicle)
                                .font(.caption2.weight(.bold))
                                .glassAccentForeground()
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(TrailhoundBrandColors.brandBottom.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }

                    if let careTitle, let band, let chipText {
                        VehicleCareDueChip(
                            text: chipText,
                            band: band,
                            leadingSystemImage: careSystemImage,
                            title: careTitle,
                            playEntrance: playEntrance
                        )
                    } else {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear(perform: consumeEntranceIfNeeded)
    }

    private var isElectricAccent: Bool {
        vehicle.fuelType == .electric
    }

    private func consumeEntranceIfNeeded() {
        guard let scheduleID, let band, !reduceMotion else { return }
        playEntrance = VehicleCareUrgencyEntranceStore.consume(
            role: .chip,
            scheduleID: scheduleID,
            band: band
        )
    }
}
