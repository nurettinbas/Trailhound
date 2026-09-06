import SwiftUI

/// One chrome for every Stats surface: half-span siblings, full-width cards, nested tiles.
/// Nested tiles are fills — never a second `Material` blur.
enum StatsCardTokens {
    static let radius: CGFloat = GlassTokens.cardRadius
    static let nestedRadius: CGFloat = 12
    static let pairSpacing: CGFloat = 12
    static let contentInset: CGFloat = 14
    static let summaryGridInset: CGFloat = 8
    static let halfMinHeight: CGFloat = 188
    static let listRowVerticalInset: CGFloat = 6
    /// Title + value/trend + previous line, no leftover empty band.
    static let nestedTileHeight: CGFloat = 64
    static let nestedTileTitleRowHeight: CGFloat = 16
    static let nestedTilePreviousLineHeight: CGFloat = 13
}

private struct StatsNestedTileModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(
                maxWidth: .infinity,
                minHeight: StatsCardTokens.nestedTileHeight,
                maxHeight: StatsCardTokens.nestedTileHeight,
                alignment: .topLeading
            )
            .background {
                RoundedRectangle(cornerRadius: StatsCardTokens.nestedRadius, style: .continuous)
                    .fill(tileFill)
            }
    }

    private var tileFill: Color {
        if reduceTransparency {
            return Color(.tertiarySystemFill)
        }
        return colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.white.opacity(0.16)
    }
}

extension View {
    /// Full-width Stats card in a clear List row — one Material, no list-row glass behind it.
    func statsFullCard(contentInset: CGFloat = StatsCardTokens.contentInset, frozen: Bool = false) -> some View {
        glassCard(
            cornerRadius: StatsCardTokens.radius,
            contentInset: contentInset,
            frozen: frozen
        )
        .statsCardListRow()
    }

    /// Half of a 2-up pair. Fixed minHeight — no GeometryReader in the List row.
    func statsHalfCard() -> some View {
        glassCard(
            cornerRadius: StatsCardTokens.radius,
            contentInset: StatsCardTokens.contentInset
        )
        .frame(
            maxWidth: .infinity,
            minHeight: StatsCardTokens.halfMinHeight,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    func statsCardListRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(
                EdgeInsets(
                    top: StatsCardTokens.listRowVerticalInset,
                    leading: GlassTokens.panelHorizontalInset,
                    bottom: StatsCardTokens.listRowVerticalInset,
                    trailing: GlassTokens.panelHorizontalInset
                )
            )
    }

    /// Frost fill inside a Stats card. Not `ultraThinMaterial`.
    func statsNestedTile() -> some View {
        modifier(StatsNestedTileModifier())
    }
}

struct StatsCardPair<Left: View, Right: View>: View {
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    var body: some View {
        HStack(alignment: .top, spacing: StatsCardTokens.pairSpacing) {
            left()
                .statsHalfCard()
            right()
                .statsHalfCard()
        }
        .frame(minHeight: StatsCardTokens.halfMinHeight)
        .statsCardListRow()
    }
}

/// Placeholder nested tile so the summary grid stays packed while a snapshot loads.
struct StatsSummaryTileSkeleton: View {
    var reduceMotion: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var shimmerPhase = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule()
                .fill(barFill)
                .frame(width: 76, height: 7)
            Capsule()
                .fill(barFill)
                .frame(width: 52, height: 11)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .statsNestedTile()
        .overlay {
            if !reduceMotion {
                RoundedRectangle(cornerRadius: StatsCardTokens.nestedRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                TrailhoundBrandColors.brandBottom.opacity(colorScheme == .dark ? 0.14 : 0.10),
                                Color.clear
                            ],
                            startPoint: shimmerPhase ? .trailing : .leading,
                            endPoint: shimmerPhase ? UnitPoint(x: 1.4, y: 0.5) : UnitPoint(x: 0.4, y: 0.5)
                        )
                    )
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: StatsCardTokens.nestedRadius, style: .continuous))
        .accessibilityHidden(true)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                shimmerPhase = true
            }
        }
    }

    private var barFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.white.opacity(0.55)
    }
}
