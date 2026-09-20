import SwiftUI

struct RecordToastView: View {
    let payload: PersonalRecordBreak

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    @State private var settled = false
    @State private var valuesVisible = false
    @State private var iconBounceToken = 0
    @State private var glintID = "record.toast"

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            medalDisc
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.toastRecordKicker)
                    .font(.caption2.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(GlassText.secondary(for: colorScheme))
                    .opacity(settled ? 1 : 0.55)
                valueLines
                    .opacity(valuesVisible ? 1 : 0)
                    .offset(y: valuesVisible || reduceMotion ? 0 : 4)
            }
            .frame(maxWidth: 260, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .fixedSize()
        .glassChrome(cornerRadius: GlassTokens.chipRadius)
        .glassEntranceGlint(
            cornerRadius: GlassTokens.chipRadius,
            id: glintID,
            isEnabled: !reduceMotion && !UITestSupport.isEnabled
        )
        .shadow(
            color: .black.opacity(settled ? 0.16 : 0.05),
            radius: settled ? 16 : 6,
            y: settled ? 6 : 2
        )
        .scaleEffect(settled ? 1 : 0.96)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .accessibilityLabel(payload.accessibilityMessage)
        .onAppear(perform: playEntrance)
        .onChange(of: payload) { _, _ in
            playEntrance()
        }
    }

    @ViewBuilder
    private var valueLines: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let longest = payload.longestText {
                Text(L10n.toastRecordLongest(longest))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GlassText.primary(for: colorScheme))
                    .lineLimit(1)
            }
            if let fastest = payload.fastestText {
                Text(L10n.toastRecordFastest(fastest))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(GlassText.primary(for: colorScheme))
                    .lineLimit(1)
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var medalDisc: some View {
        ZStack {
            Circle()
                .fill(discFill)
            Circle()
                .strokeBorder(.white.opacity(0.42), lineWidth: 1)
            Image(systemName: discSymbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: iconBounceToken)
        }
        .frame(width: 28, height: 28)
        .scaleEffect(settled ? 1 : 0.72)
        .shadow(color: discGlow.opacity(settled ? 0.55 : 0.12), radius: settled ? 8 : 2, y: 1)
        .accessibilityHidden(true)
    }

    private var discSymbol: String {
        if payload.longestDistanceMeters != nil, payload.fastestCruiseKmh != nil {
            "trophy.fill"
        } else if payload.fastestCruiseKmh != nil {
            "gauge.with.dots.needle.67percent"
        } else {
            "flag.checkered"
        }
    }

    private var usesGoldDisc: Bool {
        payload.longestDistanceMeters != nil
    }

    private var discFill: LinearGradient {
        if usesGoldDisc {
            let dark = colorScheme == .dark
            return LinearGradient(
                colors: [
                    AchievementTheme.hex(dark ? 0xD4A84A : 0xF3D08A),
                    AchievementTheme.hex(dark ? 0x9A6A12 : 0xC48A1A)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        let tint = shellPalette.tintColor(for: colorScheme)
        return LinearGradient(
            colors: [tint.opacity(0.95), tint.opacity(0.72)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var discGlow: Color {
        if usesGoldDisc {
            AchievementTheme.hex(colorScheme == .dark ? 0xD4A84A : 0xF3D08A)
        } else {
            shellPalette.tintColor(for: colorScheme)
        }
    }

    private func playEntrance() {
        if reduceMotion || UITestSupport.isEnabled {
            settled = true
            valuesVisible = true
            return
        }
        settled = false
        valuesVisible = false
        glintID = "record.toast.\(UUID().uuidString)"
        withAnimation(TrailhoundMotion.pinPop) {
            settled = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            iconBounceToken += 1
            try? await Task.sleep(for: .milliseconds(70))
            withAnimation(TrailhoundMotion.snappy) {
                valuesVisible = true
            }
        }
    }
}
