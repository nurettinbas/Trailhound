import SwiftUI

struct StatsYearAwardsCard: View {
    let snapshot: StatsYearAwardsSnapshot?
    let medals: [StatsYearAward]
    let years: [Int]
    @Binding var selectedYear: Int
    var reduceMotion: Bool
    var onAppear: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("stats.awards.section"))
                        .font(.subheadline.weight(.semibold))
                    Text(L10n.string("stats.awards.unfiltered_hint"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    if let snapshot, snapshot.hasData {
                        Text(DateFormatters.formatDistance(snapshot.totalDistanceMeters))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(TrailhoundBrandColors.brandBottom)
                    }
                }
                Spacer()
                if years.count > 1 {
                    Picker(L10n.string("stats.awards.year"), selection: $selectedYear) {
                        ForEach(years, id: \.self) { year in
                            Text(String(year)).tag(year)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(TrailhoundBrandColors.brandBottom)
                    .labelsHidden()
                    .accessibilityLabel(L10n.string("stats.awards.year"))
                    .accessibilityValue(String(selectedYear))
                } else {
                    Text(String(selectedYear))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if snapshot == nil {
                StatsChartSkeleton(height: 168, reduceMotion: reduceMotion)
            } else if let snapshot, !snapshot.hasData {
                Text(L10n.string("stats.awards.empty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
            ForEach(Array(medals.prefix(3))) { medal in
                            medalCell(medal)
                        }
                    }
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(medals.dropFirst(3))) { medal in
                            medalCell(medal)
                        }
                    }
                }
            }
        }
        .onAppear(perform: onAppear)
    }

    private func medalCell(_ medal: StatsYearAward) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(medal.kind.badgeFill(unlocked: medal.isUnlocked))
                    .frame(width: 52, height: 52)
                Image(systemName: medal.isUnlocked ? medal.systemImage : "lock.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(medal.isUnlocked ? Color.white : medal.kind.badgeAccent)
            }
            Text(medal.title)
                .font(.system(size: 10, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(medal.detail)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .opacity(medal.isUnlocked ? 1 : 0.78)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(medal.title), \(medal.isUnlocked ? medal.detail : L10n.string("stats.awards.locked"))")
    }
}

private extension StatsYearAwardKind {
    var badgeAccent: Color {
        switch self {
        case .distance: TrailhoundBrandColors.brandBottom
        case .nightOwl: Color(red: 0.52, green: 0.42, blue: 0.98)
        case .goal: Color(red: 0.18, green: 0.72, blue: 0.54)
        case .busiestDay: Color(red: 0.96, green: 0.58, blue: 0.16)
        case .expensiveVehicle: Color(red: 0.92, green: 0.36, blue: 0.52)
        case .expensiveMonth: Color(red: 0.22, green: 0.74, blue: 0.86)
        }
    }

    var badgeHighlight: Color {
        switch self {
        case .distance: TrailhoundBrandColors.brandTop
        case .nightOwl: Color(red: 0.72, green: 0.58, blue: 1.0)
        case .goal: Color(red: 0.42, green: 0.90, blue: 0.68)
        case .busiestDay: Color(red: 1.0, green: 0.80, blue: 0.36)
        case .expensiveVehicle: Color(red: 1.0, green: 0.58, blue: 0.68)
        case .expensiveMonth: Color(red: 0.48, green: 0.90, blue: 0.96)
        }
    }

    func badgeFill(unlocked: Bool) -> LinearGradient {
        if unlocked {
            return LinearGradient(
                colors: [badgeHighlight, badgeAccent],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                badgeHighlight.opacity(0.28),
                badgeAccent.opacity(0.16)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
