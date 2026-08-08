import Foundation
import Observation

enum AppNotificationKind: String {
    case tripStarted
    case tripEnded
    case tripDiscarded
    case tripsMerged
    case orphanStale
    case recordingStopped
    case pairingSuggestion
    case vehicleCareReminder

    var systemImage: String {
        switch self {
        case .tripStarted: "play.circle.fill"
        case .tripEnded: "flag.checkered"
        case .tripDiscarded: "trash.circle.fill"
        case .tripsMerged: "arrow.triangle.merge"
        case .orphanStale: "exclamationmark.triangle.fill"
        case .recordingStopped: "stop.circle.fill"
        case .pairingSuggestion: "link.circle.fill"
        case .vehicleCareReminder: "wrench.and.screwdriver.fill"
        }
    }

    var tintName: String {
        switch self {
        case .tripStarted: "green"
        case .tripEnded: "blue"
        case .tripDiscarded: "gray"
        case .tripsMerged: "blue"
        case .orphanStale: "orange"
        case .recordingStopped: "red"
        case .pairingSuggestion: "blue"
        case .vehicleCareReminder: "orange"
        }
    }
}

@MainActor
@Observable
final class AppNotificationStore {
    static let shared = AppNotificationStore()

    private(set) var items: [StoredAppNotification] = []

    var unreadCount: Int {
        items.filter { !$0.isRead }.count
    }

    private init() {
        reload()
    }

    func reload() {
        items = AppNotificationArchive.load()
    }

    func record(
        kind: AppNotificationKind,
        title: String,
        body: String,
        tripID: UUID? = nil,
        createdAt: Date = Date()
    ) {
        let record = StoredAppNotification(
            kind: kind.rawValue,
            title: title,
            body: body,
            createdAt: createdAt,
            tripID: tripID
        )
        items.insert(record, at: 0)
        if items.count > 100 {
            items = Array(items.prefix(100))
        }
        persist()
    }

    func recordSystemNotification(title: String, body: String, identifier: String) {
        let kind = kindForIdentifier(identifier)
        let tripID = tripIDFromIdentifier(identifier)
        guard !containsDuplicate(title: title, body: body, within: 5) else { return }
        record(kind: kind, title: title, body: body, tripID: tripID)
    }

    func syncLiveTripNotification(
        tripID: UUID,
        isPaused: Bool,
        elapsed: TimeInterval,
        distanceMeters: Double,
        currentSpeedKmh: Int
    ) {
        let title = isPaused ? L10n.recordingPaused : L10n.recordingStarted
        let duration = DateFormatters.formatDuration(elapsed)
        let distance = DateFormatters.formatDistance(distanceMeters)
        let body: String
        if isPaused {
            body = "\(duration) · \(distance)"
        } else {
            body = "\(duration) · \(distance) · \(L10n.formatSpeedKmh(Double(currentSpeedKmh)))"
        }
        updateTripStartedNotification(tripID: tripID, title: title, body: body)
    }

    private func updateTripStartedNotification(tripID: UUID, title: String, body: String) {
        guard let index = items.firstIndex(where: {
            $0.tripID == tripID && kind(for: $0) == .tripStarted
        }) else { return }

        let existing = items[index]
        guard existing.title != title || existing.body != body else { return }

        items[index] = StoredAppNotification(
            id: existing.id,
            kind: existing.kind,
            title: title,
            body: body,
            createdAt: existing.createdAt,
            tripID: existing.tripID,
            isRead: existing.isRead
        )
        persist()
    }

    nonisolated static func enqueueSystemNotification(
        title: String,
        body: String,
        identifier: String,
        reload: Bool = false
    ) {
        Task { @MainActor in
            shared.recordSystemNotification(title: title, body: body, identifier: identifier)
            if reload {
                shared.reload()
            }
        }
    }

    func markRead(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isRead = true
        persist()
    }

    func markAllRead() {
        guard items.contains(where: { !$0.isRead }) else { return }
        for index in items.indices {
            items[index].isRead = true
        }
        persist()
    }

    func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    func clearAll() {
        guard !items.isEmpty else { return }
        items.removeAll()
        persist()
    }

    func kind(for record: StoredAppNotification) -> AppNotificationKind {
        AppNotificationKind(rawValue: record.kind) ?? .tripEnded
    }

    private func persist() {
        AppNotificationArchive.save(items)
    }

    private func containsDuplicate(title: String, body: String, within seconds: TimeInterval) -> Bool {
        guard let latest = items.first else { return false }
        let isRecent = Date().timeIntervalSince(latest.createdAt) <= seconds
        return isRecent && latest.title == title && latest.body == body
    }

    private func kindForIdentifier(_ identifier: String) -> AppNotificationKind {
        if identifier.contains("started") { return .tripStarted }
        if identifier.contains("ended") { return .tripEnded }
        if identifier.contains("discarded") { return .tripDiscarded }
        if identifier.contains("merged") { return .tripsMerged }
        if identifier.contains("orphan") { return .orphanStale }
        if identifier.contains("stopped") { return .recordingStopped }
        if identifier.contains("pairing") { return .pairingSuggestion }
        if identifier.contains(".care.") { return .vehicleCareReminder }
        return .tripEnded
    }

    private func tripIDFromIdentifier(_ identifier: String) -> UUID? {
        let parts = identifier.split(separator: ".")
        guard let raw = parts.last else { return nil }
        return UUID(uuidString: String(raw))
    }
}
