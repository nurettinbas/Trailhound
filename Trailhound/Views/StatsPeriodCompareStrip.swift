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

    @Environment(\.colorScheme) private var colorScheme

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
            .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
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
                    .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
                    .lineLimit(1)
                Text(row.currentText)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(row.previousText)
                .font(.caption)
                .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
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

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

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
            .foregroundStyle(
                trend.isNovel
                    ? novelChipInk
                    : Self.color(for: trend, colorScheme: colorScheme)
            )
            .padding(.horizontal, trend.isNovel ? 6 : 0)
            .padding(.vertical, trend.isNovel ? 3 : 0)
            .background {
                if trend.isNovel {
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    novelChipFill,
                                    novelChipFill.opacity(0.82)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(
                                    Color.white.opacity(colorScheme == .dark ? 0.28 : 0.42),
                                    lineWidth: 0.75
                                )
                        }
                }
            }
            .shadow(
                color: trend.isNovel ? Color.black.opacity(colorScheme == .dark ? 0.28 : 0.18) : .clear,
                radius: trend.isNovel ? 2 : 0,
                y: trend.isNovel ? 1 : 0
            )
            .accessibilityLabel(trend.accessibilityLabel(metricName: metricName))
        }
    }

    private var novelChipRGB: ShellRGB {
        colorScheme == .dark
            ? shellPalette.atmosphere(for: .dark).tint
            : shellPalette.atmosphere(for: .light).chrome
    }

    private var novelChipFill: Color {
        novelChipRGB.color
    }

    private var novelChipInk: Color {
        novelChipRGB.relativeLuminance > 0.56
            ? Color.black.opacity(0.82)
            : Color.white
    }

    static func color(for trend: StatsTrend, colorScheme: ColorScheme) -> Color {
        switch trend.isFavorable {
        case true: .green
        case false: .red
        case nil: StatsTextColor.secondary(for: colorScheme)
        }
    }
}
