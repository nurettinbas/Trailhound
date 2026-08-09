import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum VehiclePhotoCaptureMode: Equatable, Hashable {
    case gallery
    case camera
}

enum VehiclePhotoSourceAction: Equatable {
    case library
    case camera
    case cancel
}

/// Single sheet route so source → capture never fights dual `.sheet(isPresented:)` modifiers.
enum VehiclePhotoSheetRoute: Identifiable, Equatable {
    case source
    case capture(VehiclePhotoCaptureMode)

    var id: String {
        switch self {
        case .source: return "source"
        case .capture(.gallery): return "capture-gallery"
        case .capture(.camera): return "capture-camera"
        }
    }
}

/// Maps the atmospheric source dialog choice to the capture overlay mode.
enum VehiclePhotoCaptureHandoff {
    static func pendingMode(after action: VehiclePhotoSourceAction) -> VehiclePhotoCaptureMode? {
        switch action {
        case .library: return .gallery
        case .camera: return .camera
        case .cancel: return nil
        }
    }
}

/// ~72% bottom sheet: recent grid + All Photos + inline camera.
struct VehiclePhotoCaptureSheet: View {
    var initialMode: VehiclePhotoCaptureMode
    var onPicked: (UIImage) -> Void
    var onCancel: () -> Void

    @StateObject private var loader = VehiclePhotoLibraryLoader()
    @State private var mode: VehiclePhotoCaptureMode
    /// Mode the sheet was opened with (controls Back on the camera pane).
    @State private var entryMode: VehiclePhotoCaptureMode
    @State private var isPhotosPickerPresented = false
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isProcessing = false

    private var canUseCamera: Bool { VehicleInlineCameraView.isCameraAvailable }

    init(
        initialMode: VehiclePhotoCaptureMode = .gallery,
        onPicked: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.initialMode = initialMode
        self.onPicked = onPicked
        self.onCancel = onCancel
        _mode = State(initialValue: initialMode)
        _entryMode = State(initialValue: initialMode)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            Group {
                switch mode {
                case .gallery:
                    VehiclePhotoLibraryGrid(
                        loader: loader,
                        canUseCamera: canUseCamera,
                        onSelectAsset: { id in
                            Task { await pickAsset(id) }
                        },
                        onOpenCamera: {
                            TrailhoundHaptics.selection()
                            mode = .camera
                        },
                        onAllPhotos: {
                            TrailhoundHaptics.selection()
                            isPhotosPickerPresented = true
                        },
                        onBack: onCancel,
                        onOpenSettings: openSettings
                    )
                case .camera:
                    VehicleInlineCameraView(
                        isActive: mode == .camera,
                        onCapture: { image in
                            finish(with: image)
                        },
                        onBack: {
                            TrailhoundHaptics.selection()
                            if entryMode == .camera {
                                onCancel()
                            } else {
                                mode = .gallery
                            }
                        },
                        onOpenLibrary: {
                            mode = .gallery
                        },
                        onPermissionDenied: {}
                    )
                }
            }

            if isProcessing {
                Color.black.opacity(0.35).ignoresSafeArea()
                ProgressView()
                    .tint(.white)
            }
        }
        .photosPicker(
            isPresented: $isPhotosPickerPresented,
            selection: $photoPickerItem,
            matching: .images,
            photoLibrary: .shared()
        )
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task { await importPickerItem(item) }
        }
        .task {
            await loader.prepare()
        }
        .onDisappear {
            loader.tearDown()
        }
        .presentationDetents([.fraction(0.72)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(28)
        .presentationBackground {
            Color.black.opacity(0.92)
        }
        .interactiveDismissDisabled(isProcessing)
    }

    private func pickAsset(_ localIdentifier: String) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        guard let image = await loader.requestFullImage(localIdentifier: localIdentifier) else {
            AppErrorPresenter.shared.present(L10n.pairingTabVehiclePhotoFailed)
            return
        }
        finish(with: image)
    }

    private func importPickerItem(_ item: PhotosPickerItem) async {
        isProcessing = true
        defer {
            isProcessing = false
            photoPickerItem = nil
        }
        do {
            guard let picked = try await item.loadTransferable(type: VehiclePickedImage.self),
                  let image = UIImage(data: picked.data) else {
                AppErrorPresenter.shared.present(L10n.pairingTabVehiclePhotoFailed)
                return
            }
            finish(with: image)
        } catch {
            AppErrorPresenter.shared.present(L10n.pairingTabVehiclePhotoFailed)
        }
    }

    private func finish(with image: UIImage) {
        TrailhoundHaptics.selection()
        onPicked(image)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct VehiclePickedImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            VehiclePickedImage(data: data)
        }
    }
}

/// Host photo sheets on a NavigationStack root (not inside a List row) so the first tap sticks.
struct VehiclePhotoFlowSheetModifier: ViewModifier {
    @Binding var photoSheet: VehiclePhotoSheetRoute?
    @Binding var pendingCaptureMode: VehiclePhotoCaptureMode?
    @Binding var pendingFramingImage: UIImage?

    func body(content: Content) -> some View {
        content
            .sheet(item: $photoSheet, onDismiss: handleDismissed) { route in
                switch route {
                case .source:
                    VehiclePhotoSourceSheet(
                        canUseCamera: VehicleInlineCameraView.isCameraAvailable,
                        onLibrary: {
                            pendingCaptureMode = VehiclePhotoCaptureHandoff.pendingMode(after: .library)
                            photoSheet = nil
                        },
                        onCamera: {
                            pendingCaptureMode = VehiclePhotoCaptureHandoff.pendingMode(after: .camera)
                            photoSheet = nil
                        },
                        onCancel: {
                            pendingCaptureMode = VehiclePhotoCaptureHandoff.pendingMode(after: .cancel)
                            photoSheet = nil
                        }
                    )
                    .presentationDetents([.height(VehicleInlineCameraView.isCameraAvailable ? 340 : 280)])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(28)
                    .presentationBackground {
                        AtmosphericBackground(style: .full)
                    }
                    .interactiveDismissDisabled(false)
                case .capture(let mode):
                    VehiclePhotoCaptureSheet(
                        initialMode: mode,
                        onPicked: { image in
                            pendingFramingImage = image
                            photoSheet = nil
                        },
                        onCancel: {
                            photoSheet = nil
                        }
                    )
                }
            }
    }

    private func handleDismissed() {
        if let mode = pendingCaptureMode {
            pendingCaptureMode = nil
            Task { @MainActor in
                // Source teardown must finish; 350ms is often tight inside NavigationStack+List.
                try? await Task.sleep(for: .milliseconds(450))
                photoSheet = .capture(mode)
            }
            return
        }
        // Framing handoff is consumed by the editor via `pendingFramingImage` binding.
    }
}

extension View {
    func vehiclePhotoFlowSheets(
        photoSheet: Binding<VehiclePhotoSheetRoute?>,
        pendingCaptureMode: Binding<VehiclePhotoCaptureMode?>,
        pendingFramingImage: Binding<UIImage?>
    ) -> some View {
        modifier(
            VehiclePhotoFlowSheetModifier(
                photoSheet: photoSheet,
                pendingCaptureMode: pendingCaptureMode,
                pendingFramingImage: pendingFramingImage
            )
        )
    }
}
