import Foundation

enum VehicleScheduleKind: String, Codable, CaseIterable, Sendable {
    case service
    case inspection
    case trafficInsurance
    case casco
    case custom

    var defaultTitleKey: StaticString {
        switch self {
        case .service: "vehicles.care.kind.service"
        case .inspection: "vehicles.care.kind.inspection"
        case .trafficInsurance: "vehicles.care.kind.traffic_insurance"
        case .casco: "vehicles.care.kind.casco"
        case .custom: "vehicles.care.kind.custom"
        }
    }

    var defaultTitle: String { L10n.string(defaultTitleKey) }

    /// Push reminder offsets in days before due date.
    var defaultReminderOffsets: [Int] {
        switch self {
        case .service, .inspection, .custom:
            return [30, 7, 1]
        case .trafficInsurance, .casco:
            return [7, 1]
        }
    }

    var systemImage: String {
        switch self {
        case .service: "wrench.and.screwdriver.fill"
        case .inspection: "seal.fill"
        case .trafficInsurance: "doc.text.fill"
        case .casco: "shield.fill"
        case .custom: "calendar"
        }
    }
}

enum VehicleScheduleIntervalKind: String, Codable, CaseIterable, Sendable {
    case none
    case everyMonths
    case everyYears
    case everyKm
    case whicheverFirst

    var displayName: String {
        switch self {
        case .none: L10n.string("vehicles.care.interval.none")
        case .everyMonths: L10n.string("vehicles.care.interval.months")
        case .everyYears: L10n.string("vehicles.care.interval.years")
        case .everyKm: L10n.string("vehicles.care.interval.km")
        case .whicheverFirst: L10n.string("vehicles.care.interval.whichever_first")
        }
    }
}

/// Picker / new entries use these seven cases. Legacy raw values still decode via `resolved`.
enum VehicleExpenseCategory: String, Codable, CaseIterable, Sendable {
    case fuel
    case casco
    case service
    case inspection
    case repair
    case accessory
    case other

    /// Legacy stored strings (not in CaseIterable picker).
    private static let legacyInsurance = "insurance"
    private static let legacyTax = "tax"
    private static let legacyParking = "parking"
    private static let legacyParts = "parts"

    var displayName: String {
        switch self {
        case .fuel: L10n.string("vehicles.care.expense.fuel")
        case .casco: L10n.string("vehicles.care.expense.casco")
        case .service: L10n.string("vehicles.care.expense.service")
        case .inspection: L10n.string("vehicles.care.expense.inspection")
        case .repair: L10n.string("vehicles.care.expense.repair")
        case .accessory: L10n.string("vehicles.care.expense.accessory")
        case .other: L10n.string("vehicles.care.expense.other")
        }
    }

    var systemImage: String {
        switch self {
        case .fuel: "fuelpump.fill"
        case .casco: "shield.fill"
        case .service: "wrench.and.screwdriver.fill"
        case .inspection: "seal.fill"
        case .repair: "hammer.fill"
        case .accessory: "bag.fill"
        case .other: "ellipsis.circle.fill"
        }
    }

    /// Buckets used by Stats stacked charts.
    var costBucket: VehicleCostBucket {
        switch self {
        case .fuel: .fuel
        case .service, .repair: .service
        case .casco: .casco
        case .inspection, .accessory, .other: .other
        }
    }

    static func resolved(fromRaw raw: String) -> VehicleExpenseCategory {
        if let direct = VehicleExpenseCategory(rawValue: raw) { return direct }
        switch raw {
        case legacyParts: return .accessory
        case legacyInsurance, legacyTax, legacyParking: return .other
        default: return .other
        }
    }

    static func suggested(for kind: VehicleScheduleKind) -> VehicleExpenseCategory {
        switch kind {
        case .service: .service
        case .inspection: .inspection
        case .trafficInsurance: .other
        case .casco: .casco
        case .custom: .other
        }
    }
}

enum VehicleExpenseSource: String, Codable, Sendable {
    case manual
    case tripEstimate
}

enum VehicleCostBucket: String, CaseIterable, Sendable {
    case fuel
    case service
    case insurance
    case casco
    case other

    var displayName: String {
        switch self {
        case .fuel: L10n.string("stats.cost.bucket.fuel")
        case .service: L10n.string("stats.cost.bucket.service")
        case .insurance: L10n.string("stats.cost.bucket.insurance")
        case .casco: L10n.string("stats.cost.bucket.casco")
        case .other: L10n.string("stats.cost.bucket.other")
        }
    }
}

/// Runtime-only due state — never persisted.
enum VehicleCareDueState: Equatable, Sendable {
    case upcoming(daysLeft: Int)
    case dueToday
    case overdue(days: Int)
    case noDate

    var sortPriority: Int {
        switch self {
        case .overdue: 0
        case .dueToday: 1
        case .upcoming: 2
        case .noDate: 3
        }
    }

    var isUrgent: Bool {
        switch self {
        case .overdue, .dueToday: true
        case .upcoming(let days): days <= 30
        case .noDate: false
        }
    }

    var isOverdue: Bool {
        if case .overdue = self { return true }
        return false
    }
}

struct VehicleDueItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let scheduleID: UUID
    let vehicleID: UUID
    let vehicleName: String
    let kind: VehicleScheduleKind
    let title: String
    let dueDate: Date?
    let state: VehicleCareDueState

    var daysSortKey: Int {
        switch state {
        case .overdue(let days): -days
        case .dueToday: 0
        case .upcoming(let days): days
        case .noDate: Int.max
        }
    }
}
