import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PairingVehicleEditorView: View {
    let vehicleID: UUID

    @Environment(\.dismiss) private var dismiss
    @Query private var vehicles: [VehicleProfile]

    private var vehicle: VehicleProfile? {
        vehicles.first { $0.id == vehicleID }
    }

    var body: some View {
        Group {
            if let vehicle {
                PairingVehicleEditorForm(vehicle: vehicle, vehicles: vehicles)
            } else {
                ContentUnavailableView(L10n.pairingTabVehicleNotFound, systemImage: "car")
            }
        }
        .onChange(of: vehicle?.id) { _, newID in
            if newID == nil {
                dismiss()
            }
        }
    }
}

private enum PhotoSourceAction {
    case library
    case camera
}

private struct PairingVehicleEditorForm: View {
    let vehicle: VehicleProfile
    let vehicles: [VehicleProfile]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable private var settings = AppSettings.shared

    @State private var draft: VehicleEditorDraft?
    @State private var pendingPreview: UIImage?
    @State private var cropSourceImage: UIImage?
    @State private var isFraming = false
    @State private var frameScale = VehiclePhotoCropMath.defaultUserScale
    @State private var frameOffset: CGSize = .zero
    @State private var showPhotoSourceSheet = false
    @State private var pendingSourceAction: PhotoSourceAction?
    @State private var showCamera = false
    @State private var cameraImage: UIImage?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isPhotosPickerPresented = false
    @State private var showDeleteConfirm = false
    @State private var isSaving = false
    @State private var isProcessingPhoto = false
    @State private var emptyOverlayPulse = false

    private let heroSide: CGFloat = 132

    private var isOnlyVehicle: Bool { vehicles.count <= 1 }

    private var activeDraft: VehicleEditorDraft {
        draft ?? VehicleEditorDraft(from: vehicle)
    }

    private var resolvedSystemImage: String {
        VehicleIconOption.default.rawValue
    }

    private var isElectricAccent: Bool {
        activeDraft.fuelType == .electric
    }

    private var photoFileNameForPreview: String? {
        switch activeDraft.photoEdit {
        case .removed, .newThumb: return nil
        case .unchanged: return activeDraft.existingPhotoFileName
        }
    }

    private var hasPhoto: Bool { activeDraft.hasDisplayPhoto }

