import SwiftUI

/// Reserves chart layout, then mounts heavy Swift Charts content after the row appears.
struct StatsDeferredChart<Content: View>: View {
    let title: String
    let chartHeight: CGFloat
    var reduceMotion: Bool
    var isPageActive: Bool = true
    var titleAlignment: HorizontalAlignment = .leading
    @ViewBuilder let content: () -> Content

    @State private var isLoaded = false
    @State private var hasAppeared = false

    private var titleFrameAlignment: Alignment {
        titleAlignment == .center ? .center : .leading
    }

    private var titleTextAlignment: TextAlignment {
        titleAlignment == .center ? .center : .leading
    }

    var body: some View {
        VStack(alignment: titleAlignment, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(titleTextAlignment)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: titleFrameAlignment)

            if isLoaded {
                content()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .chartStatsAppearAnimation(reduceMotion: reduceMotion)
            } else {
                StatsChartSkeleton(height: chartHeight, reduceMotion: reduceMotion)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear {
            hasAppeared = true
            scheduleLoadIfNeeded()
        }
        .onDisappear {
            hasAppeared = false
        }
        .onChange(of: isPageActive) { _, _ in
            scheduleLoadIfNeeded()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func scheduleLoadIfNeeded() {
        guard hasAppeared, isPageActive, !isLoaded else { return }
        if reduceMotion {
            isLoaded = true
        } else {
            Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled, hasAppeared, isPageActive else { return }
                isLoaded = true
            }
        }
    }
}

/// Defers mounting a heavy chart block (e.g. donut + legend) without a separate title row.
struct StatsDeferredContent<Content: View>: View {
    let placeholderHeight: CGFloat
    var reduceMotion: Bool
    var isPageActive: Bool = true
    @ViewBuilder let content: () -> Content

    @State private var isLoaded = false
    @State private var hasAppeared = false

    var body: some View {
        Group {
            if isLoaded {
                content()
                    .chartStatsAppearAnimation(reduceMotion: reduceMotion)
            } else {
                StatsChartSkeleton(height: placeholderHeight, reduceMotion: reduceMotion)
            }
        }
        .onAppear {
            hasAppeared = true
            scheduleLoadIfNeeded()
        }
        .onDisappear {
            hasAppeared = false
        }
        .onChange(of: isPageActive) { _, _ in
            scheduleLoadIfNeeded()
        }
    }

    private func scheduleLoadIfNeeded() {
        guard hasAppeared, isPageActive, !isLoaded else { return }
        if reduceMotion {
            isLoaded = true
        } else {
            Task { @MainActor in
                await Task.yield()
                guard !Task.isCancelled, hasAppeared, isPageActive else { return }
                isLoaded = true
            }
        }
    }
}

struct StatsChartSkeleton: View {
    let height: CGFloat
    var reduceMotion: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var shimmerPhase = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(baseFill)
            .overlay {
                if !reduceMotion {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    TrailhoundBrandColors.brandBottom.opacity(colorScheme == .dark ? 0.12 : 0.08),
                                    Color.clear
                                ],
                                startPoint: shimmerPhase ? .trailing : .leading,
                                endPoint: shimmerPhase ? .init(x: 1.5, y: 0.5) : .init(x: 0.5, y: 0.5)
                            )
                        )
                }
            }
            .frame(height: height)
            .accessibilityHidden(true)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    shimmerPhase = true
                }
            }
    }

    private var baseFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.secondary.opacity(0.12)
    }
}
