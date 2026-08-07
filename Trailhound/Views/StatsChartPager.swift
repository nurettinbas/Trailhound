import SwiftUI

enum StatsChartPagerMetrics {
    /// Caption title + spacing + 200pt chart.
    static let dailyContentHeight: CGFloat = 236
    /// Title + donut + compact legend — keep close to intrinsic content so pages don’t look top-heavy.
    static let donutContentHeight: CGFloat = 228
    static let indicatorHeight: CGFloat = 20
    static let chevronSize: CGFloat = 28
}

/// Horizontal page slider for stacking similar stats charts in one list row.
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

    private var showsChrome: Bool {
        pageCount > 1
    }

    private var clampedSelection: Int {
        guard pageCount > 0 else { return 0 }
        return min(max(0, selection), pageCount - 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: selectionBinding) {
                ForEach(0..<pageCount, id: \.self) { index in
                    content(index)
                        .tag(index)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: contentHeight)
            .clipped()
            .animation(motionReduced ? nil : TrailhoundMotion.gentle, value: clampedSelection)
            .overlay {
                if showsChrome {
                    HStack {
                        pageChevron(systemName: "chevron.left", enabled: clampedSelection > 0) {
                            move(by: -1)
                        }
                        Spacer(minLength: 0)
                        pageChevron(systemName: "chevron.right", enabled: clampedSelection < pageCount - 1) {
                            move(by: 1)
                        }
                    }
                    // Sit near the visual center of the chart block (below title), not the empty footer.
                    .padding(.horizontal, 2)
                    .padding(.bottom, 24)
                }
            }

            if showsChrome {
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

    private var selectionBinding: Binding<Int> {
        Binding(
            get: { clampedSelection },
            set: { newValue in
                guard pageCount > 0 else {
                    selection = 0
                    return
                }
                selection = min(max(0, newValue), pageCount - 1)
            }
        )
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Circle()
                    .fill(index == clampedSelection ? Color.primary : Color.secondary.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityHidden(true)
    }

    private func pageChevron(
        systemName: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(enabled ? Color.secondary : Color.secondary.opacity(0.25))
                .frame(width: StatsChartPagerMetrics.chevronSize, height: StatsChartPagerMetrics.chevronSize)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .opacity(enabled ? 0.95 : 0.55)
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(
            L10n.string(
                systemName == "chevron.left"
                    ? "stats.chart.previous_a11y"
                    : "stats.chart.next_a11y"
            )
        )
    }

    private func move(by delta: Int) {
        let next = clampedSelection + delta
        guard next >= 0, next < pageCount else { return }
        if motionReduced {
            selection = next
        } else {
            withAnimation(TrailhoundMotion.gentle) {
                selection = next
            }
        }
    }
}
