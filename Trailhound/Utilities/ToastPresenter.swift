import Foundation
import SwiftUI

enum ToastKind: Equatable {
    case saved
    case deleted
    case placeSaved
    case vehicleSaved
    case vehicleReminderSaved
    case vehicleExpenseSaved
    case tripSaved
    case categoryAdded
    case categoryDeleted
    case orphanSaved
    case tripsMerged
    case shortcutsGuideFinished
    case shortcutsAutomationReached
    case categoryAccepted
    case journalTitleRequired
    case personalRecord(PersonalRecordBreak)

    var message: String {
        switch self {
        case .saved: L10n.toastSaved
        case .deleted: L10n.toastDeleted
        case .placeSaved: L10n.toastPlaceSaved
        case .vehicleSaved: L10n.toastVehicleSaved
        case .vehicleReminderSaved: L10n.toastVehicleReminderSaved
        case .vehicleExpenseSaved: L10n.toastVehicleExpenseSaved
        case .tripSaved: L10n.toastTripSaved
        case .categoryAdded: L10n.toastCategoryAdded
        case .categoryDeleted: L10n.toastCategoryDeleted
        case .orphanSaved: L10n.toastOrphanSaved
        case .tripsMerged: L10n.toastTripsMerged
        case .shortcutsGuideFinished: L10n.toastShortcutsGuideFinished
        case .shortcutsAutomationReached: L10n.toastShortcutsAutomationReached
        case .categoryAccepted: L10n.toastCategoryAccepted
        case .journalTitleRequired: L10n.journalTitleRequired
        case .personalRecord(let payload): payload.accessibilityMessage
        }
    }

    var systemImage: String {
        switch self {
        case .saved, .tripSaved, .orphanSaved, .shortcutsGuideFinished, .shortcutsAutomationReached, .vehicleReminderSaved, .vehicleExpenseSaved, .categoryAccepted:
            "checkmark.circle.fill"
        case .placeSaved:
            "mappin.circle.fill"
        case .vehicleSaved:
            "car.circle.fill"
        case .categoryAdded:
            "folder.badge.plus"
        case .categoryDeleted, .deleted:
            "trash.circle.fill"
        case .tripsMerged:
            "arrow.triangle.merge"
        case .journalTitleRequired:
            "exclamationmark.circle.fill"
        case .personalRecord:
            "trophy.fill"
        }
    }

    var tint: Color {
        switch self {
        case .deleted, .categoryDeleted, .journalTitleRequired:
            .orange
        case .tripsMerged:
            TrailhoundBrandColors.brandBottom
        case .personalRecord:
            TrailhoundBrandColors.brandBottom
        default:
            .green
        }
    }

    var usesSuccessHaptic: Bool {
        switch self {
        case .deleted, .categoryDeleted, .journalTitleRequired, .personalRecord:
            false
        default:
            true
        }
    }

    var usesBadgeHaptic: Bool {
        if case .personalRecord = self { return true }
        return false
    }

    var dwellSeconds: TimeInterval {
        switch self {
        case .personalRecord: 2.8
        default: 2
        }
    }
}

@MainActor
@Observable
final class ToastPresenter {
    static let shared = ToastPresenter()

    var kind: ToastKind?
    var isPresented = false

    private var dismissTask: Task<Void, Never>?
    private var clearKindTask: Task<Void, Never>?
    private var creditsQueuedKind: ToastKind?
    private var creditsFallbackTask: Task<Void, Never>?
    private var followTask: Task<Void, Never>?

    func show(_ kind: ToastKind, playHaptic: Bool = true) {
        followTask?.cancel()
        followTask = nil
        dismissTask?.cancel()
        clearKindTask?.cancel()
        self.kind = kind
        withAnimation(TrailhoundMotion.toastSpring) {
            isPresented = true
        }
        if playHaptic, !UITestSupport.isEnabled {
            if kind.usesBadgeHaptic {
                TrailhoundHaptics.badgeUnlocked()
            } else if kind.usesSuccessHaptic {
                TrailhoundHaptics.pairingSucceeded()
            } else {
                TrailhoundHaptics.selection()
            }
        }
        let dwell = kind.dwellSeconds
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(dwell))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.dismiss()
            }
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation(TrailhoundMotion.toastDismiss) {
            isPresented = false
        }
        // Keep `kind` until the exit transition finishes so removal isn't abrupt.
        clearKindTask?.cancel()
        clearKindTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, !self.isPresented else { return }
                self.kind = nil
            }
        }
    }

    func queueAfterRecordingCredits(_ kind: ToastKind) {
        creditsFallbackTask?.cancel()
        creditsQueuedKind = kind
        creditsFallbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3.6))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.flushRecordingCreditsQueue()
            }
        }
    }

    func flushRecordingCreditsQueue() {
        creditsFallbackTask?.cancel()
        creditsFallbackTask = nil
        guard let kind = creditsQueuedKind else { return }
        creditsQueuedKind = nil
        show(kind)
    }

    func queueFollowingCurrent(_ kind: ToastKind) {
        followTask?.cancel()
        followTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.show(kind)
            }
        }
    }
}

struct ToastHostModifier: ViewModifier {
    @Bindable private var presenter = ToastPresenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if presenter.isPresented, let kind = presenter.kind {
                toastContent(for: kind)
                    .padding(.horizontal, GlassTokens.panelHorizontalInset)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity)
                    .transition(TrailhoundMotion.toastTransition(reduceMotion: reduceMotion))
                    .zIndex(999)
                    .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private func toastContent(for kind: ToastKind) -> some View {
        if case .personalRecord(let payload) = kind {
            RecordToastView(payload: payload)
        } else {
            ToastView(kind: kind)
        }
    }
}

extension View {
    func toastHost() -> some View {
        modifier(ToastHostModifier())
    }
}
