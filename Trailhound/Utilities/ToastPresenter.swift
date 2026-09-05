import Foundation
import SwiftUI

enum ToastKind {
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
    case journalTitleRequired

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
        case .journalTitleRequired: L10n.journalTitleRequired
        }
    }

    var systemImage: String {
        switch self {
        case .saved, .tripSaved, .orphanSaved, .shortcutsGuideFinished, .vehicleReminderSaved, .vehicleExpenseSaved:
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
        }
    }

    var tint: Color {
        switch self {
        case .deleted, .categoryDeleted, .journalTitleRequired:
            .orange
        case .tripsMerged:
            TrailhoundBrandColors.brandBottom
        default:
            .green
        }
    }

    var usesSuccessHaptic: Bool {
        switch self {
        case .deleted, .categoryDeleted, .journalTitleRequired:
            false
        default:
            true
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

    func show(_ kind: ToastKind, playHaptic: Bool = true) {
        dismissTask?.cancel()
        clearKindTask?.cancel()
        self.kind = kind
        withAnimation(TrailhoundMotion.toastSpring) {
            isPresented = true
        }
        if playHaptic {
            if kind.usesSuccessHaptic {
                TrailhoundHaptics.pairingSucceeded()
            } else {
                TrailhoundHaptics.selection()
            }
        }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
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
}

struct ToastHostModifier: ViewModifier {
    @Bindable private var presenter = ToastPresenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if presenter.isPresented, let kind = presenter.kind {
                ToastView(kind: kind)
                    .padding(.horizontal, GlassTokens.panelHorizontalInset)
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity)
                    .transition(TrailhoundMotion.toastTransition(reduceMotion: reduceMotion))
                    .zIndex(999)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func toastHost() -> some View {
        modifier(ToastHostModifier())
    }
}
