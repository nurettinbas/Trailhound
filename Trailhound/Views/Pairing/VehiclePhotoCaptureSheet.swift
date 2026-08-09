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

/// Single sheet identity so source → capture expands in place (no dismiss / re-present).
enum VehiclePhotoSheetRoute: Identifiable, Equatable {
    case flow

    var id: String { "vehicle-photo-flow" }
}

enum VehiclePhotoFlowPhase: Equatable {
    case source
    case capture(VehiclePhotoCaptureMode)
}

/// Detent sizes for the unified vehicle photo sheet.
enum VehiclePhotoFlowDetents {
    static func sourceHeight(cameraAvailable: Bool) -> CGFloat {
        cameraAvailable ? 340 : 280
    }

    static var captureFraction: CGFloat { 0.72 }

    static func source(cameraAvailable: Bool) -> PresentationDetent {
        .height(sourceHeight(cameraAvailable: cameraAvailable))
    }

    static var capture: PresentationDetent { .fraction(captureFraction) }
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

/// Unified source → capture sheet: detent expands, content crossfades (no 450ms handoff).
struct VehiclePhotoFlowSheet: View {
    var onPicked: (UIImage) -> Void
    var onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: VehiclePhotoFlowPhase = .source
    @State private var selectedDetent: PresentationDetent
    @State private var isCaptureProcessing = false

    private var canUseCamera: Bool { VehicleInlineCameraView.isCameraAvailable }
    private var sourceDetent: PresentationDetent {
        VehiclePhotoFlowDetents.source(cameraAvailable: canUseCamera)
    }
    private var captureDetent: PresentationDetent { VehiclePhotoFlowDetents.capture }

    init(
        onPicked: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onPicked = onPicked
        self.onCancel = onCancel
        let camera = VehicleInlineCameraView.isCameraAvailable
        _selectedDetent = State(initialValue: VehiclePhotoFlowDetents.source(cameraAvailable: camera))
    }

    var body: some View {
        ZStack {
            Group {
                switch phase {
                case .source:
                    AtmosphericBackground(style: .full)
                case .capture:
                    Color.black.opacity(0.92)
                }
            }
            .ignoresSafeArea()

            Group {
                switch phase {
                case .source:
                    VehiclePhotoSourceSheet(
                        canUseCamera: canUseCamera,
                        onLibrary: {
                            expand(to: .gallery)
                        },
                        onCamera: {
                            expand(to: .camera)
                        },
                        onCancel: onCancel
                    )
                    .transition(
                        .asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .offset(y: 8))
                        )
                    )
                case .capture(let mode):
                    VehiclePhotoCaptureSheet(
                        initialMode: mode,
                        onPicked: onPicked,
                        onCancel: shrinkToSource,
                        isProcessing: $isCaptureProcessing
                    )
                    .transition(TrailhoundMotion.softRiseTransition)
                }
            }
        }
        .animation(reduceMotion ? nil : TrailhoundMotion.photoSheetExpand, value: phase)
        .presentationDetents([sourceDetent, captureDetent], selection: $selectedDetent)
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(28)
        .presentationBackground {
            Group {
                switch phase {
                case .source:
                    AtmosphericBackground(style: .full)
                case .capture:
                    Color.black.opacity(0.92)
                }
            }
        }
        .interactiveDismissDisabled(isCaptureProcessing)
        .onChange(of: selectedDetent) { _, newValue in
            syncPhase(with: newValue)
        }
    }

    private func expand(to mode: VehiclePhotoCaptureMode) {
        applyPhase(.capture(mode), detent: captureDetent)
    }

    private func shrinkToSource() {
        isCaptureProcessing = false
        applyPhase(.source, detent: sourceDetent)
    }

    private func applyPhase(_ newPhase: VehiclePhotoFlowPhase, detent: PresentationDetent) {
        if reduceMotion {
            phase = newPhase
            selectedDetent = detent
        } else {
            withAnimation(TrailhoundMotion.photoSheetExpand) {
                phase = newPhase
                selectedDetent = detent
            }
        }
    }

    /// Keep phase aligned if the user drags between detents.
    private func syncPhase(with detent: PresentationDetent) {
        switch (phase, detent) {
        case (.capture, _) where detent == sourceDetent:
            if reduceMotion {
                phase = .source
                isCaptureProcessing = false
            } else {
                withAnimation(TrailhoundMotion.photoSheetExpand) {
                    phase = .source
                    isCaptureProcessing = false
                }
            }
        case (.source, _) where detent == captureDetent:
            // Expand only via Library / Camera — snap drag-up back.
            selectedDetent = sourceDetent
        default:
            break
        }
    }
}

/// ~72% capture content: recent grid + All Photos + inline camera (hosted inside `VehiclePhotoFlowSheet`).
struct VehiclePhotoCaptureSheet: View {
    var initialMode: VehiclePhotoCaptureMode
    var onPicked: (UIImage) -> Void
    var onCancel: () -> Void
    @Binding var isProcessing: Bool

    @StateObject private var loader = VehiclePhotoLibraryLoader()
    @State private var mode: VehiclePhotoCaptureMode
    /// Mode the sheet was opened with (controls Back on the camera pane).
    @State private var entryMode: VehiclePhotoCaptureMode
    @State private var isPhotosPickerPresented = false
    @State private var photoPickerItem: PhotosPickerItem?

    private var canUseCamera: Bool { VehicleInlineCameraView.isCameraAvailable }

    init(
        initialMode: VehiclePhotoCaptureMode = .gallery,
        onPicked: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void,
        isProcessing: Binding<Bool> = .constant(false)
    ) {
        self.initialMode = initialMode
        self.onPicked = onPicked
        self.onCancel = onCancel
        _isProcessing = isProcessing
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
                        onBack: {
                            TrailhoundHaptics.selection()
                            onCancel()
                        },
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
    @Binding var pendingFramingImage: UIImage?

    func body(content: Content) -> some View {
        content
            .sheet(item: $photoSheet) { _ in
                VehiclePhotoFlowSheet(
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

extension View {
    func vehiclePhotoFlowSheets(
        photoSheet: Binding<VehiclePhotoSheetRoute?>,
        pendingFramingImage: Binding<UIImage?>
    ) -> some View {
        modifier(
            VehiclePhotoFlowSheetModifier(
                photoSheet: photoSheet,
                pendingFramingImage: pendingFramingImage
            )
        )
    }
}