    var body: some View {
        Form {
            Section(L10n.pairingTabVehicleSection) {
                TextField(L10n.pairingTabVehicleName, text: draftBinding(\.name))
                    .glassRow(position: .first)
                Picker(L10n.pairingTabFuelType, selection: draftBinding(\.fuelType)) {
                    ForEach(VehicleFuelType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .glassRow(position: .middle)
                LabeledContent(activeDraft.consumptionLabel) {
                    TextField(activeDraft.consumptionLabel, value: draftBinding(\.consumption), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                }
                .glassRow(position: activeDraft.fuelType == .electric ? .middle : .last)
                if activeDraft.fuelType == .electric {
                    LabeledContent(L10n.pairingTabChargePrice) {
                        TextField(
                            "TL/kWh",
                            value: electricChargeBinding,
                            format: .number
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    }
                    .glassRow(position: .last)
                }
            }

            Section(L10n.pairingTabVehiclePhoto) {
                photoSection
                    .glassListRow()
            }

            Section {
                Button {
                    guard !isOnlyVehicle else { return }
                    updateDraft { $0.wantsDefault.toggle() }
                } label: {
                    HStack {
                        Text(L10n.pairingTabDefaultVehicle)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: activeDraft.wantsDefault ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundStyle(
                                activeDraft.wantsDefault
                                    ? TrailhoundBrandColors.brandBottom
                                    : Color.secondary
                            )
                    }
                }
                .buttonStyle(.plain)
                .disabled(isOnlyVehicle)
                .glassListRow()
            }

            Section {
                Button(L10n.pairingTabSave) {
                    Task { await saveVehicle() }
                }
                .frame(maxWidth: .infinity)
                .tint(TrailhoundBrandColors.brandBottom)
                .disabled(isSaving || isProcessingPhoto || isFraming)
                .glassListRow()
            }
        }
        .glassListChrome()
        .navigationTitle(L10n.pairingTabVehicleSection)
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneToolbar()
        .onAppear {
            reloadDraft()
            startEmptyOverlayPulse()
        }
        .onChange(of: vehicle.id) { _, _ in reloadDraft() }
        .sheet(isPresented: $showPhotoSourceSheet, onDismiss: handleSourceSheetDismissed) {
            VehiclePhotoSourceSheet(
                canUseCamera: CameraImagePicker.isCameraAvailable,
                onLibrary: {
                    pendingSourceAction = .library
                    showPhotoSourceSheet = false
                },
                onCamera: {
                    pendingSourceAction = .camera
                    showPhotoSourceSheet = false
                },
                onCancel: {
                    pendingSourceAction = nil
                    showPhotoSourceSheet = false
                }
            )
            .presentationDetents([.height(CameraImagePicker.isCameraAvailable ? 340 : 280)])
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(28)
            .presentationBackground {
                AtmosphericBackground(style: .full)
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
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker(image: $cameraImage)
                .ignoresSafeArea()
        }
        .onChange(of: cameraImage) { _, image in
            guard let image else { return }
            cameraImage = nil
            beginInlineFraming(with: image)
        }
    }

    private var photoSection: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Spacer(minLength: 8)
                hero
                if !isFraming {
                    photoActionColumn
                }
                Spacer(minLength: 8)
            }
            if isFraming, cropSourceImage != nil {
                VehiclePhotoInlineFraming(
                    workingImage: framingImageBinding,
                    userScale: $frameScale,
                    offset: $frameOffset,
                    cropSide: heroSide,
                    onApply: { Task { await applyFraming() } },
                    onCancel: cancelFraming
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var framingImageBinding: Binding<UIImage> {
        Binding(
            get: { cropSourceImage ?? UIImage() },
            set: { cropSourceImage = $0 }
        )
    }

    /// Rose — solid like Edit, but clearly destructive and not system-red.
    private var deleteAccent: Color {
        Color(red: 0.86, green: 0.22, blue: 0.36)
    }

    private var photoActionColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            if hasPhoto {
                photoSideButton(
                    title: L10n.pairingTabVehiclePhotoActionEdit,
                    systemImage: "slider.horizontal.3",
                    role: .edit
                ) {
                    Task { await openFraming() }
                }
                photoSideButton(
                    title: L10n.pairingTabVehiclePhotoActionChange,
                    systemImage: "photo.on.rectangle.angled",
                    role: .change
                ) {
                    showPhotoSourceSheet = true
                }
                photoSideButton(
                    title: L10n.pairingTabVehiclePhotoActionDelete,
                    systemImage: "trash",
                    role: .destructive
                ) {
                    TrailhoundHaptics.destructive()
                    showDeleteConfirm = true
                }
                .popover(isPresented: $showDeleteConfirm, arrowEdge: .top) {
                    deletePhotoPopover
                }
            } else {
                photoSideButton(
                    title: L10n.pairingTabVehiclePhotoActionAdd,
                    systemImage: "camera.fill",
                    role: .edit
                ) {
                    showPhotoSourceSheet = true
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .disabled(isProcessingPhoto || isSaving)
    }

    private var deletePhotoPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.pairingTabVehiclePhotoDeleteTitle)
                .font(.headline)
            Text(L10n.pairingTabVehiclePhotoDeleteMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(role: .destructive) {
                showDeleteConfirm = false
                removePhoto()
            } label: {
                Text(L10n.pairingTabVehiclePhotoRemove)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(deleteAccent)
        }
        .padding(16)
        .frame(minWidth: 220, idealWidth: 260)
        .presentationCompactAdaptation(.popover)
    }

    private enum PhotoSideRole {
        case destructive
        case change
        case edit
    }

    private func photoSideButton(
        title: String,
        systemImage: String,
        role: PhotoSideRole,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .frame(width: 14)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(sideButtonForeground(role))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minWidth: 96, alignment: .leading)
            .background(
                Capsule(style: .continuous)
                    .fill(sideButtonFill(role))
            )
        }
        .buttonStyle(VehiclePhotoPressStyle())
    }

    private func sideButtonForeground(_ role: PhotoSideRole) -> Color {
        switch role {
        case .destructive, .edit: return .white
        case .change: return .primary
        }
    }

    private func sideButtonFill(_ role: PhotoSideRole) -> Color {
        switch role {
        case .destructive: return deleteAccent
        case .change: return Color.primary.opacity(0.08)
        case .edit: return TrailhoundBrandColors.brandBottom
        }
    }

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: heroSide * 0.18, style: .continuous)
                .fill(TrailhoundBrandColors.brandBottom.opacity(0.10))
                .frame(width: heroSide, height: heroSide)
                .shadow(color: .black.opacity(0.12), radius: 16, y: 6)

            if isFraming, let cropSourceImage {
                VehiclePhotoFramingCanvas(
                    image: cropSourceImage,
                    userScale: frameScale,
                    offset: frameOffset,
                    side: heroSide,
                    showsCheckerboard: true
                )
                .modifier(
                    VehiclePhotoFramingGestures(
                        imageSize: cropSourceImage.size,
                        cropSide: heroSide,
                        userScale: $frameScale,
                        offset: $frameOffset
                    )
                )
            } else {
                VehicleAvatarView(
                    systemImage: resolvedSystemImage,
                    photoFileName: photoFileNameForPreview,
                    pendingImage: pendingPreview,
                    size: heroSide,
                    cornerRadius: heroSide * 0.18,
                    isElectricAccent: isElectricAccent,
                    showsBrandRing: true
                )
            }

            if !hasPhoto && !isFraming {
                emptyPhotoOverlay
                    .allowsHitTesting(false)
            }

            if isProcessingPhoto {
                RoundedRectangle(cornerRadius: heroSide * 0.18, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: heroSide, height: heroSide)
                ProgressView()
            }
        }
        .frame(width: heroSide, height: heroSide)
        .animation(reduceMotion ? nil : TrailhoundMotion.photoSettle, value: isFraming)
    }

    private var emptyPhotoOverlay: some View {
        Image(systemName: "camera.fill")
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(14)
            .background(Circle().fill(TrailhoundBrandColors.brandBottom.opacity(0.92)))
            .scaleEffect(emptyOverlayPulse ? 1.06 : 0.94)
            .opacity(emptyOverlayPulse ? 1 : 0.82)
            .shadow(color: TrailhoundBrandColors.brandBottom.opacity(0.35), radius: 10, y: 3)
            .accessibilityHidden(true)
    }

    private func startEmptyOverlayPulse() {
        guard !reduceMotion else {
            emptyOverlayPulse = true
            return
        }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            emptyOverlayPulse = true
        }
    }

