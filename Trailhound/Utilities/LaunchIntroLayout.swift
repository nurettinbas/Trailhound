import Foundation
import Observation

// MARK: - Timeline

/// Clocks for the cold-launch intro. Pure; the scene plays these on Core Animation.
struct LaunchIntroTimeline: Equatable {
    /// Launch color has become the theme plate; the picture has settled in.
    var enterEnd: TimeInterval
    /// Large run ends; the plate starts closing into the icon.
    var runEnd: TimeInterval
    /// Plate is the app icon.
    var closeEnd: TimeInterval
    var total: TimeInterval
    var allowsMotion: Bool
    /// Preferred display rate. Existing display links keep their own caps.
    var preferredFrameRate: Float

    static var standard: LaunchIntroTimeline {
        LaunchIntroTimeline(
            enterEnd: 0.40,
            runEnd: 1.30,
            closeEnd: 2.10,
            total: TrailhoundMotion.launchIntroDuration,
            allowsMotion: true,
            preferredFrameRate: 120
        )
    }

    static var lowPower: LaunchIntroTimeline {
        LaunchIntroTimeline(
            enterEnd: 0.30,
            runEnd: 0.85,
            closeEnd: 1.40,
            total: TrailhoundMotion.launchIntroLowPowerDuration,
            allowsMotion: true,
            preferredFrameRate: 60
        )
    }

    /// Still logo. No run, no close.
    static var reduceMotion: LaunchIntroTimeline {
        let duration = TrailhoundMotion.launchIntroReduceMotionDuration
        return LaunchIntroTimeline(
            enterEnd: 0,
            runEnd: 0,
            closeEnd: 0,
            total: duration,
            allowsMotion: false,
            preferredFrameRate: 60
        )
    }

    /// Tap-to-skip. Fades out from wherever the intro is.
    static var skip: LaunchIntroTimeline {
        let duration = TrailhoundMotion.launchIntroSkipDuration
        return LaunchIntroTimeline(
            enterEnd: 0,
            runEnd: 0,
            closeEnd: 0,
            total: duration,
            allowsMotion: false,
            preferredFrameRate: 120
        )
    }

    static func resolve(reduceMotion: Bool, lowPower: Bool) -> LaunchIntroTimeline {
        if reduceMotion { return .reduceMotion }
        if lowPower { return .lowPower }
        return .standard
    }
}

// MARK: - Gate

enum LaunchIntroSkipReason: Equatable {
    case uiTest
    case activeRecording
    case pendingRecordingRequest
    case openedFromURL
    case notificationTap
    case voiceOver
    case alreadyPlayed
    case secondaryScene
}

struct LaunchIntroDecision: Equatable {
    var plays: Bool
    var skipReason: LaunchIntroSkipReason?

    static func play() -> LaunchIntroDecision {
        LaunchIntroDecision(plays: true, skipReason: nil)
    }

    static func skip(_ reason: LaunchIntroSkipReason) -> LaunchIntroDecision {
        LaunchIntroDecision(plays: false, skipReason: reason)
    }
}

enum LaunchIntroGate {
    static func decide(
        isUITesting: Bool,
        isActiveRecording: Bool,
        hasPendingRecordingRequest: Bool,
        openedFromURL: Bool,
        openedFromNotification: Bool,
        voiceOver: Bool,
        alreadyPlayed: Bool,
        isFirstScene: Bool
    ) -> LaunchIntroDecision {
        if isUITesting { return .skip(.uiTest) }
        if alreadyPlayed { return .skip(.alreadyPlayed) }
        if !isFirstScene { return .skip(.secondaryScene) }
        if isActiveRecording { return .skip(.activeRecording) }
        if hasPendingRecordingRequest { return .skip(.pendingRecordingRequest) }
        if openedFromURL { return .skip(.openedFromURL) }
        if openedFromNotification { return .skip(.notificationTap) }
        if voiceOver { return .skip(.voiceOver) }
        return .play()
    }
}

/// Process-wide cold-launch latch. The first scene may play once; later scenes and
/// foreground resumes do not. URL and notification flags are set before the first frame
/// when UIKit delivers them with the scene connection.
@MainActor
@Observable
final class LaunchIntroSession {
    static let shared = LaunchIntroSession()

    private(set) var didFinish = false
    /// True only when the hound intro actually ran (onboarding then skips its own drive-in).
    private(set) var playedIntro = false
    /// Set as soon as this process decides to play, before the overlay's first frame.
    private(set) var coversFirstScreen = false
    private(set) var openedFromURL = false
    private(set) var openedFromNotification = false
    /// Bumps when Settings asks to play the intro again. Cold launch stays at 0.
    private(set) var replayGeneration = 0
    private var didClaimScene = false

    func replay() {
        replayGeneration += 1
    }

    func noteURLOpen() {
        openedFromURL = true
    }

    func noteNotificationTap() {
        openedFromNotification = true
    }

    /// The first caller in the process owns the intro.
    func claimFirstScene() -> Bool {
        if didClaimScene { return false }
        didClaimScene = true
        return true
    }

    func markCovering() {
        coversFirstScreen = true
    }

    func markPlayed() {
        playedIntro = true
        didFinish = true
    }

    func markSkipped() {
        didFinish = true
    }
}
