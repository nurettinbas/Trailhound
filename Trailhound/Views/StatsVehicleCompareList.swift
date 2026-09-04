import SwiftUI

/// Ranked vehicle expense list. Capsule bars only — no Swift Charts.
struct StatsVehicleCompareList: View {
    let rows: [VehicleCompareRow]
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string("stats.compare.vehicles_title"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(rows) { row in
                vehicleRow(row)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private func vehicleRow(_ row: VehicleCompareRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 10) {
                VehicleAvatarView(
                    systemImage: row.iconName,
                    photoFileName: row.photoFileName,
                    size: 28,
                    cornerRadius: 7,
                    isElectricAccent: row.isElectric,
                    showsBrandRing: row.isMostExpensive
                )

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(row.displayName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        if row.isMostExpensive {
                            Text(L10n.string("stats.compare.most_expensive"))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(TrailhoundBrandColors.brandBottom)
                                .lineLimit(1)
                        }
                    }
                    HStack(spacing: 8) {
                        Text(FuelCostCalculator.formatCost(row.amount, currencyCode: currencyCode))
                            .font(.caption.weight(.semibold))
                        Text(costPerKmText(row))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            bucketBar(for: row)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: row))
    }

    private func costPerKmText(_ row: VehicleCompareRow) -> String {
        guard let costPerKm = row.costPerKm else {
            return L10n.string("stats.compare.cost_per_km_empty")
        }
        let formatted = FuelCostCalculator.formatCost(costPerKm, currencyCode: currencyCode)
        return String(format: L10n.string("stats.compare.cost_per_km"), formatted)
    }

    private func bucketBar(for row: VehicleCompareRow) -> some View {
        GeometryReader { geo in
            let total = max(row.amount, 0.0001)
            HStack(spacing: 1) {
                ForEach(VehicleCostBucket.allCases, id: \.rawValue) { bucket in
                    let amount = row.amount(for: bucket)
                    if amount > 0 {
                        Capsule()
                            .fill(StatsChartTheme.bucketColor(for: bucket))
                            .frame(width: max(geo.size.width * CGFloat(amount / total), 2))
                    }
                }
            }
        }
        .frame(height: 5)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private func accessibilityLabel(for row: VehicleCompareRow) -> String {
        var parts = [
            row.displayName,
            FuelCostCalculator.formatCost(row.amount, currencyCode: currencyCode),
            costPerKmText(row)
        ]
        if row.isMostExpensive {
            parts.append(L10n.string("stats.compare.most_expensive"))
        }
        return parts.joined(separator: ", ")
    }
}
