import Foundation
import os

/// Instruments the aggregation paths that historically blocked the main thread.
/// Profile with Instruments → os_signpost, subsystem `com.trailhound.app`, category `Performance`.
enum PerformanceSignposts {
    static let signposter = OSSignposter(
        subsystem: "com.trailhound.app",
        category: "Performance"
    )

    static func measure<T>(_ name: StaticString, _ work: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try work()
    }
}
