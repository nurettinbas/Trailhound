import CoreGraphics

/// Global frame of the live recording card (for stop credits morph).
struct RecordingCardAnchor: Equatable {
    var minX: CGFloat = 0
    var minY: CGFloat = 0
    var width: CGFloat = 0
}

/// Holds the anchor outside SwiftUI's dependency graph.
///
/// The frame is only read when Stop is pressed, but keeping it in `@State` meant every scroll
/// frame moved the card far enough to write it, rebuilding the whole card each frame.
@MainActor
final class RecordingCardAnchorBox {
    var value = RecordingCardAnchor()
}
