import SwiftUI

/// Compact `?` that opens a short explanation. Hit target ≥ 44 pt for accessibility.
///
/// Presented as a sheet so the full message is never clipped (iPhone popover bubbles
/// often truncate long footnote text with an ellipsis).
struct HelpPopoverButton: View {
    let accessibilityLabel: String
    let message: String
    /// Layout side of the `?` control. Default 44 pt for accessibility; metric cards pass 16.
    var side: CGFloat = 44
    /// Sheet height. Longer copy (travel help) passes a taller detent so the text is not clipped.
    var sheetHeight: CGFloat = 240

    @State private var isPresented = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(side <= 18 ? .system(size: 12, weight: .medium) : .body)
                .foregroundStyle(GlassText.secondary(for: colorScheme))
                .frame(width: side, height: side)
                .contentShape(Rectangle())
        }
        .buttonStyle(.glassPlainHit)
        .accessibilityLabel(accessibilityLabel)
        .sheet(isPresented: $isPresented) {
            helpCard
                .presentationBackground {
                    AtmosphericBackground(style: .full)
                }
                .onGlassShell()
                .modifier(HelpPopoverSheetSizing(fallbackHeight: sheetHeight))
        }
    }

    /// Width follows the copy. OK sits in the top trailing corner, not in the title row.
    private var helpCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(accessibilityLabel)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.trailing, 56)
            Text(message)
                .font(.body)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
        .fixedSize(horizontal: true, vertical: true)
        .overlay(alignment: .topTrailing) {
            Button(L10n.ok) { isPresented = false }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.glassPlainHit)
                .padding(8)
        }
    }
}

/// Fitted sheet on iOS 18 so the card is only as wide as the text. Older systems keep a height detent.
private struct HelpPopoverSheetSizing: ViewModifier {
    var fallbackHeight: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .presentationSizing(.fitted)
                .presentationDragIndicator(.visible)
        } else {
            content
                .presentationDetents([.height(fallbackHeight), .medium])
                .presentationDragIndicator(.visible)
        }
    }
}
