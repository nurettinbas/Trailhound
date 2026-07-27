import SwiftUI

struct PairingVehicleRow: View {
    let vehicle: VehicleProfile
    let subtitle: String
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 12) {
                vehicleIcon

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(vehicle.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if vehicle.isDefault {
                            Text(L10n.pairingTabDefaultVehicle)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(TrailhoundBrandColors.brandBottom)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(TrailhoundBrandColors.brandBottom.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var vehicleIcon: some View {
        let isElectricAccent = vehicle.fuelType == .electric
            || vehicle.systemImage == VehicleIconOption.electric.rawValue
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isElectricAccent
                    ? Color.yellow.opacity(0.15)
                    : TrailhoundBrandColors.brandBottom.opacity(0.12))
                .frame(width: 36, height: 36)
            Image(systemName: vehicle.systemImage)
                .font(.body)
                .foregroundStyle(isElectricAccent ? .yellow : TrailhoundBrandColors.brandBottom)
        }
    }
}
