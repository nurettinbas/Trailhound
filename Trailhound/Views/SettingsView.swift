import AppIntents
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationService.self) private var locationService
    @Environment(TripRecordingService.self) private var tripRecordingService
    @Environment(GeocodingRetryService.self) private var geocodingRetryService
    @Environment(AppLockService.self) private var appLockService
    @Query private var places: [SavedPlace]
    @Query(sort: \Trip.startedAt, order: .reverse) private var trips: [Trip]
    @Bindable private var settings = AppSettings.shared

    @State private var exportURL: URL?
    @State private var showExportSheet = false
    @State private var isExporting = false
    @State private var showAppLockUnavailableAlert = false
    @State private var showShortcutsAutomationGuide = false
    @State private var versionTapCount = 0
    @State private var showRestoreBackupConfirm = false
    @State private var pendingRestoreBackupName = ""
    @State private var showRestoreRestartAlert = false
    @State private var storeBackups: [StoreBackupItem] = []
    @State private var pendingRestoreBackupURL: URL?

    @FocusState private var focusedField: SettingsFocusedField?

    var body: some View {
        Form {
            Section {
                LocationPermissionBanner()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section(L10n.settingsRecordingSection) {
                Toggle(L10n.settingsRecordingSounds, isOn: $settings.recordingSoundsEnabled)
                    .accessibilityIdentifier("settings.recordingSounds")
                    .glassRow(position: .first)
                Text(L10n.settingsSiriShortcutsHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .glassRow(position: .middle)
                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)
                    .accessibilityLabel(L10n.settingsSiriShortcutsLink)
                    .glassRow(position: .middle)
                Button {
                    showShortcutsAutomationGuide = true
                } label: {
                    Label(L10n.settingsShortcutsAutomationGuide, systemImage: "bolt.horizontal.circle")
                }
                .glassRow(position: .last)
            }

            Section {
                if places.isEmpty {
                    Text(L10n.settingsFavoritePlacesEmpty)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .glassRow(position: favoritePlacesRowCount == 1 ? .only : .first)
                }

                ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                    NavigationLink {
                        PlacePickerView(editingPlace: place)
                    } label: {
                        HStack {
                            Image(systemName: place.kind.systemImage)
                            VStack(alignment: .leading) {
                                Text(place.name)
                                Text(place.kind.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .glassRow(position: favoritePlacePosition(placeIndex: index))
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            deletePlace(place)
                        } label: {
                            Label(L10n.delete, systemImage: "trash")
                        }
                        .destructiveTint()
                    }
                }

                NavigationLink(L10n.settingsAddPlace) {
                    PlacePickerView()
                }
                .glassRow(position: .last)
            } header: {
                Text(L10n.settingsFavoritePlaces)
            } footer: {
                Text(L10n.settingsFavoritePlacesHint)
            }

            CategoryManagementView(focusedField: $focusedField)

            Section {
                Button(L10n.settingsOpenSystemSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .glassRow(position: .only)
            } header: {
                Text(L10n.settingsLanguageSection)
            } footer: {
                Text(L10n.settingsLanguageSystemHint)
            }

            Section(L10n.settingsFuelSection) {
                LabeledContent(L10n.settingsFuelPrice) {
                    TextField("TL", value: $settings.fuelPricePerLiter, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .fuelPrice)
                }
                .glassRow(position: .first)
                Text(L10n.settingsFuelHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .glassRow(position: .last)
            }

            Section(L10n.settingsPrivacySection) {
                Toggle(L10n.settingsAppLock, isOn: appLockEnabledBinding)
                    .glassRow(position: .first)
                Toggle(L10n.settingsConfirmExternalStart, isOn: $settings.confirmExternalRecordingStart)
                    .glassRow(position: .middle)
                LabeledContent(L10n.settingsPrivacyRadius) {
                    TextField(L10n.settingsPrivacyRadiusUnit, value: $settings.privacyRadiusMeters, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .privacyRadius)
                }
                .glassRow(position: .middle)
                Toggle(L10n.settingsBlurExport, isOn: $settings.blurExportCoordinates)
                    .glassRow(position: .middle)
                Picker(L10n.settingsAutoDelete, selection: $settings.autoDeleteDays) {
                    Text(L10n.settingsAutoDeleteNever).tag(0)
                    Text(L10n.settingsAutoDeleteDays(30)).tag(30)
                    Text(L10n.settingsAutoDeleteDays(90)).tag(90)
                    Text(L10n.settingsAutoDeleteDays(365)).tag(365)
                }
                .glassRow(position: .last)
            }

            Section(L10n.settingsPermissionsSection) {
                LabeledContent(L10n.settingsLocationPermission) {
                    LocationPermissionBadge(state: locationService.authorizationState)
                }
                .glassRow(position: permissionsPositions.labeled)

                if !locationService.canRecordInBackground {
                    Text(L10n.settingsBackgroundLocationHint)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .glassRow(position: permissionsPositions.hint)
                }

                Button(L10n.settingsRequestLocationPermission) { locationService.requestPermission() }
                    .glassRow(position: permissionsPositions.request)

                Button(L10n.settingsOpenSystemSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .glassRow(position: permissionsPositions.openSettings)
            }

            Section(L10n.settingsBackupSection) {
                Button(L10n.settingsExportJSON) { export(format: .json) }
                    .disabled(isExporting)
                    .glassRow(position: .first)
                Button(L10n.settingsExportCSV) { export(format: .csv) }
                    .disabled(isExporting)
                    .glassRow(position: .middle)
                Button(L10n.settingsExportGPX) { export(format: .gpx) }
                    .disabled(isExporting)
                    .glassRow(position: .middle)
                Button(L10n.settingsExportKML) { export(format: .kml) }
                    .disabled(isExporting)
                    .glassRow(position: .middle)
                Button(L10n.settingsRestoreBestBackup) {
                    promptRestoreBestBackup()
                }
                .disabled(storeBackups.isEmpty)
                .glassRow(position: storeBackups.isEmpty ? .last : .middle)

                if !storeBackups.isEmpty {
                    ForEach(Array(storeBackups.enumerated()), id: \.element.id) { index, item in
                        Button {
                            promptRestore(backup: item)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName)
                                    .font(.subheadline)
                                Text(item.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .glassRow(position: GlassRowPosition.index(index, in: storeBackups.count))
                    }
                }

                if storeBackups.isEmpty {
                    Text(L10n.settingsBackupRestoreHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .glassListRow()
                }
            }

            Section(L10n.settingsAboutSection) {
                LabeledContent(L10n.settingsVersion, value: "1.1.0")
                    .contentShape(Rectangle())
                    .onTapGesture {
                        versionTapCount += 1
                        if versionTapCount >= 5 {
                            settings.developerModeEnabled.toggle()
                            versionTapCount = 0
                        }
                    }
                    .glassRow(position: aboutPositions.version)
                if settings.developerModeEnabled {
                    Toggle(L10n.settingsDeveloperMode, isOn: $settings.developerModeEnabled)
                        .glassRow(position: aboutPositions.developer)
                }
                Text(L10n.settingsAboutPrivacy)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .glassRow(position: aboutPositions.privacy)
            }
        }
        .navigationTitle(L10n.settingsTitle)
        .glassListChrome()
        .dismissKeyboardOnTap(focus: $focusedField)
        .dismissKeyboardOnScroll()
        .keyboardDoneToolbar()
        .onAppear {
            runCleanupIfNeeded()
            refreshStoreBackups()
            Task { await geocodingRetryService.retryPendingTrips(in: modelContext) }
        }
        .sheet(isPresented: $showExportSheet) {
            if let exportURL {
                ExportActivityShareSheet(items: [exportURL])
            }
        }
        .sheet(isPresented: $showShortcutsAutomationGuide) {
            PairingShortcutsAutomationGuideView()
        }
        .alert(L10n.appLockUnavailableTitle, isPresented: $showAppLockUnavailableAlert) {
            Button(L10n.ok, role: .cancel) {}
        } message: {
            Text(L10n.appLockUnavailable)
        }
        .alert(L10n.settingsRestoreConfirmTitle, isPresented: $showRestoreBackupConfirm) {
            Button(L10n.cancel, role: .cancel) {}
            Button(L10n.settingsRestoreAutoBackup, role: .destructive) {
                if let url = pendingRestoreBackupURL {
                    performRestore(backup: url)
                }
            }
        } message: {
            Text(L10n.settingsRestoreConfirmMessage(pendingRestoreBackupName))
        }
        .alert(L10n.settingsRestoreRestartTitle, isPresented: $showRestoreRestartAlert) {
            Button(L10n.settingsRestoreRestartAction) {
                exit(0)
            }
        } message: {
            Text(L10n.settingsRestoreRestartMessage)
        }
        .overlay {
            if isExporting {
                ZStack {
                    Color.black.opacity(0.2)
                        .ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                        Text(L10n.settingsExportPreparing)
                            .font(.subheadline.weight(.medium))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .glassCard(cornerRadius: 16, contentInset: 0)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExporting)
    }

    private var favoritePlacesRowCount: Int {
        (places.isEmpty ? 1 : 0) + places.count + 1
    }

    private var permissionsPositions: (labeled: GlassRowPosition, hint: GlassRowPosition, request: GlassRowPosition, openSettings: GlassRowPosition) {
        if locationService.canRecordInBackground {
            return (.first, .middle, .middle, .last)
        }
        return (.first, .middle, .middle, .last)
    }

    private var aboutPositions: (version: GlassRowPosition, developer: GlassRowPosition, privacy: GlassRowPosition) {
        settings.developerModeEnabled
            ? (.first, .middle, .last)
            : (.first, .only, .last)
    }

    private func favoritePlacePosition(placeIndex: Int) -> GlassRowPosition {
        let offset = places.isEmpty ? 1 : 0
        return GlassRowPosition.index(placeIndex + offset, in: favoritePlacesRowCount)
    }

    private enum ExportFormat {
        case json, csv, gpx, kml

        var fileExtension: String {
            switch self {
            case .json: "json"
            case .csv: "csv"
            case .gpx: "gpx"
            case .kml: "kml"
            }
        }

        var exportFileFormat: ExportService.FileFormat {
            switch self {
            case .json: .json
            case .csv: .csv
            case .gpx: .gpx
            case .kml: .kml
            }
        }
    }

    private func refreshStoreBackups() {
        storeBackups = StoreBackupRecovery.listBackups()
    }

    private func promptRestoreBestBackup() {
        guard let item = StoreBackupRecovery.bestBackup() else {
            AppErrorPresenter.shared.present(L10n.storeRestoreNoBackup)
            return
        }
        promptRestore(backup: item)
    }

    private func promptRestore(backup: StoreBackupItem) {
        pendingRestoreBackupName = "\(backup.displayName) (\(backup.sizeText))"
        pendingRestoreBackupURL = backup.url
        showRestoreBackupConfirm = true
    }

    private func performRestore(backup: URL) {
        do {
            _ = try StoreBackupRecovery.restore(backup: backup)
            pendingRestoreBackupURL = nil
            showRestoreRestartAlert = true
        } catch {
            AppErrorPresenter.shared.present(error.localizedDescription)
        }
    }

    private func export(format: ExportFormat) {
        guard !isExporting else { return }

        isExporting = true
        let completed = trips.filter { $0.endedAt != nil }
        let blurCoordinates = settings.blurExportCoordinates
        let privacyRadius = settings.privacyRadiusMeters
        let savedPlaces = places
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("trailhound-export.\(format.fileExtension)")

        Task { @MainActor in
            let snapshots = ExportService.snapshots(
                from: completed,
                blurCoordinates: blurCoordinates,
                places: savedPlaces,
                privacyRadius: privacyRadius
            )

            do {
                try await Task.detached(priority: .userInitiated) {
                    try ExportService.write(
                        snapshots: snapshots,
                        format: format.exportFileFormat,
                        to: url
                    )
                }.value
                exportURL = url
                showExportSheet = true
            } catch {
                AppErrorPresenter.shared.present(error.localizedDescription)
            }
            isExporting = false
        }
    }

    private func deletePlace(_ place: SavedPlace) {
        modelContext.delete(place)
        try? modelContext.save()
    }

    private func runCleanupIfNeeded() {
        let days = settings.autoDeleteDays
        guard days > 0 else { return }
        _ = try? TripCleanupService.cleanupOldTrips(in: modelContext, olderThanDays: days)
    }

    private var appLockEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.appLockEnabled },
            set: { newValue in
                if newValue, !appLockService.canUseDeviceAuthentication {
                    settings.appLockEnabled = false
                    showAppLockUnavailableAlert = true
                } else {
                    settings.appLockEnabled = newValue
                }
            }
        )
    }
}

private struct StoreBackupItem: Identifiable {
    let url: URL
    let byteCount: Int64
    let modifiedAt: Date?

    var id: String { url.path }
    var displayName: String { url.lastPathComponent }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    var dateText: String {
        guard let modifiedAt else { return "—" }
        return modifiedAt.formatted(date: .abbreviated, time: .shortened)
    }

    var subtitle: String {
        L10n.settingsBackupRestoreRow(size: sizeText, date: dateText)
    }
}

private enum StoreBackupRecovery {
    private static let minimumMeaningfulBytes: Int64 = 8_192

    enum RecoveryError: LocalizedError {
        case noBackupFound

        var errorDescription: String? {
            switch self {
            case .noBackupFound:
                return L10n.storeRestoreNoBackup
            }
        }
    }

    static func listBackups() -> [StoreBackupItem] {
        let directory = ModelContainerFactory.storeURL.deletingLastPathComponent()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else {
            return []
        }

        return entries
            .filter { $0.lastPathComponent.hasPrefix("Trailhound.store.backup-") }
            .compactMap { url -> StoreBackupItem? in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                let bytes = Int64(values?.fileSize ?? 0)
                return StoreBackupItem(url: url, byteCount: bytes, modifiedAt: values?.contentModificationDate)
            }
            .filter { $0.byteCount >= minimumMeaningfulBytes }
            .sorted { lhs, rhs in
                if lhs.byteCount != rhs.byteCount { return lhs.byteCount > rhs.byteCount }
                return (lhs.modifiedAt ?? .distantPast) > (rhs.modifiedAt ?? .distantPast)
            }
    }

    static func bestBackup() -> StoreBackupItem? {
        listBackups().first
    }

    static func restore(backup: URL) throws -> URL {
        let liveStore = ModelContainerFactory.storeURL
        for suffix in ["-shm", "-wal"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: liveStore.path + suffix))
        }
        if FileManager.default.fileExists(atPath: liveStore.path) {
            try FileManager.default.removeItem(at: liveStore)
        }
        try FileManager.default.copyItem(at: backup, to: liveStore)

        UserDefaults.standard.set(false, forKey: "store.recovery.notice.shown")
        return backup
    }
}

struct ExportActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack { SettingsView() }
        .modelContainer(PreviewData.shared.container)
        .environment(LocationService())
        .environment(PreviewData.shared.recordingService)
        .environment(GeocodingRetryService(geocodingService: GeocodingService()))
        .environment(AppLockService())
}
