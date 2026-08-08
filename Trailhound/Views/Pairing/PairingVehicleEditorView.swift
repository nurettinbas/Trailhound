import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PairingVehicleEditorView: View {
    let vehicleID: UUID

    @Environment(\.dismiss) private var dismiss
    @Query private var vehicles: [VehicleProfile]
    @State private var hasUnsavedChanges = false
    @State private var saveTrigger = 0
    @State private var saveDisabled = false

    private var vehicle: VehicleProfile? {
        vehicles.first { $0.id == vehicleID }
    }

    var body: some View {
        Group {
            if let vehicle {
                PairingVehicleEditorForm(
                    vehicle: vehicle,
                    vehicles: vehicles,
                    unsavedChanges: $hasUnsavedChanges,
                    saveTrigger: $saveTrigger,
                    saveDisabled: $saveDisabled
                )
            } else {
                ContentUnavailableView(L10n.pairingTabVehicleNotFound, systemImage: "car")
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveTrigger += 1
                } label: {
                    GlassToolbarSaveButton(title: L10n.pairingTabSave)
                }
                .buttonStyle(.plain)
                .disabled(saveDisabled)
                .opacity(saveDisabled ? 0.45 : 1)
            }
        }
        .vehicleEditorUnsavedChangesGuard($hasUnsavedChanges)
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

enum VehicleEditorPresentation {
    /// Standalone Form with nav chrome; dismisses after save.
    case standaloneForm
    /// Sections for embedding inside a parent List (vehicle detail).
    case embeddedInList
}

struct PairingVehicleEditorForm: View {
    let vehicle: VehicleProfile
    let vehicles: [VehicleProfile]
    var presentation: VehicleEditorPresentation = .standaloneForm
    var unsavedChanges: Binding<Bool> = .constant(false)
    var saveTrigger: Binding<Int> = .constant(0)
    var saveDisabled: Binding<Bool> = .constant(false)

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

    private let photoHeroSide: CGFloat = 132
    private let emptyPhotoControlHeight: CGFloat = 56 * 1.3 + 20 + 8 + 6

    private var activeHeroSide: CGFloat {
        hasPhoto || isFraming || isProcessingPhoto ? photoHeroSide : emptyPhotoControlHeight
    }

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

    private var hasUnsavedChanges: Bool {
        if isFraming { return true }
        guard let draft else { return false }
        return draft != VehicleEditorDraft(from: vehicle)
    }

    var body: some View {
        Group {
            switch presentation {
            case .standaloneForm:
                Form {
                    editorSections
                }
                .glassListChrome()
                .navigationTitle(L10n.pairingTabVehicleSection)
                .navigationBarTitleDisplayMode(.inline)
                .keyboardDoneToolbar()
            case .embeddedInList:
                editorSections
            }
        }
        .onAppear {
            reloadDraft()
            syncUnsavedChanges()
            syncSaveDisabled()
        }
        .onChange(of: vehicle.id) { _, _ in reloadDraft() }
        .onChange(of: draft) { _, _ in syncUnsavedChanges() }
        .onChange(of: isFraming) { _, _ in
            syncUnsavedChanges()
            syncSaveDisabled()
        }
        .onChange(of: isSaving) { _, _ in syncSaveDisabled() }
        .onChange(of: isProcessingPhoto) { _, _ in syncSaveDisabled() }
        .onChange(of: saveTrigger.wrappedValue) { _, _ in
            Task { await saveVehicle() }
        }
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

    @ViewBuilder
    private var editorSections: some View {
        if showsCompactEmptyPhotoLayout {
            Section(L10n.pairingTabVehicleSection) {
                photoSection
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Color.clear)
                    .listRowInsets(compactEmptyPhotoRowInsets)
                    .listRowSeparator(.hidden)

                vehicleProfileFields(compactTop: true)
            }
        } else {
            Section {
                photoSection
                    .listRowBackground(Color.clear)
                    .listRowInsets(photoListRowInsets)
                    .listRowSeparator(.hidden)
            }

            Section(L10n.pairingTabVehicleSection) {
                vehicleProfileFields(compactTop: false)
            }
        }
    }

    private var showsCompactEmptyPhotoLayout: Bool {
        !hasPhoto && !isFraming && !isProcessingPhoto
    }

    @ViewBuilder
    private func vehicleProfileFields(compactTop: Bool) -> some View {
        GlassFieldLabel(title: L10n.pairingTabVehicleName) {
            TextField("", text: draftBinding(\.name))
        }
        .glassRow(position: .first)
        .listRowInsets(vehicleFirstRowInsets(compactTop: compactTop))

        defaultVehicleRow
            .glassRow(position: .middle)

        Picker(L10n.pairingTabFuelType, selection: draftBinding(\.fuelType)) {
            ForEach(VehicleFuelType.allCases, id: \.self) { type in
                Text(type.displayName).tag(type)
            }
        }
        .glassRow(position: .middle)
        LabeledContent(activeDraft.consumptionLabel) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    TextField("", value: draftBinding(\.consumption), format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .glassInputField()
                        .frame(width: geo.size.width * 0.5)
                }
            }
            .frame(height: 44)
        }
        .glassRow(position: activeDraft.fuelType == .electric ? .middle : .last)
        if activeDraft.fuelType == .electric {
            LabeledContent(L10n.pairingTabChargePrice) {
                TextField(
                    "",
                    value: electricChargeBinding,
                    format: .number
                )
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .glassInputField()
            }
            .glassRow(position: .last)
        }
    }

    private var defaultVehicleRow: some View {
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
    }

    private var photoSection: some View {
        VStack(spacing: isFraming ? 12 : 0) {
            HStack(alignment: .center, spacing: 10) {
                if hasPhoto || isFraming || isProcessingPhoto {
                    Spacer(minLength: 8)
                    hero
                    if !isFraming && hasPhoto {
                        photoActionColumn
                    }
                    Spacer(minLength: 8)
                } else {
                    Spacer(minLength: 0)
                    hero
                    Spacer(minLength: 0)
                }
            }
            if isFraming, cropSourceImage != nil {
                VehiclePhotoInlineFraming(
                    workingImage: framingImageBinding,
                    userScale: $frameScale,
                    offset: $frameOffset,
                    cropSide: photoHeroSide,
                    onApply: { Task { await applyFraming() } },
                    onCancel: cancelFraming
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, hasPhoto || isFraming ? 4 : 0)
    }

    private var compactEmptyPhotoRowInsets: EdgeInsets {
        EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16)
    }

    private var photoListRowInsets: EdgeInsets {
        let horizontal: CGFloat = 16
        return EdgeInsets(top: 4, leading: horizontal, bottom: 4, trailing: horizontal)
    }

    private func vehicleFirstRowInsets(compactTop: Bool) -> EdgeInsets {
        let horizontal = GlassTokens.listContentHorizontalInset
        if compactTop {
            return EdgeInsets(top: 8, leading: horizontal, bottom: 10, trailing: horizontal)
        }
        return EdgeInsets(top: 14, leading: horizontal, bottom: 10, trailing: horizontal)
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
        Group {
            if !hasPhoto && !isFraming && !isProcessingPhoto {
                EmptyVehiclePhotoAddButton(
                    title: L10n.pairingTabVehiclePhotoActionAdd,
                    isDisabled: isSaving
                ) {
                    TrailhoundHaptics.selection()
                    showPhotoSourceSheet = true
                }
                .accessibilityHint(L10n.pairingTabVehiclePhotoChooseSubtitle)
            } else {
                heroContent
            }
        }
        .frame(
            width: isFraming ? nil : (hasPhoto || isProcessingPhoto ? activeHeroSide : nil),
            height: isFraming ? nil : (hasPhoto || isProcessingPhoto ? activeHeroSide : nil)
        )
        .animation(reduceMotion ? nil : TrailhoundMotion.photoSettle, value: isFraming)
        .animation(reduceMotion ? nil : TrailhoundMotion.photoSettle, value: hasPhoto)
    }

    private var heroContent: some View {
        Group {
            if isFraming, let cropSourceImage {
                VehiclePhotoFramingCanvas(
                    image: cropSourceImage,
                    userScale: frameScale,
                    offset: frameOffset,
                    side: photoHeroSide,
                    showsCheckerboard: true,
                    showsCropChrome: true,
                    showsExtendedPreview: true
                )
                .modifier(
                    VehiclePhotoFramingGestures(
                        imageSize: cropSourceImage.size,
                        cropSide: photoHeroSide,
                        userScale: $frameScale,
                        offset: $frameOffset
                    )
                )
            } else {
                ZStack {
                    VehicleAvatarView(
                        systemImage: resolvedSystemImage,
                        photoFileName: photoFileNameForPreview,
                        pendingImage: pendingPreview,
                        size: photoHeroSide,
                        cornerRadius: photoHeroSide * 0.18,
                        isElectricAccent: isElectricAccent,
                        showsBrandRing: true,
                        showsSymbolPlate: true
                    )

                    if isProcessingPhoto {
                        RoundedRectangle(cornerRadius: photoHeroSide * 0.18, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .frame(width: photoHeroSide, height: photoHeroSide)
                        ProgressView()
                    }
                }
                .frame(width: photoHeroSide, height: photoHeroSide)
                .contentShape(RoundedRectangle(cornerRadius: photoHeroSide * 0.18, style: .continuous))
            }
        }
    }

    private func handleSourceSheetDismissed() {
        guard let pendingSourceAction else { return }
        let action = pendingSourceAction
        self.pendingSourceAction = nil
        // Sheet + PhotosPicker/camera cannot present in the same turn; SwiftUI
        // drops the second presentation and the user has to tap Add again.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            switch action {
            case .library:
                isPhotosPickerPresented = true
            case .camera:
                showCamera = true
            }
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
        syncUnsavedChanges()
    }

    private func syncUnsavedChanges() {
        unsavedChanges.wrappedValue = hasUnsavedChanges
    }

    private func syncSaveDisabled() {
        saveDisabled.wrappedValue = isSaving || isProcessingPhoto || isFraming
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
            cropSide: photoHeroSide,
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
            if presentation == .standaloneForm {
                dismiss()
            } else {
                reloadDraft()
                syncUnsavedChanges()
            }
        } catch {
            AppErrorPresenter.shared.present(L10n.pairingTabSaveFailed(error.localizedDescription))
        }
    }

    private func updateDraft(_ mutate: (inout VehicleEditorDraft) -> Void) {
        var next = activeDraft
        mutate(&next)
        draft = next
        syncUnsavedChanges()
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

private struct VehicleEditorUnsavedChangesGuard: ViewModifier {
    @Binding var hasUnsavedChanges: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var showDiscardConfirm = false

    func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(hasUnsavedChanges)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if hasUnsavedChanges {
                        Button {
                            showDiscardConfirm = true
                        } label: {
                            Image(systemName: "chevron.backward")
                                .font(.body.weight(.semibold))
                        }
                    }
                }
            }
            .background(NavigationInteractivePopDisabled(disabled: hasUnsavedChanges))
            .alert(L10n.pairingTabDiscardVehicleEditsTitle, isPresented: $showDiscardConfirm) {
                Button(L10n.pairingTabDiscardVehicleEditsLeave, role: .destructive) {
                    dismiss()
                }
                Button(L10n.cancel, role: .cancel) {}
            } message: {
                Text(L10n.pairingTabDiscardVehicleEditsMessage)
            }
    }
}

private struct NavigationInteractivePopDisabled: UIViewControllerRepresentable {
    let disabled: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            uiViewController.navigationController?.interactivePopGestureRecognizer?.isEnabled = !disabled
        }
    }
}

extension View {
    func vehicleEditorUnsavedChangesGuard(_ hasUnsavedChanges: Binding<Bool>) -> some View {
        modifier(VehicleEditorUnsavedChangesGuard(hasUnsavedChanges: hasUnsavedChanges))
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

