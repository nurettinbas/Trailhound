import Foundation

enum RecapYearPolicy {
    /// January shows last year's recap; every other month is year-to-date.
    static func displayYear(now: Date = Date(), calendar: Calendar = .current) -> Int {
        let year = calendar.component(.year, from: now)
        let month = calendar.component(.month, from: now)
        return month == 1 ? year - 1 : year
    }

    static func seenKey(for year: Int) -> String {
        "recap.seen.\(year)"
    }

    static func shouldPresent(_ snapshot: YearRecapSnapshot?) -> Bool {
        snapshot?.hasData == true
    }
}

enum RecapNotificationPolicy {
    static func notifiedKey(for year: Int) -> String {
        "recap.notified.\(year)"
    }

    /// Previous calendar year — only during January, when that recap is complete.
    static func catchUpYear(now: Date = Date(), calendar: Calendar = .current) -> Int? {
        calendar.component(.month, from: now) == 1
            ? calendar.component(.year, from: now) - 1
            : nil
    }

    /// 1 January 09:00 local of the year after `year`.
    static func fireDate(forRecapYear year: Int, calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1, hour: 9, minute: 0))
    }

    static func shouldNotify(hasData: Bool, seen: Bool, alreadyNotified: Bool) -> Bool {
        hasData && !seen && !alreadyNotified
    }
}

/// Identifiable wrapper so the recap cover is never presented empty.
/// `fullScreenCover(isPresented:)` + `if let snapshot` draws a blank white
/// screen when SwiftUI builds the cover before the optional is copied in.
struct RecapStorySession: Identifiable, Equatable {
    let id: UUID
    let snapshot: YearRecapSnapshot

    init(snapshot: YearRecapSnapshot) {
        self.id = UUID()
        self.snapshot = snapshot
    }
}
