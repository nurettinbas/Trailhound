import SwiftUI

struct StatsAchievementsStrip: View {
    let achievements: [AchievementDisplay]
    var onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                Text(L10n.string("premium.achievements.title"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                if achievements.isEmpty {
                    Text(L10n.string("premium.achievements.empty"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(visible) { item in
                                AchievementBadgeView(item: item, compact: true)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("stats.premium.achievements")
    }

    private var visible: [AchievementDisplay] {
        let unlocked = achievements.filter(\.isUnlocked)
        if let next = achievements.first(where: { !$0.isUnlocked }) {
            return Array(unlocked.prefix(6)) + [next]
        }
        return Array(unlocked.prefix(8))
    }
}

struct AchievementBadgeView: View {
    let item: AchievementDisplay
    var compact: Bool = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        item.isUnlocked
                            ? TrailhoundBrandColors.brandBottom.opacity(0.18)
                            : Color.secondary.opacity(0.10)
                    )
                    .frame(width: compact ? 44 : 64, height: compact ? 44 : 64)
                Image(systemName: item.id.systemImage)
                    .font(compact ? .body.weight(.semibold) : .title3.weight(.semibold))
                    .foregroundStyle(item.isUnlocked ? TrailhoundBrandColors.brandBottom : Color.secondary)
            }
            if !compact {
                Text(L10n.string(item.id.titleKey))
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(item.isUnlocked ? .primary : .secondary)
                if !item.isUnlocked {
                    Text("\(Int(item.currentValue.rounded())) / \(Int(item.threshold.rounded()))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: compact ? 48 : 96)
        .opacity(item.isUnlocked ? 1 : 0.55)
        .accessibilityLabel(L10n.string(item.id.titleKey))
    }
}

struct AchievementGalleryView: View {
    let achievements: [AchievementDisplay]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 16) {
                    ForEach(achievements) { item in
                        VStack(spacing: 8) {
                            AchievementBadgeView(item: item, compact: false)
                            Text(L10n.string(item.id.bodyKey))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            if let unlockedAt = item.unlockedAt {
                                Text(unlockedAt.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            ShareLink(item: L10n.string(item.id.titleKey)) {
                                Label(L10n.string("action.share"), systemImage: "square.and.arrow.up")
                                    .font(.caption2)
                            }
                        }
                        .padding(12)
                        .glassCard(cornerRadius: 18, contentInset: 0)
                    }
                }
                .padding(16)
            }
            .background(AtmosphericBackground())
            .navigationTitle(L10n.string("premium.achievements.title"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct AchievementUnlockOverlay: View {
    let item: AchievementDisplay
    var onDismiss: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 0.86

    var body: some View {
        VStack(spacing: 14) {
            AchievementBadgeView(item: item, compact: false)
            Text(L10n.string("premium.achievements.unlocked"))
                .font(.headline)
            Text(L10n.string(item.id.titleKey))
                .font(.subheadline.weight(.semibold))
        }
        .padding(28)
        .glassCard(cornerRadius: 22, contentInset: 0)
        .scaleEffect(scale)
        .onAppear {
            TrailhoundHaptics.badgeUnlocked()
            withAnimation(TrailhoundMotion.badgeUnlock(reduceMotion: reduceMotion)) {
                scale = 1
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(reduceMotion ? 0.8 : 1.8))
                onDismiss()
            }
        }
        .accessibilityIdentifier("stats.premium.achievement.unlock")
    }
}
