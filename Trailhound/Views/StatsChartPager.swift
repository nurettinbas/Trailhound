import SwiftUI

enum StatsChartPagerMetrics {
    /// Caption title + spacing + 200pt chart.
    static let dailyContentHeight: CGFloat = 236
    /// Title + donut + legend gap + up to 2 centered legend rows.
    static let donutContentHeight: CGFloat = 268
    /// Cost pager: title + chart + optional legend.
    static let costContentHeight: CGFloat = 260
    static let indicatorHeight: CGFloat = 20
}

/// Horizontal page slider for stacking similar stats charts in one list row.
/// Swipe only — no chevrons. Page dots remain when there is more than one chart.
struct StatsChartPager<Content: View>: View {
    let pageCount: Int
    let contentHeight: CGFloat
    @Binding var selection: Int
    var reduceMotion: Bool
    @ViewBuilder var content: (Int) -> Content

    @Environment(\.accessibilityReduceMotion) private var environmentReduceMotion

    private var motionReduced: Bool {
        reduceMotion || environmentReduceMotion
    }

    private var showsPageIndicator: Bool {
        pageCount > 1
    }

    private var clampedSelection: Int {
        guard pageCount > 0 else { return 0 }
        return min(max(0, selection), pageCount - 1)
    }

    private var scrollPosition: Binding<Int?> {
        Binding(
            get: { pageCount > 0 ? clampedSelection : nil },
            set: { newValue in
                guard pageCount > 0, let newValue else { return }
                let next = min(max(0, newValue), pageCount - 1)
                guard next != selection else { return }
                selection = next
            }
        )
    }

    var body: some View {
        if pageCount <= 0 {
            EmptyView()
        } else {
            pagerBody
        }
    }

    private var pagerBody: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        content(index)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                            .containerRelativeFrame(.horizontal)
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: scrollPosition)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: contentHeight)
            .clipped()

            if showsPageIndicator {
                pageIndicator
                    .frame(height: StatsChartPagerMetrics.indicatorHeight)
            }
        }
        .onChange(of: pageCount) { _, newCount in
            guard newCount > 0 else {
                selection = 0
                return
            }
            if selection >= newCount {
                selection = newCount - 1
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            String(
                format: L10n.string("stats.chart.page_a11y"),
                clampedSelection + 1,
                max(pageCount, 1)
            )
        )
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(
                        index == clampedSelection
                            ? TrailhoundBrandColors.brandBottom
                            : Color.secondary.opacity(0.25)
                    )
                    .frame(width: index == clampedSelection ? 18 : 8, height: 8)
                    .animation(motionReduced ? nil : TrailhoundMotion.snappy, value: clampedSelection)
            }
        }
        .accessibilityHidden(true)
    }
}