    private func handleSourceSheetDismissed() {
        guard let pendingSourceAction else { return }
        let action = pendingSourceAction
        self.pendingSourceAction = nil
        switch action {
        case .library:
            isPhotosPickerPresented = true
        case .camera:
            showCamera = true
        }
    }

    private func reloadDraft() {
        draft = VehicleEditorDraft(from: vehicle)
        pendingPreview = nil
        cropSourceImage = nil
        isFraming = false
        frameScale = VehiclePhotoCropMath.defaultUserScale
        frameOffset = .zero
        photoPickerItem = nil
    }

    private func removePhoto() {
        updateDraft { $0.photoEdit = .removed }
        pendingPreview = nil
        cropSourceImage = nil
        isFraming = false
        photoPickerItem = nil
        TrailhoundHaptics.selection()
    }

    private func importPickerItem(_ item: PhotosPickerItem) async {
        isProcessingPhoto = true
        defer {
            isProcessingPhoto = false
            photoPickerItem = nil
        }
        do {
            guard let picked = try await item.loadTransferable(type: VehiclePickedImage.self),
                  let image = UIImage(data: picked.data) else {
                AppErrorPresenter.shared.present(L10n.pairingTabVehiclePhotoFailed)
                return
            }
            beginInlineFraming(with: image)
        } catch {
            AppErrorPresenter.shared.present(L10n.pairingTabVehiclePhotoFailed)
        }
    }

