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

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(side <= 18 ? .system(size: 12, weight: .medium) : .body)
                .foregroundStyle(.secondary)
                .frame(width: side, height: side)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .sheet(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(accessibilityLabel)
                        .font(.headline)
                    Spacer(minLength: 8)
                    Button(L10n.ok) { isPresented = false }
                        .fontWeight(.semibold)
                }
                Text(message)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(20)
            .presentationDetents([.height(240)])
            .presentationDragIndicator(.visible)
        }
    }
}
