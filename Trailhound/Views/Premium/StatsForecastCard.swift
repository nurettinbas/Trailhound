import Charts
import SwiftUI

struct StatsForecastCard: View {
    let forecast: MonthCostForecast
    let currencyCode: String
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("premium.forecast.title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(FuelCostCalculator.formatCost(forecast.projectedTotal, currencyCode: currencyCode))
                    .font(.title.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                Text(L10n.string("premium.forecast.subtitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if let ratio = forecast.trendRatio {
                        Label(
                            trendText(ratio),
                            systemImage: ratio >= 0 ? "arrow.up.right" : "arrow.down.right"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ratio >= 0 ? Color.orange : Color.green)
                    }
                    Text(confidenceText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if !forecast.monthlyTotals.isEmpty {
                    Chart(forecast.monthlyTotals) { month in
                        BarMark(
                            x: .value("m", month.monthStart, unit: .month),
                            y: .value("c", month.total)
                        )
                        .foregroundStyle(TrailhoundBrandColors.brandBottom.opacity(0.85))
                        .cornerRadius(3)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: 36)
                    .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("stats.premium.forecast")
        .accessibilityLabel(L10n.string("premium.forecast.title"))
        .accessibilityValue(FuelCostCalculator.formatCost(forecast.projectedTotal, currencyCode: currencyCode))
    }

    private var confidenceText: String {
        switch forecast.confidence {
        case .low: L10n.string("premium.forecast.confidence.low")
        case .medium: L10n.string("premium.forecast.confidence.medium")
        case .high: L10n.string("premium.forecast.confidence.high")
        }
    }

    private func trendText(_ ratio: Double) -> String {
        let percent = Int((abs(ratio) * 100).rounded())
        let format = ratio >= 0
            ? L10n.string("premium.forecast.trend.up")
            : L10n.string("premium.forecast.trend.down")
        return String(format: format, percent)
    }
}

struct StatsForecastDetailSheet: View {
    let forecast: MonthCostForecast
    let currencyCode: String

    var body: some View {
        NavigationStack {
            List {
                Section {
                    detailRow(L10n.string("premium.forecast.row.drive"), forecast.projectedFuel)
                    detailRow(L10n.string("premium.forecast.row.installments"), forecast.installmentsDue)
                    detailRow(L10n.string("premium.forecast.row.other"), forecast.otherExpenses)
                    detailRow(L10n.string("premium.forecast.row.logged_fuel"), forecast.loggedFuel)
                }
            }
            .glassListChrome()
            .navigationTitle(L10n.string("premium.forecast.detail.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    private func detailRow(_ title: String, _ amount: Double) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(amount > 0 ? FuelCostCalculator.formatCost(amount, currencyCode: currencyCode) : "—")
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .glassListRow()
    }
}
