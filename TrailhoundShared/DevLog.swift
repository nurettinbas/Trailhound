import Foundation

/// Log severity for `DevLog` entries.
public enum DevLogLevel: String, Sendable {
    case info
    case warning
    case error

    var badge: String {
        switch self {
        case .info: "INFO"
        case .warning: "WARN"
        case .error: "ERR"
        }
    }
}

/// Coarse subsystem tag for `DevLog` entries. Keep this list small and stable
/// so exported logs stay easy to filter/scan.
public enum DevLogCategory: String, Sendable, CaseIterable, Hashable {
    case lifecycle
    case bluetooth
    case recording
    case location
    case widget
    case tripDetail
    case general
}

/// Trailhound has no analytics or crash reporting (the app works fully offline),
/// so this is the only way to see what actually happened on a user's device —
/// e.g. exact Bluetooth connect/disconnect timing around a false-stop report.
///
/// Entries are appended as plain text lines to a rolling log file in the
/// shared app-group container, so both the main app and the widget/App
/// Intent extension processes can write to the same log. All file access is
/// serialized on a private queue.
public final class DevLog: @unchecked Sendable {
    public static let shared = DevLog()

    private let queue = DispatchQueue(label: "com.trailhound.devlog", qos: .utility)
    private let fileURL: URL?
    private let maxBytes = 2 * 1024 * 1024

    private init() {
        let dir = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: RecordingControlBridge.appGroupSuiteName
        )
        fileURL = dir?.appendingPathComponent("trailhound-debug.log")
    }

    public func log(_ category: DevLogCategory, _ message: String, level: DevLogLevel = .info) {
        let timestamp = Self.timestampFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level.badge)] [\(category.rawValue)] \(message)\n"
        queue.async { [weak self] in
            self?.append(line)
        }
    }

    public func warning(_ category: DevLogCategory, _ message: String) {
        log(category, message, level: .warning)
    }

    public func error(_ category: DevLogCategory, _ message: String) {
        log(category, message, level: .error)
    }

    private func append(_ line: String) {
        guard let fileURL, let data = line.data(using: .utf8) else { return }

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        handle.seekToEndOfFile()
        handle.write(data)

        rotateIfNeeded(fileURL: fileURL)
    }

    /// Drops the oldest half of the log once it grows past `maxBytes`, so a long
    /// drive (or a chatty bug) can't grow the file unbounded.
    private func rotateIfNeeded(fileURL: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? UInt64,
              size > UInt64(maxBytes) else { return }
        guard let full = try? Data(contentsOf: fileURL) else { return }
        let tail = full.suffix(maxBytes / 2)
        try? tail.write(to: fileURL, options: .atomic)
    }

    /// Full raw log contents, suitable for exporting as a `.log` file.
    public func readAllText() -> String {
        queue.sync {
            guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        }
    }

    /// Most recent lines, newest first, for the in-app live view.
    public func recentLines(maxCount: Int = 400) -> [String] {
        let content = readAllText()
        let lines = content.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return Array(lines.suffix(maxCount).reversed())
    }

    public func clear() {
        guard let fileURL else { return }
        queue.async {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    public var exportFileURL: URL? { fileURL }

    public func fileSizeBytes() -> Int {
        guard let fileURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attributes[.size] as? UInt64 else { return 0 }
        return Int(size)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
