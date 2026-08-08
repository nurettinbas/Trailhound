import Charts
import SwiftUI

struct VehicleCostDonutChart: View {
    let snapshot: VehicleCostSnapshot
    let currencyCode: String

    private struct Slice: Identifiable {
        let id: VehicleCostBucket
        let name: String
        let amount: Double
    }

    private var slices: [Slice] {
        let candidates: [(VehicleCostBucket, Double)] = [
            (.fuel, snapshot.fuelTotal),
            (.service, snapshot.serviceTotal),
            (.insurance, snapshot.insuranceTotal),
            (.casco, snapshot.cascoTotal),
            (.other, snapshot.otherTotal)
        ]
        return candidates.compactMap { bucket, amount in
            guard amount > 0 else { return nil }
            return Slice(id: bucket, name: bucket.displayName, amount: amount)
        }
    }

    var body: some View {
        if slices.isEmpty {
            Text(L10n.string("vehicles.care.chart.empty"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            VStack(spacing: 10) {
                ZStack {
                    Chart(slices) { slice in
                        SectorMark(
                            angle: .value("Amount", slice.amount),
                            innerRadius: .ratio(StatsChartTheme.donutInnerRadius),
                            angularInset: StatsChartTheme.donutAngularInset
                        )
                        .foregroundStyle(StatsChartTheme.bucketColor(for: slice.id))
                    }
                    .chartLegend(.hidden)
                    .statsChartCardLayout()
                    .frame(height: 150)

                    VStack(spacing: 2) {
                        Text(FuelCostCalculator.formatCost(snapshot.total, currencyCode: currencyCode))
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(L10n.string("stats.cost.chart.center_total"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                }

                VStack(spacing: 5) {
                    ForEach(slices) { slice in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle()
                                .fill(StatsChartTheme.bucketColor(for: slice.id))
                                .frame(
                                    width: StatsChartTheme.legendDotSize,
                                    height: StatsChartTheme.legendDotSize
                                )
                                .alignmentGuide(.firstTextBaseline) { dims in dims[VerticalAlignment.center] }
                            Text(slice.name)
                                .font(.caption2)
                                .lineLimit(1)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Text(FuelCostCalculator.formatCost(slice.amount, currencyCode: currencyCode))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 1)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
