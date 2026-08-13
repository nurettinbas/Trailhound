import SwiftData
import SwiftUI
import UIKit

struct PairingVehicleEditorView: View {
    let vehicleID: UUID

    @Environment(\.dismiss) private var dismiss
    @Query private var vehicles: [VehicleProfile]
    @State private var hasUnsavedChanges = false
    @State private var saveTrigger = 0
    @State private var saveDisabled = false
    @State private var photoSheet: VehiclePhotoSheetRoute?
    @State private var pendingFramingImage: UIImage?

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
                    saveDisabled: $saveDisabled,
                    photoSheet: $photoSheet,
                    pendingFramingImage: $pendingFramingImage
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
                .glassToolbarSaveControl()
                .disabled(saveDisabled)
                .opacity(saveDisabled ? 0.45 : 1)
            }
        }
        .vehicleEditorUnsavedChangesGuard($hasUnsavedChanges)
        .vehiclePhotoFlowSheets(
            photoSheet: $photoSheet,
            pendingFramingImage: $pendingFramingImage
        )
        .onChange(of: vehicle?.id) { _, newID in
            if newID == nil {
                dismiss()
            }
        }
    }
}

enum VehicleEditorPresentation {
    /// Standalone Form with nav chrome; dismisses after save.
    case standaloneForm
    /// Sections for embedding inside a parent List (vehicle detail); dismisses after save.
    case embeddedInList
}

struct PairingVehicleEditorForm: View {
    let vehicle: VehicleProfile
    let vehicles: [VehicleProfile]
    var presentation: VehicleEditorPresentation = .standaloneForm
    var unsavedChanges: Binding<Bool> = .constant(false)
    var saveTrigger: Binding<Int> = .constant(0)
    var saveDisabled: Binding<Bool> = .constant(false)
    /// Owned by the NavigationStack host so List re-renders cannot drop the sheet.
    var photoSheet: Binding<VehiclePhotoSheetRoute?>
    var pendingFramingImage: Binding<UIImage?>

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
    @State private var showDeleteConfirm = false
    @State private var isSaving = false
    @State private var isProcessingPhoto = false
    @State private var showPhotoActions = false
    @State private var visiblePhotoActionCount = 0
    @State private var brandRingOpacity: Double = 0.45
    @State private var showTapHintBadge = true
    @State private var tapHintBadgeOpacity: Double = 1
    @State private var tapHintBounceOffset: CGFloat = 0
    @State private var didPlayTapHintIntro = false

