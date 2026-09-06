import SwiftUI

struct StatsPeriodCompareRow: Identifiable {
    let id: String
    let title: String
    let currentText: String
    let previousText: String
    let trend: StatsTrend?
}

/// Period-over-period row model plus the trend badge.
/// The old spreadsheet strip lives on Stats hero / nested tiles now.
struct StatsPeriodCompareStrip: View {
    let currentLabel: String
    let previousLabel: String
    let rows: [StatsPeriodCompareRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(currentLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(previousLabel)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear
                    .frame(width: 56)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

            ForEach(rows) { row in
                compareRow(row)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    private func compareRow(_ row: StatsPeriodCompareRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(row.currentText)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.previousText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)

            StatsTrendBadge(trend: row.trend, metricName: row.title)
                .frame(width: 56, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: row))
    }

    private func accessibilityLabel(for row: StatsPeriodCompareRow) -> String {
        var parts = [
            row.title,
            "\(currentLabel) \(row.currentText)",
            "\(previousLabel) \(row.previousText)"
        ]
        if let trend = row.trend, let a11y = Optional(trend.accessibilityLabel(metricName: row.title)) {
            parts.append(a11y)
        }
        return parts.joined(separator: ", ")
    }
}

struct StatsTrendBadge: View {
    let trend: StatsTrend?
    var metricName: String = ""

    var body: some View {
        if let trend {
            HStack(spacing: 2) {
                if let systemImage = trend.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 8, weight: .bold))
                }
                if let text = trend.displayText {
                    Text(text)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(Self.color(for: trend))
            .accessibilityLabel(trend.accessibilityLabel(metricName: metricName))
        }
    }

    static func color(for trend: StatsTrend) -> Color {
        switch trend.isFavorable {
        case true: .green
        case false: .red
        case nil: .secondary
        }
    }
}
