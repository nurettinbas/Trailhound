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
        let isPresented = presenter.request != nil
        content
            // Do not implicit-animate the tab/list tree when the dialog appears.
            .animation(nil, value: isPresented)
            // Swipe-open List rows steal the first tap. Block the tree under the
            // dialog so Cancel/Delete land on the overlay, not the list.
            .allowsHitTesting(!isPresented)
            .overlay {
                ZStack {
                    if let request = presenter.request {
                        Color.black.opacity(0.46)
                            .ignoresSafeArea()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                DeleteConfirmPresenter.shared.cancel()
                            }
                            .accessibilityLabel(L10n.cancel)
                            .accessibilityAddTraits(.isButton)
                            .transition(.opacity)

                        DeleteConfirmCard(request: request)
                            .transition(cardTransition)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(overlayAnimation, value: isPresented)
            }
    }

    private var overlayAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.15) : TrailhoundMotion.cardSpring
    }

    private var cardTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .opacity.combined(with: .scale(scale: 0.94))
    }
}

private struct DeleteConfirmCard: View {
    let request: DeleteConfirmRequest

    var body: some View {
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

            HStack(spacing: 10) {
                actionButton(title: L10n.cancel, tint: Color(.systemGray)) {
                    DeleteConfirmPresenter.shared.cancel()
                }

                actionButton(title: request.confirmTitle, tint: .red, role: .destructive) {
                    DeleteConfirmPresenter.shared.performConfirm()
                }
            }
        }
        .padding(22)
        .frame(maxWidth: 320)
        .glassChrome(cornerRadius: GlassTokens.cardRadius)
        .shadow(color: .black.opacity(0.22), radius: 24, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: GlassTokens.cardRadius, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func actionButton(
        title: String,
        tint: Color,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .frame(maxWidth: .infinity)
    }
}

extension View {
    func deleteConfirmHost() -> some View {
        modifier(DeleteConfirmHostModifier())
    }

    /// Trailing swipe that only presents confirm. Do not use `Button(role: .destructive)`
    /// here — List treats that role as an immediate row delete, so Cancel would leave
    /// the row gone even though the model was not deleted.
    @ViewBuilder
    func confirmingDeleteSwipe(
        _ kind: DeleteConfirmKind = .generic,
        title: String = L10n.delete,
        systemImage: String = "trash",
        allowsFullSwipe: Bool = true,
        enabled: Bool = true,
        perform: @escaping () -> Void
    ) -> some View {
        if enabled {
            swipeActions(edge: .trailing, allowsFullSwipe: allowsFullSwipe) {
                Button {
                    DeleteConfirmPresenter.shared.confirm(kind, perform: perform)
                } label: {
                    Label(title, systemImage: systemImage)
                }
                .destructiveTint()
            }
        } else {
            self
        }
    }
}
