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
            : Color.white.opacity(0.42)
    }
}

extension View {
    /// Full-width Stats card in a clear List row — one Material, no list-row glass behind it.
    func statsFullCard(contentInset: CGFloat = StatsCardTokens.contentInset) -> some View {
        glassCard(
            cornerRadius: StatsCardTokens.radius,
            contentInset: contentInset
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
