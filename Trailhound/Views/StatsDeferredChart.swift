import SwiftUI

/// Reserves chart layout, then mounts heavy Swift Charts content after the row appears.
struct StatsDeferredChart<Content: View>: View {
    let title: String
    let chartHeight: CGFloat
    var reduceMotion: Bool
    @ViewBuilder let content: () -> Content

    @State private var isLoaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            if isLoaded {
                content()
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: chartHeight)
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            guard !isLoaded else { return }
            if reduceMotion {
                isLoaded = true
            } else {
                Task { @MainActor in
                    await Task.yield()
                    isLoaded = true
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// Defers mounting a heavy chart block (e.g. donut + legend) without a separate title row.
struct StatsDeferredContent<Content: View>: View {
    let placeholderHeight: CGFloat
    var reduceMotion: Bool
    @ViewBuilder let content: () -> Content

    @State private var isLoaded = false

    var body: some View {
        Group {
            if isLoaded {
                content()
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: placeholderHeight)
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            guard !isLoaded else { return }
            if reduceMotion {
                isLoaded = true
            } else {
                Task { @MainActor in
                    await Task.yield()
                    isLoaded = true
                }
            }
        }
    }
}
