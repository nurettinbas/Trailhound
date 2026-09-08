import SwiftUI

struct YearRecapHubCard: View {
    let snapshot: YearRecapSnapshot
    var onPlay: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var usesOverlay: Bool {
        snapshot.hasData && !dynamicTypeSize.isAccessibilitySize
    }

    private var pulsePlay: Bool {
        !reduceMotion && !UITestSupport.isEnabled
    }

    var body: some View {
        Group {
            if snapshot.hasData {
                Button(action: onPlay) {
                    Group {
                        if usesOverlay {
                            overlayPoster
                        } else {
                            stackedContent(allowsIdleMotion: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.trailhoundCardPress)
                .glassEntranceGlint(cornerRadius: StatsCardTokens.radius, id: "stats.premium.recap")
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("stats.premium.recap.play")
                .accessibilityLabel(L10n.string("premium.recap.play"))
                .accessibilityValue(DateFormatters.formatDistance(snapshot.distanceMeters))
            } else {
                stackedContent(allowsIdleMotion: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("stats.premium.recap")
    }

    private var overlayPoster: some View {
        ZStack {
            RecapHubTeaserScene(
                height: RecapHubTeaserMetrics.posterHeight,
                allowsIdleMotion: true,
                cornerRadius: StatsCardTokens.radius
            )
            LinearGradient(
                colors: [
                    shellPalette.atmosphere(for: colorScheme).bottom.color.opacity(0.92),
                    shellPalette.atmosphere(for: colorScheme).bottom.color.opacity(0)
                ],
                startPoint: .bottom,
                endPoint: .center
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 0) {
                yearChip
                Spacer(minLength: 0)
                HStack(alignment: .bottom, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        distanceText
                        metricsLine
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    playChip
                        .layoutPriority(1)
                }
            }
            .statsPosterOverlayPadding()
        }
        .clipShape(RoundedRectangle(cornerRadius: StatsCardTokens.radius, style: .continuous))
    }

    private func stackedContent(allowsIdleMotion: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            RecapHubTeaserScene(
                height: snapshot.hasData
                    ? RecapHubTeaserMetrics.stackedHeight
                    : RecapHubTeaserMetrics.emptyHeight,
                allowsIdleMotion: allowsIdleMotion
            )
            yearChip
            if snapshot.hasData {
                distanceText
                metricsLine
                playChip
            } else {
                Text(L10n.string("premium.recap.empty"))
                    .font(.caption)
                    .foregroundStyle(StatsTextColor.tertiary(for: colorScheme))
            }
        }
        .padding(StatsCardTokens.contentInset)
    }

    private var yearChip: some View {
        Text(String(format: L10n.string("premium.recap.year_title"), snapshot.year))
            .font(.caption.weight(.semibold))
            .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
            .statsFrostChip()
    }

    private var distanceText: some View {
        Text(DateFormatters.formatDistance(snapshot.distanceMeters))
            .font(.title.weight(.bold).monospacedDigit())
            .glassAccentForeground()
            .minimumScaleFactor(0.7)
            .lineLimit(1)
    }

    private var metricsLine: some View {
        HStack(spacing: 6) {
            Text(String(snapshot.tripCount))
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(L10n.string("premium.recap.trips"))
            if snapshot.cityCount > 0 {
                Text("·")
                Text("\(snapshot.cityCount)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text(L10n.string("premium.recap.cities"))
            }
        }
        .font(.caption)
        .foregroundStyle(StatsTextColor.secondary(for: colorScheme))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var playChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "play.fill")
                .symbolEffect(.pulse, options: .repeating, isActive: pulsePlay)
            Text(L10n.string("premium.recap.play"))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .trailhoundCompactProminentButton()
        .layoutPriority(1)
        .accessibilityHidden(true)
    }
}
