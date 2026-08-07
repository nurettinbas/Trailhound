import AppIntents
import Foundation

@MainActor
private func performRecordingShortcut(_ request: () -> Void) {
    AppServices.bootstrapRecordingIfNeeded()
    request()
    AppServices.runtime.processPendingRecordingRequests()
}

/// `LiveActivityIntent` is required so Siri/Shortcuts can start a Live Activity /
/// Dynamic Island presentation while the app stays in the background
/// (`openAppWhenRun = false`). Plain `AppIntent` hits ActivityKit `visibility`.
struct StartTripRecordingIntent: LiveActivityIntent {
    nonisolated static var title: LocalizedStringResource { "shortcut.start.title" }
    nonisolated static var description: IntentDescription {
        IntentDescription("shortcut.start.description")
    }
    // AppIntent requires a Bool literal (not a runtime value). Always silent like
    // stop/pause/resume so Siri/Shortcuts/CarPlay don't force Face ID via App Lock.
    // If confirmExternalRecordingStart is on, awaitingExternalStartConfirmation waits
    // until the user next opens the app (ContentView alert).
    nonisolated static var openAppWhenRun: Bool { false }
    nonisolated static var isDiscoverable: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        performRecordingShortcut {
            RecordingControlBridge.requestStartFromControlSurface()
        }
        let recording = AppServices.runtime.tripRecordingService
        if recording.state.isActiveSession, let startedAt = recording.recordingStartedAt {
            let mark = RecordingVehicleMarkSnapshot.makeCached(
                for: recording.activeRecordingVehicleForLiveActivity()
            )
            await RecordingLiveActivityService.startOnCurrentTask(
                startedAt: startedAt,
                elapsed: recording.elapsedTime,
                distanceMeters: recording.currentDistanceMeters,
                currentSpeedKmh: Int(max(0, recording.currentSpeedMps) * 3.6),
                isPaused: recording.state == .paused,
                vehicleSystemImage: mark.systemImage,
                vehicleSymbolScaleX: mark.symbolScaleX,
                vehiclePhotoJPEGData: mark.photoJPEGData
            )
        }
        return .result(dialog: IntentDialog("shortcut.start.success"))
    }
}

struct StopTripRecordingIntent: AppIntent {
    nonisolated static var title: LocalizedStringResource { "shortcut.stop.title" }
    nonisolated static var description: IntentDescription {
        IntentDescription("shortcut.stop.description")
    }
    nonisolated static var openAppWhenRun: Bool { false }
    nonisolated static var isDiscoverable: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        performRecordingShortcut {
            RecordingControlBridge.requestStopFromControlSurface()
        }
        return .result(dialog: IntentDialog("shortcut.stop.success"))
    }
}

struct PauseTripRecordingIntent: AppIntent {
    nonisolated static var title: LocalizedStringResource { "shortcut.pause.title" }
    nonisolated static var description: IntentDescription {
        IntentDescription("shortcut.pause.description")
    }
    nonisolated static var openAppWhenRun: Bool { false }
    nonisolated static var isDiscoverable: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        performRecordingShortcut {
            RecordingControlBridge.requestPauseFromControlSurface()
        }
        return .result(dialog: IntentDialog("shortcut.pause.success"))
    }
}

struct ResumeTripRecordingIntent: AppIntent {
    nonisolated static var title: LocalizedStringResource { "shortcut.resume.title" }
    nonisolated static var description: IntentDescription {
        IntentDescription("shortcut.resume.description")
    }
    nonisolated static var openAppWhenRun: Bool { false }
    nonisolated static var isDiscoverable: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        performRecordingShortcut {
            RecordingControlBridge.requestResumeFromControlSurface()
        }
        return .result(dialog: IntentDialog("shortcut.resume.success"))
    }
}

struct TodayKmQueryIntent: AppIntent {
    nonisolated static var title: LocalizedStringResource { "shortcut.today.title" }
    nonisolated static var description: IntentDescription {
        IntentDescription(
            "shortcut.today.description",
            resultValueName: "shortcut.today.result"
        )
    }
    nonisolated static var openAppWhenRun: Bool { false }
    nonisolated static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let km = TodayKmProvider.todayKilometers()
        let spoken = String(format: "%.1f km", km)
        return .result(value: spoken)
    }
}

struct TrailhoundShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .blue }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTripRecordingIntent(),
            phrases: [
                "Yolculuğu başlat \(.applicationName)",
                "\(.applicationName) yolculuğu başlat",
                "\(.applicationName) ile yolculuğu başlat",
                "Start trip in \(.applicationName)",
                "Start trip with \(.applicationName)"
            ],
            shortTitle: "shortcut.start.title",
            systemImageName: "play.circle"
        )
        AppShortcut(
            intent: PauseTripRecordingIntent(),
            phrases: [
                "Yolculuğu duraklat \(.applicationName)",
                "\(.applicationName) yolculuğu duraklat",
                "Pause trip in \(.applicationName)",
                "Pause trip with \(.applicationName)"
            ],
            shortTitle: "shortcut.pause.title",
            systemImageName: "pause.circle"
        )
        AppShortcut(
            intent: ResumeTripRecordingIntent(),
            phrases: [
                "Yolculuğu sürdür \(.applicationName)",
                "\(.applicationName) yolculuğu sürdür",
                "Resume trip in \(.applicationName)",
                "Resume trip with \(.applicationName)"
            ],
            shortTitle: "shortcut.resume.title",
            systemImageName: "playpause.circle"
        )
        AppShortcut(
            intent: StopTripRecordingIntent(),
            phrases: [
                "Yolculuğu bitir \(.applicationName)",
                "\(.applicationName) yolculuğu bitir",
                "\(.applicationName) ile yolculuğu bitir",
                "End trip in \(.applicationName)",
                "End trip with \(.applicationName)"
            ],
            shortTitle: "shortcut.stop.title",
            systemImageName: "stop.circle"
        )
    }
}
