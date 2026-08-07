import Foundation

enum FuelCurrency: String, CaseIterable, Identifiable, Sendable {
    case tryCurrency = "TRY"
    case eur = "EUR"
    case usd = "USD"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .tryCurrency: "₺"
        case .eur: "€"
        case .usd: "$"
        }
    }

    static let `default` = FuelCurrency.tryCurrency
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults: UserDefaults
    private let suiteName = "group.com.trailhound.app"

    var hasCompletedOnboarding = false
    var hasCompletedCarSetup = false
    /// User-marked completion of the in-app Shortcuts guide (not verified against Shortcuts).
    var hasCompletedShortcutsGuide = false
    /// Live target for the calendar month currently in progress. Widgets and fuel-agnostic surfaces read this.
    var monthlyDistanceGoalMeters: Double = 500_000 {
        didSet { defaults.set(monthlyDistanceGoalMeters, forKey: Key.monthlyDistanceGoalMeters) }
    }
    /// Frozen monthly targets keyed by `"yyyy-MM"`. Past months stay locked at the value last written while that month was current.
    private(set) var monthlyGoalsByMonth: [String: Double] = [:]
    /// Vehicle used for new recordings and fuel estimates when none is set on the trip.
    var recordingVehicleID: UUID? {
        didSet {
            if let recordingVehicleID {
                defaults.set(recordingVehicleID.uuidString, forKey: Key.recordingVehicleID)
            } else {
                defaults.removeObject(forKey: Key.recordingVehicleID)
            }
        }
    }

    private enum Key {
        static let recordingSounds = "recordingSoundsEnabled"
        static let fuelLitersPer100km = "fuelLitersPer100km"
        static let fuelPricePerLiter = "fuelPricePerLiter"
        static let fuelCurrency = "fuelCurrency"
        static let evChargePricePerKWh = "evChargePricePerKWh"
        static let appLockEnabled = "appLockEnabled"
        static let confirmExternalRecordingStart = RecordingControlBridge.Keys.confirmExternalRecordingStart
        static let privacyRadiusMeters = "privacyRadiusMeters"
        static let autoDeleteDays = "autoDeleteDays"
        static let blurExportCoordinates = "blurExportCoordinates"
        static let hasCompletedCarSetup = "hasCompletedCarSetup"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let hasCompletedShortcutsGuide = "hasCompletedShortcutsGuide"
        static let monthlyDistanceGoalMeters = "monthlyDistanceGoalMeters"
        static let monthlyGoalsByMonth = "monthlyGoalsByMonth"
        static let preferredLanguageCode = "preferredLanguageCode"
        static let developerModeEnabled = "developerModeEnabled"
        static let recordingVehicleID = "recording.vehicleID"
    }

    init(userDefaults: UserDefaults? = nil) {
        let resolvedDefaults = userDefaults ?? RecordingControlBridge.sharedDefaults()
        defaults = resolvedDefaults
        hasCompletedOnboarding = resolvedDefaults.bool(forKey: Key.hasCompletedOnboarding)
        hasCompletedCarSetup = resolvedDefaults.bool(forKey: Key.hasCompletedCarSetup)
        hasCompletedShortcutsGuide = resolvedDefaults.bool(forKey: Key.hasCompletedShortcutsGuide)
        resolvedDefaults.removeObject(forKey: Key.preferredLanguageCode)
        monthlyDistanceGoalMeters = Self.loadedPositiveDouble(
            from: resolvedDefaults,
            key: Key.monthlyDistanceGoalMeters,
            default: 500_000
        )
        monthlyGoalsByMonth = Self.loadedMonthlyGoals(from: resolvedDefaults)
        seedCurrentMonthGoalIfNeeded()
        Self.removeLegacyRecordingSensitivityKeys(from: resolvedDefaults)
        if let raw = resolvedDefaults.string(forKey: Key.recordingVehicleID),
           let id = UUID(uuidString: raw) {
            recordingVehicleID = id
        }
    }

    /// Stable `"yyyy-MM"` key for a calendar month.
    func goalMonthKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        return String(format: "%04d-%02d", year, month)
    }

    /// Stored goal for that month, or the live `monthlyDistanceGoalMeters` when no history exists.
    func goalMeters(forMonthContaining date: Date) -> Double {
        let key = goalMonthKey(for: date)
        if let stored = monthlyGoalsByMonth[key], stored > 0 {
            return stored
        }
        return monthlyDistanceGoalMeters
    }

    /// Only the calendar month currently in progress can be edited.
    func isGoalEditable(forMonthContaining date: Date, now: Date = Date()) -> Bool {
        goalMonthKey(for: date) == goalMonthKey(for: now)
    }

    /// Writes the live monthly target and freezes it under the current month's key. No-op when
    /// `date` is not the calendar month of `now` (past months stay locked).
    func setMonthlyGoalMeters(
        _ meters: Double,
        forMonthContaining date: Date = Date(),
        now: Date = Date()
    ) {
        guard isGoalEditable(forMonthContaining: date, now: now) else { return }
        let value = max(meters, 0)
        monthlyDistanceGoalMeters = value
        var goals = monthlyGoalsByMonth
        goals[goalMonthKey(for: now)] = value
        monthlyGoalsByMonth = goals
        persistMonthlyGoals()
    }

    private func seedCurrentMonthGoalIfNeeded(now: Date = Date()) {
        let key = goalMonthKey(for: now)
        guard monthlyGoalsByMonth[key] == nil else { return }
        var goals = monthlyGoalsByMonth
        goals[key] = monthlyDistanceGoalMeters
        monthlyGoalsByMonth = goals
        persistMonthlyGoals()
    }

    private func persistMonthlyGoals() {
        defaults.set(monthlyGoalsByMonth, forKey: Key.monthlyGoalsByMonth)
    }

    private static func loadedMonthlyGoals(from defaults: UserDefaults) -> [String: Double] {
        guard let raw = defaults.dictionary(forKey: Key.monthlyGoalsByMonth) else { return [:] }
        var parsed: [String: Double] = [:]
        for (key, value) in raw {
            if let number = value as? Double, number > 0 {
                parsed[key] = number
            } else if let number = value as? NSNumber, number.doubleValue > 0 {
                parsed[key] = number.doubleValue
            }
        }
        return parsed
    }

    func completeOnboarding() {
        guard !hasCompletedOnboarding else { return }
        hasCompletedOnboarding = true
        defaults.set(true, forKey: Key.hasCompletedOnboarding)
    }

    func skipCarSetup() {
        if !hasCompletedCarSetup {
            hasCompletedCarSetup = true
            defaults.set(true, forKey: Key.hasCompletedCarSetup)
        }
    }

    func markShortcutsGuideCompleted() {
        guard !hasCompletedShortcutsGuide else { return }
        hasCompletedShortcutsGuide = true
        defaults.set(true, forKey: Key.hasCompletedShortcutsGuide)
    }

    private static func removeLegacyRecordingSensitivityKeys(from defaults: UserDefaults) {
        let keys = [
            "recording.stopSpeedKmh",
            "recording.stopMinimumDistanceMeters",
            "recording.stopMinimumDurationSeconds",
            "recording.tripStopMinimumDurationSeconds"
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }

    /// One-time cleanup after removing in-app Bluetooth auto-start.
    func migrateLegacyBluetoothAutoStartKeys() {
        let legacyKeys = [
            "pairedVehicleName",
            "pairedRouteUID",
            "activeAutoTriggerVehicleID",
            "vehicle.lastConnected",
            "vehicle.lastTrigger"
        ]
        for key in legacyKeys {
            defaults.removeObject(forKey: key)
        }
    }

    var recordingSoundsEnabled: Bool {
        get {
            if defaults.object(forKey: Key.recordingSounds) == nil { return true }
            return defaults.bool(forKey: Key.recordingSounds)
        }
        set { defaults.set(newValue, forKey: Key.recordingSounds) }
    }

    var fuelLitersPer100km: Double {
        get {
            let value = defaults.double(forKey: Key.fuelLitersPer100km)
            return value > 0 ? value : 7.5
        }
        set { defaults.set(newValue, forKey: Key.fuelLitersPer100km) }
    }

    var fuelPricePerLiter: Double {
        get {
            let value = defaults.double(forKey: Key.fuelPricePerLiter)
            return value > 0 ? value : 65.0
        }
        set { defaults.set(newValue, forKey: Key.fuelPricePerLiter) }
    }

    /// Currency the liter / kWh price is denominated in. Drives every fuel cost label in the app.
    var fuelCurrency: FuelCurrency {
        get {
            guard let raw = defaults.string(forKey: Key.fuelCurrency),
                  let currency = FuelCurrency(rawValue: raw) else {
                return .default
            }
            return currency
        }
        set { defaults.set(newValue.rawValue, forKey: Key.fuelCurrency) }
    }

    var evChargePricePerKWh: Double {
        get {
            let value = defaults.double(forKey: Key.evChargePricePerKWh)
            return value > 0 ? value : 8.5
        }
        set { defaults.set(newValue, forKey: Key.evChargePricePerKWh) }
    }

    var appLockEnabled: Bool {
        get { defaults.bool(forKey: Key.appLockEnabled) }
        set { defaults.set(newValue, forKey: Key.appLockEnabled) }
    }

    var confirmExternalRecordingStart: Bool {
        get { defaults.bool(forKey: Key.confirmExternalRecordingStart) }
        set { defaults.set(newValue, forKey: Key.confirmExternalRecordingStart) }
    }

    var awaitingExternalStartConfirmation: Bool {
        get { defaults.bool(forKey: "recording.awaitingExternalStartConfirmation") }
        set { defaults.set(newValue, forKey: "recording.awaitingExternalStartConfirmation") }
    }

    var privacyRadiusMeters: Double {
        get {
            let value = defaults.double(forKey: Key.privacyRadiusMeters)
            return value > 0 ? value : 500
        }
        set { defaults.set(newValue, forKey: Key.privacyRadiusMeters) }
    }

    var autoDeleteDays: Int {
        get {
            let value = defaults.integer(forKey: Key.autoDeleteDays)
            return value
        }
        set { defaults.set(newValue, forKey: Key.autoDeleteDays) }
    }

    var blurExportCoordinates: Bool {
        get { defaults.bool(forKey: Key.blurExportCoordinates) }
        set { defaults.set(newValue, forKey: Key.blurExportCoordinates) }
    }

    var developerModeEnabled: Bool {
        get { defaults.bool(forKey: Key.developerModeEnabled) }
        set { defaults.set(newValue, forKey: Key.developerModeEnabled) }
    }

    private static func loadedTimeInterval(
        from defaults: UserDefaults,
        key: String,
        default defaultValue: TimeInterval
    ) -> TimeInterval {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        let value = defaults.double(forKey: key)
        return value > 0 ? value : defaultValue
    }

    private static func loadedPositiveDouble(
        from defaults: UserDefaults,
        key: String,
        default defaultValue: Double
    ) -> Double {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        let value = defaults.double(forKey: key)
        return value > 0 ? value : defaultValue
    }

    func syncRecordingState(
        isRecording: Bool,
        isPaused: Bool = false,
        elapsed: TimeInterval,
        distanceMeters: Double,
        currentSpeedKmh: Int = 0,
        recordingStartedAt: Date? = nil
    ) {
        defaults.set(isRecording, forKey: "recording.isActive")
        defaults.set(isPaused, forKey: "recording.isPaused")
        defaults.removeObject(forKey: "recording.isPendingGPS")
        defaults.set(elapsed, forKey: "recording.elapsed")
        defaults.set(distanceMeters, forKey: "recording.distance")
        defaults.set(currentSpeedKmh, forKey: "recording.currentSpeedKmh")
        if let recordingStartedAt {
            defaults.set(recordingStartedAt.timeIntervalSince1970, forKey: RecordingControlBridge.Keys.startedAt)
        } else if !isRecording || isPaused {
            defaults.removeObject(forKey: RecordingControlBridge.Keys.startedAt)
        }
    }

    var pendingStartRecordingRequest: Bool {
        get { defaults.bool(forKey: "recording.requestStart") }
        set {
            defaults.set(newValue, forKey: "recording.requestStart")
            if newValue {
                defaults.set(Date().timeIntervalSince1970, forKey: "recording.requestStartAt")
            } else {
                defaults.removeObject(forKey: "recording.requestStartAt")
            }
        }
    }

    var pendingStopRecordingRequest: Bool {
        get { defaults.bool(forKey: "recording.requestStop") }
        set {
            defaults.set(newValue, forKey: "recording.requestStop")
            if newValue {
                defaults.set(Date().timeIntervalSince1970, forKey: "recording.requestStopAt")
            } else {
                defaults.removeObject(forKey: "recording.requestStopAt")
            }
        }
    }

    var pendingPauseRecordingRequest: Bool {
        get { defaults.bool(forKey: "recording.requestPause") }
        set {
            defaults.set(newValue, forKey: "recording.requestPause")
            if newValue {
                defaults.set(Date().timeIntervalSince1970, forKey: "recording.requestPauseAt")
            } else {
                defaults.removeObject(forKey: "recording.requestPauseAt")
            }
        }
    }

    var pendingResumeRecordingRequest: Bool {
        get { defaults.bool(forKey: "recording.requestResume") }
        set {
            defaults.set(newValue, forKey: "recording.requestResume")
            if newValue {
                defaults.set(Date().timeIntervalSince1970, forKey: "recording.requestResumeAt")
            } else {
                defaults.removeObject(forKey: "recording.requestResumeAt")
            }
        }
    }

    private static let recordingRequestTTL: TimeInterval = 60

    func expireStaleRecordingRequests() {
        let now = Date().timeIntervalSince1970
        if pendingStartRecordingRequest,
           now - defaults.double(forKey: "recording.requestStartAt") > Self.recordingRequestTTL {
            pendingStartRecordingRequest = false
        }
        if pendingStopRecordingRequest,
           now - defaults.double(forKey: "recording.requestStopAt") > Self.recordingRequestTTL {
            pendingStopRecordingRequest = false
        }
        if pendingPauseRecordingRequest,
           now - defaults.double(forKey: "recording.requestPauseAt") > Self.recordingRequestTTL {
            pendingPauseRecordingRequest = false
        }
        if pendingResumeRecordingRequest,
           now - defaults.double(forKey: "recording.requestResumeAt") > Self.recordingRequestTTL {
            pendingResumeRecordingRequest = false
        }
    }
}