    private let photoHeroSide: CGFloat = 132
    private let restingBrandRingOpacity: Double = 0.45
    private let tapHintBounceAmplitude: CGFloat = 8

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
            // Sheet dismiss / List reappearance must NOT wipe in-progress photo edits.
            if draft == nil {
                reloadDraft()
            }
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
        .onChange(of: pendingFramingImage.wrappedValue) { _, image in
            guard let image else { return }
            pendingFramingImage.wrappedValue = nil
            // Let capture sheet finish dismissing before growing List framing UI.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                beginInlineFraming(with: image)
            }
        }
        .confirmationDialog(
            L10n.pairingTabVehiclePhotoDeleteTitle,
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(L10n.pairingTabVehiclePhotoRemove, role: .destructive) {
                removePhoto()
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.pairingTabVehiclePhotoDeleteMessage)
        }
    }

    @ViewBuilder
    private var editorSections: some View {
        Section(L10n.pairingTabVehicleSection) {
            photoSection
                .listRowBackground(Color.clear)
                .listRowInsets(photoListRowInsets)
                .listRowSeparator(.hidden)

            vehicleProfileFields(compactTop: true)
        }
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
            HStack(alignment: .center, spacing: 6) {
                if hasPhoto || isFraming || isProcessingPhoto {
                    Spacer(minLength: 4)
                    hero
                        .transition(reduceMotion ? .opacity : TrailhoundMotion.photoHeroTransition)
                    if !isFraming && hasPhoto && visiblePhotoActionCount > 0 {
                        photoActionColumn
                    }
                    Spacer(minLength: 4)
                } else {
                    Spacer(minLength: 0)
                    hero
                        .transition(reduceMotion ? .opacity : TrailhoundMotion.photoHeroTransition)
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
                .transition(reduceMotion ? .opacity : TrailhoundMotion.softRiseTransition)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .animation(reduceMotion ? nil : TrailhoundMotion.photoRemove, value: hasPhoto)
        .animation(reduceMotion ? nil : TrailhoundMotion.photoSettle, value: isFraming)
        .onChange(of: hasPhoto) { _, present in
            if !present { collapsePhotoActions(animated: false) }
        }
        .onChange(of: isFraming) { _, framing in
            if framing { collapsePhotoActions(animated: true) }
        }
        .onChange(of: isProcessingPhoto) { _, processing in
            if processing { collapsePhotoActions(animated: true) }
        }
    }

    private var photoListRowInsets: EdgeInsets {
        let horizontal: CGFloat = 16
        // Extra top so the tap-hint chip can peek above the square without clipping.
        return EdgeInsets(top: 14, leading: horizontal, bottom: 4, trailing: horizontal)
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
            if visiblePhotoActionCount >= 1 {
                photoSideButton(
                    title: L10n.pairingTabVehiclePhotoActionEdit,
                    systemImage: "slider.horizontal.3",
                    role: .edit
                ) {
                    Task { await openFraming() }
                }
                .transition(reduceMotion ? .opacity : TrailhoundMotion.photoActionsTransition)
            }
            if visiblePhotoActionCount >= 2 {
                photoSideButton(
                    title: L10n.pairingTabVehiclePhotoActionChange,
                    systemImage: "photo.on.rectangle.angled",
                    role: .change
                ) {
                    collapsePhotoActions(animated: true)
                    photoSheet.wrappedValue = .flow
                }
                .transition(reduceMotion ? .opacity : TrailhoundMotion.photoActionsTransition)
            }
            if visiblePhotoActionCount >= 3 {
                photoSideButton(
                    title: L10n.pairingTabVehiclePhotoActionDelete,
                    systemImage: "trash",
                    role: .destructive
                ) {
                    showDeleteConfirm = true
                }
                .transition(reduceMotion ? .opacity : TrailhoundMotion.photoActionsTransition)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .disabled(isProcessingPhoto || isSaving)
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
                    side: photoHeroSide,
                    isDisabled: isSaving
                ) {
                    TrailhoundHaptics.selection()
                    photoSheet.wrappedValue = .flow
                }
                .accessibilityHint(L10n.pairingTabVehiclePhotoChooseSubtitle)
            } else {
                heroContent
            }
        }
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
                filledPhotoHero
            }
        }
    }

    private var photoGlintID: String {
        if let pendingPreview {
            return "pending-\(ObjectIdentifier(pendingPreview))"
        }
        return photoFileNameForPreview ?? "none"
    }

    private var filledPhotoHero: some View {
        let corner = photoHeroSide * 0.18
        return Button {
            guard hasPhoto, !isProcessingPhoto, !isSaving else { return }
            TrailhoundHaptics.selection()
            dismissTapHintBadge()
            togglePhotoActions()
        } label: {
            ZStack {
                VehicleAvatarView(
                    systemImage: resolvedSystemImage,
                    photoFileName: photoFileNameForPreview,
                    pendingImage: pendingPreview,
                    size: photoHeroSide,
                    cornerRadius: corner,
                    isElectricAccent: isElectricAccent,
                    showsBrandRing: true,
                    brandRingOpacity: brandRingOpacity,
                    showsSymbolPlate: true
                )
                .photoEntranceGlint(cornerRadius: corner, id: photoGlintID) {
                    playCollapsedRingPulse()
                }

                if isProcessingPhoto {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .frame(width: photoHeroSide, height: photoHeroSide)
                    ProgressView()
                }
            }
            .frame(width: photoHeroSide, height: photoHeroSide)
            .contentShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            // Chip draws outside the square; layout stays 132×132 so actions stay centered.
            .overlay(alignment: .topTrailing) {
                if showTapHintBadge, hasPhoto, !isProcessingPhoto {
                    VehiclePhotoCornerChip(title: L10n.pairingTabVehiclePhotoTapHint)
                        .opacity(tapHintBadgeOpacity)
                        .offset(x: 14, y: -10 + tapHintBounceOffset)
                }
            }
        }
        .buttonStyle(VehiclePhotoPressStyle())
        .disabled(isProcessingPhoto || isSaving || !hasPhoto)
        .accessibilityLabel(L10n.pairingTabVehiclePhotoChoose)
        .accessibilityHint(L10n.pairingTabVehiclePhotoTapHint)
        .accessibilityAction(named: L10n.pairingTabVehiclePhotoActionEdit) {
            Task { await openFraming() }
        }
        .accessibilityAction(named: L10n.pairingTabVehiclePhotoActionChange) {
            collapsePhotoActions(animated: false)
            photoSheet.wrappedValue = .flow
        }
        .accessibilityAction(named: L10n.pairingTabVehiclePhotoActionDelete) {
            showDeleteConfirm = true
        }
        .onAppear(perform: playTapHintIntroIfNeeded)
        .onChange(of: photoGlintID) { _, _ in
            didPlayTapHintIntro = false
            showTapHintBadge = true
            tapHintBadgeOpacity = 1
            tapHintBounceOffset = 0
            playTapHintIntroIfNeeded()
        }
    }

    private func dismissTapHintBadge() {
        showTapHintBadge = false
        tapHintBadgeOpacity = 0
        tapHintBounceOffset = 0
    }

    private func playTapHintIntroIfNeeded() {
        guard hasPhoto, !isFraming, !isProcessingPhoto else { return }
        guard !didPlayTapHintIntro else { return }
        didPlayTapHintIntro = true

        if reduceMotion {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1200))
                guard showTapHintBadge else { return }
                withAnimation(.easeOut(duration: 0.35)) {
                    tapHintBadgeOpacity = 0
                }
                try? await Task.sleep(for: .milliseconds(350))
                if tapHintBadgeOpacity == 0 {
                    showTapHintBadge = false
                }
            }
            return
        }

        Task { @MainActor in
            let bounceDuration: TimeInterval = 0.64
            let bounceStep: Duration = .milliseconds(640)
            let fadeDuration: TimeInterval = 0.7

            for _ in 0 ..< 2 {
                guard showTapHintBadge else { return }
                withAnimation(.easeInOut(duration: bounceDuration)) {
                    tapHintBounceOffset = -tapHintBounceAmplitude
                }
                try? await Task.sleep(for: bounceStep)
                guard showTapHintBadge else { return }
                withAnimation(.easeInOut(duration: bounceDuration)) {
                    tapHintBounceOffset = 0
                }
                try? await Task.sleep(for: bounceStep)
            }

            guard showTapHintBadge else { return }
            withAnimation(.easeOut(duration: fadeDuration)) {
                tapHintBadgeOpacity = 0
            }
            try? await Task.sleep(for: .milliseconds(Int(fadeDuration * 1000)))
            if tapHintBadgeOpacity == 0 {
                showTapHintBadge = false
            }
        }
    }

    private func togglePhotoActions() {
        if showPhotoActions {
            collapsePhotoActions(animated: true)
        } else {
            expandPhotoActions()
        }
    }

    private func expandPhotoActions() {
        dismissTapHintBadge()
        showPhotoActions = true
        brandRingOpacity = restingBrandRingOpacity
        if reduceMotion {
            visiblePhotoActionCount = 3
            return
        }
        visiblePhotoActionCount = 0
        Task { @MainActor in
            for count in 1 ... 3 {
                guard showPhotoActions else { return }
                withAnimation(TrailhoundMotion.photoActionsReveal) {
                    visiblePhotoActionCount = count
                }
                if count < 3 {
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
        }
    }

    private func collapsePhotoActions(animated: Bool) {
        showPhotoActions = false
        let animation: Animation? = animated
            ? (reduceMotion ? .easeOut(duration: 0.12) : TrailhoundMotion.photoActionsReveal)
            : nil
        withAnimation(animation) {
            visiblePhotoActionCount = 0
        }
        brandRingOpacity = restingBrandRingOpacity
    }

    private func playCollapsedRingPulse() {
        guard !reduceMotion, hasPhoto, !showPhotoActions, !isFraming else { return }
        withAnimation(.easeInOut(duration: 0.45)) {
            brandRingOpacity = 0.9
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            guard !showPhotoActions else {
                brandRingOpacity = restingBrandRingOpacity
                return
            }
            withAnimation(.easeInOut(duration: 0.45)) {
                brandRingOpacity = restingBrandRingOpacity
            }
        }
    }

    private func reloadDraft() {
        draft = VehicleEditorDraft(from: vehicle)
        pendingPreview = nil
        pendingFramingImage.wrappedValue = nil
        cropSourceImage = nil
        isFraming = false
        frameScale = VehiclePhotoCropMath.defaultUserScale
        frameOffset = .zero
        collapsePhotoActions(animated: false)
        brandRingOpacity = restingBrandRingOpacity
        didPlayTapHintIntro = false
        showTapHintBadge = true
        tapHintBadgeOpacity = 1
        tapHintBounceOffset = 0
        syncUnsavedChanges()
    }

    private func syncUnsavedChanges() {
        unsavedChanges.wrappedValue = hasUnsavedChanges
    }

    private func syncSaveDisabled() {
        saveDisabled.wrappedValue = isSaving || isProcessingPhoto || isFraming
    }

    private func removePhoto() {
        TrailhoundHaptics.destructive()
        collapsePhotoActions(animated: true)
        withAnimation(reduceMotion ? nil : TrailhoundMotion.photoRemove) {
            updateDraft { $0.photoEdit = .removed }
            pendingPreview = nil
            cropSourceImage = nil
            isFraming = false
        }
    }

    private func beginInlineFraming(with image: UIImage) {
        let prepared = VehiclePhotoCropMath.prepareForCrop(image)
        cropSourceImage = prepared
        frameScale = VehiclePhotoCropMath.defaultUserScale
        frameOffset = .zero
        collapsePhotoActions(animated: true)
        withAnimation(reduceMotion ? nil : TrailhoundMotion.photoSettle) {
            isFraming = true
        }
    }

    private func openFraming() async {
        collapsePhotoActions(animated: true)
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
            photoSheet.wrappedValue = .flow
            return
        }
        isProcessingPhoto = true
        defer { isProcessingPhoto = false }
        if let image = await VehiclePhotoStore.shared.image(fileName: fileName) {
            beginInlineFraming(with: image)
        } else {
            photoSheet.wrappedValue = .flow
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
            // Pop back to My Vehicles / pairing list; toast stays on the host.
            dismiss()
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

