import SwiftUI

enum DeleteConfirmKind {
    case generic
    case vehicle(isActivePaired: Bool)
    case journalRemove
    case category
    case installmentPlan(count: Int)
    case vehiclePhoto
    case notificationsAll

    var title: String {
        switch self {
        case .generic, .category, .notificationsAll:
            L10n.deleteConfirmTitle
        case .vehicle:
            L10n.pairingTabDeleteVehicleTitle
        case .journalRemove:
            L10n.deleteConfirmJournalRemoveTitle
        case .installmentPlan:
            L10n.vehicleExpenseDeletePlanTitle
        case .vehiclePhoto:
            L10n.pairingTabVehiclePhotoDeleteTitle
        }
    }

    var message: String {
        switch self {
        case .generic:
            L10n.deleteConfirmMessage
        case .vehicle(let isActivePaired):
            isActivePaired
                ? L10n.pairingTabDeleteVehicleMessageActive
                : L10n.pairingTabDeleteVehicleMessage
        case .journalRemove:
            L10n.deleteConfirmJournalRemoveMessage
        case .category:
            L10n.deleteConfirmCategoryMessage
        case .installmentPlan:
            L10n.deleteConfirmInstallmentPlanMessage
        case .vehiclePhoto:
            L10n.pairingTabVehiclePhotoDeleteMessage
        case .notificationsAll:
            L10n.deleteConfirmNotificationsAllMessage
        }
    }

    var confirmTitle: String {
        switch self {
        case .generic, .vehicle, .category:
            L10n.delete
        case .journalRemove:
            L10n.journalRemove
        case .installmentPlan(let count):
            L10n.vehicleExpenseDeletePlan(count)
        case .vehiclePhoto:
            L10n.pairingTabVehiclePhotoRemove
        case .notificationsAll:
            L10n.notificationsClearAll
        }
    }
}

struct DeleteConfirmRequest {
    var title: String
    var message: String
    var confirmTitle: String
    var onConfirm: () -> Void
}

@MainActor
@Observable
final class DeleteConfirmPresenter {
    static let shared = DeleteConfirmPresenter()

    var request: DeleteConfirmRequest?

    func confirm(_ kind: DeleteConfirmKind, perform: @escaping () -> Void) {
        present(
            title: kind.title,
            message: kind.message,
            confirmTitle: kind.confirmTitle,
            perform: perform
        )
    }

    func present(
        title: String,
        message: String,
        confirmTitle: String,
        perform: @escaping () -> Void
    ) {
        KeyboardDismiss.dismiss()
        request = DeleteConfirmRequest(
            title: title,
            message: message,
            confirmTitle: confirmTitle,
            onConfirm: perform
        )
        TrailhoundHaptics.selection()
    }

    func cancel() {
        request = nil
    }

    func performConfirm() {
        let action = request?.onConfirm
        request = nil
        action?()
    }
}

struct DeleteConfirmHostModifier: ViewModifier {
    @Bindable private var presenter = DeleteConfirmPresenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if let request = presenter.request {
                DeleteConfirmOverlay(request: request)
                    .transition(overlayTransition)
                    .zIndex(2_000)
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.15) : TrailhoundMotion.cardSpring,
            value: presenter.request != nil
        )
    }

    private var overlayTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .opacity.combined(with: .scale(scale: 0.94))
    }
}

private struct DeleteConfirmOverlay: View {
    let request: DeleteConfirmRequest

    var body: some View {
        ZStack {
            Color.black.opacity(0.46)
                .ignoresSafeArea()
                .onTapGesture {
                    DeleteConfirmPresenter.shared.cancel()
                }
                .accessibilityLabel(L10n.cancel)
                .accessibilityAddTraits(.isButton)

            VStack(spacing: 16) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.red)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)

                Text(request.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(request.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    Button {
                        DeleteConfirmPresenter.shared.cancel()
                    } label: {
                        Text(L10n.cancel)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .glassChrome(cornerRadius: 14)

                    Button(role: .destructive) {
                        DeleteConfirmPresenter.shared.performConfirm()
                    } label: {
                        Text(request.confirmTitle)
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(22)
            .frame(maxWidth: 320)
            .glassChrome(cornerRadius: GlassTokens.cardRadius)
            .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
            .accessibilityElement(children: .contain)
        }
    }
}

extension View {
    func deleteConfirmHost() -> some View {
        modifier(DeleteConfirmHostModifier())
    }
}
