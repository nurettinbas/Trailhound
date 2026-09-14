import SwiftUI
import UIKit

/// Restores the system edge-swipe pop when the SwiftUI back control is custom
/// (`navigationBarBackButtonHidden(true)`). UIKit otherwise leaves
/// `interactivePopGestureRecognizer` disabled unless a delegate allows it.
/// Pass `disabled: true` to block the pop (vehicle unsaved-edits guard).
struct NavigationInteractivePopEnabler: UIViewControllerRepresentable {
    var disabled: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(disabled: disabled)
    }

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        context.coordinator.disabled = disabled
        uiViewController.coordinator = context.coordinator
        uiViewController.attachInteractivePopIfNeeded()
    }

    final class Controller: UIViewController {
        var coordinator: Coordinator?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            attachInteractivePopIfNeeded()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            attachInteractivePopIfNeeded()
        }

        func attachInteractivePopIfNeeded() {
            guard let navigationController else { return }
            coordinator?.attach(to: navigationController)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var disabled: Bool
        private weak var navigationController: UINavigationController?
        private weak var installedGesture: UIGestureRecognizer?

        init(disabled: Bool) {
            self.disabled = disabled
        }

        func attach(to navigationController: UINavigationController) {
            self.navigationController = navigationController
            guard let gesture = navigationController.interactivePopGestureRecognizer else { return }
            gesture.isEnabled = !disabled && navigationController.viewControllers.count > 1
            if installedGesture !== gesture {
                gesture.delegate = self
                installedGesture = gesture
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            !disabled && (navigationController?.viewControllers.count ?? 0) > 1
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Left-edge pop must win over MapKit (and other) pans.
            gestureRecognizer === navigationController?.interactivePopGestureRecognizer
                && otherGestureRecognizer is UIPanGestureRecognizer
        }
    }
}
