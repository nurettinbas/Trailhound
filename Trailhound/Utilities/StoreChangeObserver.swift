import SwiftData
import SwiftUI

extension View {
    /// Runs `action` whenever any `ModelContext` saves, for views that keep their own fetched
    /// arrays instead of a `@Query` and so have to reload themselves.
    ///
    /// `ModelContext.didSave` is delivered on whichever thread performed the save. Background
    /// workers such as `TripDerivedBackfiller` and `TripRollupRebuilder` save from their own
    /// `@ModelActor`, so the handler is hopped to the main thread when it did not start there —
    /// otherwise it mutates SwiftUI state off the main thread.
    ///
    /// Saves that already happen on the main thread run `action` synchronously rather than hopping.
    /// A deletion has to be reflected before the next body pass: rendering a row that still points
    /// at a deleted model is a crash, not a glitch.
    func onStoreSave(perform action: @escaping @Sendable @MainActor () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { _ in
            if Thread.isMainThread {
                MainActor.assumeIsolated(action)
            } else {
                DispatchQueue.main.async(execute: action)
            }
        }
    }
}