    private func beginInlineFraming(with image: UIImage) {
        let prepared = VehiclePhotoCropMath.prepareForCrop(image)
        cropSourceImage = prepared
        frameScale = VehiclePhotoCropMath.defaultUserScale
        frameOffset = .zero
        withAnimation(reduceMotion ? nil : TrailhoundMotion.photoSettle) {
            isFraming = true
        }
    }

    private func openFraming() async {
        if cropSourceImage != nil {
            withAnimation(reduceMotion ? nil : TrailhoundMotion.photoSettle) {
                isFraming = true
            }
            return
        }
        if let pendingPreview {
            beginInlineFraming(with: pendingPreview)
            return
        }
        guard let fileName = photoFileNameForPreview else {
            showPhotoSourceSheet = true
            return
        }
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }
        if let image = await VehiclePhotoStore.shared.image(fileName: fileName) {
            beginInlineFraming(with: image)
        } else {
            showPhotoSourceSheet = true
        }
    }

    private func cancelFraming() {
        TrailhoundHaptics.selection()
        endFramingSession()
    }

    private func endFramingSession(preview: UIImage? = nil) {
        if let preview {
            pendingPreview = preview
        }
        withAnimation(reduceMotion ? nil : TrailhoundMotion.photoSettle) {
            isFraming = false
        }
        cropSourceImage = nil
        frameScale = VehiclePhotoCropMath.defaultUserScale
        frameOffset = .zero
    }

    private func applyFraming() async {
        guard let source = cropSourceImage else { return }
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }
        guard let cropped = VehiclePhotoCropMath.renderSquare(
            image: source,
            cropSide: heroSide,
            userScale: frameScale,
            offset: frameOffset
        ) else {
            AppErrorPresenter.shared.present(L10n.pairingTabVehiclePhotoFailed)
            return
        }
        do {
            let thumb = try await VehiclePhotoStore.makeThumbnail(from: cropped)
            updateDraft { $0.photoEdit = .newThumb(thumb) }
            endFramingSession(preview: UIImage(data: thumb.data) ?? cropped)
            TrailhoundHaptics.pairingSucceeded()
        } catch {
            AppErrorPresenter.shared.present(L10n.pairingTabVehiclePhotoFailed)
        }
    }

    private func saveVehicle() async {
        guard !isSaving, !isFraming else { return }
        isSaving = true
        defer { isSaving = false }
        let snapshot = activeDraft
        do {
            try await snapshot.apply(
                to: vehicle,
                allVehicles: vehicles,
                in: modelContext,
                settings: settings
            )
            ToastPresenter.shared.show(.vehicleSaved)
            dismiss()
        } catch {
            AppErrorPresenter.shared.present(L10n.pairingTabSaveFailed(error.localizedDescription))
        }
    }

    private func updateDraft(_ mutate: (inout VehicleEditorDraft) -> Void) {
        var next = activeDraft
        mutate(&next)
        draft = next
    }

    private func draftBinding<Value>(_ keyPath: WritableKeyPath<VehicleEditorDraft, Value>) -> Binding<Value> {
        Binding(
            get: { activeDraft[keyPath: keyPath] },
            set: { newValue in
                updateDraft { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private var electricChargeBinding: Binding<Double> {
        Binding(
            get: { activeDraft.chargePricePerKWh ?? settings.evChargePricePerKWh },
            set: { newValue in
                updateDraft { $0.chargePricePerKWh = newValue }
            }
        )
    }
}

private struct VehiclePickedImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            VehiclePickedImage(data: data)
        }
    }
}

