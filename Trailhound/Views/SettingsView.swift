import AppIntents
import MessageUI
import SwiftData
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
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
    @State private var showAddPlacePicker = false
    @State private var showReportProblem = false
    @State private var showMailComposer = false
    @State private var showReportShareSheet = false
    @State private var showReportShareFailed = false
    @State private var reportFileURL: URL?

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
                    .glassToggleStyle()
                    .accessibilityIdentifier("settings.recordingSounds")
                    .glassRow(position: .first)
                Text(L10n.settingsSiriShortcutsHint)
                    .font(.footnote)
                    .glassSecondaryInk()
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
                        .glassSecondaryInk()
                        .glassRow(position: favoritePlacesRowCount == 1 ? .only : .first)
                }

                ForEach(Array(places.enumerated()), id: \.element.id) { index, place in
                    NavigationLink {
                        PlacePickerView(editingPlace: place)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: place.kind.systemImage)
                                .font(.subheadline)
                                .glassSecondaryInk()
                                .frame(width: 18)
                            Text(place.name)
                                .font(.subheadline)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(place.kind.displayName)
                                .font(.caption2)
                                .glassSecondaryInk()
                            GlassDisclosureChevron()
                        }
                    }
                    .glassHidesNavigationLinkIndicator()
                    .glassRow(position: favoritePlacePosition(placeIndex: index))
                    .listRowInsets(
                        EdgeInsets(
                            top: 7,
                            leading: GlassTokens.listContentHorizontalInset,
                            bottom: 7,
                            trailing: GlassTokens.listContentHorizontalInset
                        )
                    )
                    .confirmingDeleteSwipe {
                        deletePlace(place)
                    }
                }

                Button {
                    showAddPlacePicker = true
                } label: {
                    Label(L10n.settingsAddPlace, systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                        .glassAccentForeground()
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .glassRow(position: .last)
            } header: {
                Text(L10n.settingsFavoritePlaces)
            } footer: {
                Text(L10n.settingsFavoritePlacesHint)
            }

            CategoryManagementView(focusedField: $focusedField)

            Section {
                Toggle(L10n.settingsSmartCategoryToggle, isOn: $settings.smartCategorySuggestionsEnabled)
                    .glassToggleStyle()
                    .accessibilityIdentifier("settings.smartCategory")
                    .glassRow(position: settings.smartCategorySuggestionsEnabled ? .first : .only)
                if settings.smartCategorySuggestionsEnabled {
                    LabeledContent(L10n.settingsSmartCategoryWorkStart) {
                        Picker(L10n.settingsSmartCategoryWorkStart, selection: $settings.workHourStart) {
                            ForEach(Array(0..<24), id: \.self) { hour in
                                Text(Self.hourLabel(hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .accessibilityIdentifier("settings.smartCategory.workStart")
                    .glassRow(position: .middle)
                    LabeledContent(L10n.settingsSmartCategoryWorkEnd) {
                        Picker(L10n.settingsSmartCategoryWorkEnd, selection: $settings.workHourEnd) {
                            ForEach(Array(0..<24), id: \.self) { hour in
                                Text(Self.hourLabel(hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    .accessibilityIdentifier("settings.smartCategory.workEnd")
                    .glassRow(position: .last)
                }
            } header: {
                Text(L10n.settingsSmartCategorySection)
            } footer: {
                Text(L10n.settingsSmartCategoryHint)
            }

            Section {
                Picker(L10n.settingsAppearancePicker, selection: $settings.appearanceMode) {
                    Text(L10n.settingsAppearanceSystem).tag(AppearanceMode.system)
                    Text(L10n.settingsAppearanceLight).tag(AppearanceMode.light)
                    Text(L10n.settingsAppearanceDark).tag(AppearanceMode.dark)
                }
                .glassSegmentedStyle()
                .labelsHidden()
                .accessibilityIdentifier("settings.appearance")
                .glassRow(position: .first)
                ShellPalettePicker(selection: $settings.shellPalette)
                    .glassRow(position: .last)
            } header: {
                Text(L10n.settingsAppearanceSection)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.settingsAppearanceHint)
                    Text(L10n.settingsShellPaletteHint)
                }
            }

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
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        TextField(settings.fuelCurrency.symbol, value: $settings.fuelPricePerLiter, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.leading)
                            .focused($focusedField, equals: .fuelPrice)
                            .glassInputField()
                            .frame(width: 96)
                        Picker(selection: $settings.fuelCurrency) {
                            ForEach(FuelCurrency.allCases) { currency in
                                Text(currency.symbol).tag(currency)
                            }
                        } label: {
                            Text(L10n.settingsFuelCurrency)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .accessibilityLabel(L10n.settingsFuelCurrency)
                        .foregroundStyle(colorScheme == .dark ? .white : .primary)
                    }
                }
                .glassRow(position: .first)
                Text(L10n.settingsFuelHint)
                    .font(.footnote)
                    .glassSecondaryInk()
                    .glassRow(position: .last)
            }

            Section(L10n.settingsPrivacySection) {
                Toggle(L10n.settingsAppLock, isOn: appLockEnabledBinding)
                    .glassToggleStyle()
                    .glassRow(position: .first)
                Toggle(L10n.settingsConfirmExternalStart, isOn: $settings.confirmExternalRecordingStart)
                    .glassToggleStyle()
                    .glassRow(position: .middle)
                LabeledContent(L10n.settingsPrivacyRadius) {
                    TextField(L10n.settingsPrivacyRadiusUnit, value: $settings.privacyRadiusMeters, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .focused($focusedField, equals: .privacyRadius)
                }
                .glassRow(position: .middle)
                Toggle(L10n.settingsBlurExport, isOn: $settings.blurExportCoordinates)
                    .glassToggleStyle()
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
                        .glassSecondaryInk()
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
                    .glassRow(position: .last)
            }

            Section(L10n.settingsAboutSection) {
                LabeledContent(L10n.settingsVersion, value: "1.1.0")
                    .glassRow(position: .first)
                Button(L10n.settingsReportProblem) {
                    showReportProblem = true
                }
                .accessibilityIdentifier("settings.reportProblem")
                .glassRow(position: .middle)
                Link(L10n.settingsPrivacyPolicy, destination: SupportMail.privacyPolicyURL)
                    .accessibilityIdentifier("settings.privacyPolicy")
                    .glassRow(position: .middle)
                Text(L10n.settingsAboutPrivacy)
                    .font(.footnote)
                    .glassSecondaryInk()
                    .glassRow(position: .last)
            }
        }
        .navigationTitle(L10n.settingsTitle)
        .navigationDestination(isPresented: $showAddPlacePicker) {
            PlacePickerView()
        }
        .glassListChrome()
        .dismissKeyboardOnTap(focus: $focusedField)
        .dismissKeyboardOnScroll()
        .fieldKeyboardAccessory(
            title: focusedField?.title ?? "",
            focusID: focusedField.map { AnyHashable($0) },
            onDone: {
                focusedField = nil
                KeyboardDismiss.dismiss()
            }
        )
        .onAppear {
            runCleanupIfNeeded()
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
        .alert(
            L10n.settingsReportProblemTitle,
            isPresented: $showReportProblem
        ) {
            Button(L10n.settingsReportProblemOpenMail) {
                prepareDiagnosticReport()
            }
            Button(L10n.settingsReportProblemClearLog, role: .destructive) {
                DeleteConfirmPresenter.shared.confirm(.generic) {
                    DevLog.shared.clear()
                    ToastPresenter.shared.show(.deleted)
                }
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: {
            Text(L10n.settingsReportProblemDisclosure)
        }
        .sheet(isPresented: $showMailComposer, onDismiss: cleanupReportFile) {
            MailComposeView(
                recipients: [SupportMail.to],
                subject: diagnosticMailSubject,
                body: L10n.settingsReportProblemMailBody,
                attachmentURL: reportFileURL,
                onFinish: { _ in
                    showMailComposer = false
                }
            )
        }
        .sheet(isPresented: $showReportShareSheet, onDismiss: cleanupReportFile) {
            if let reportFileURL {
                ExportActivityShareSheet(
                    items: [
                        L10n.settingsReportProblemShareHint(SupportMail.to),
                        reportFileURL
                    ]
                )
            }
        }
        .alert(L10n.appLockUnavailableTitle, isPresented: $showAppLockUnavailableAlert) {
            Button(L10n.ok, role: .cancel) {}
        } message: {
            Text(L10n.appLockUnavailable)
        }
        .alert(L10n.settingsReportProblemFailedTitle, isPresented: $showReportShareFailed) {
            Button(L10n.ok, role: .cancel) {}
        } message: {
            Text(L10n.settingsReportProblemFailedMessage)
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

    private var diagnosticMailSubject: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.1.0"
        let os = UIDevice.current.systemVersion
        return "Trailhound \(version) · iOS \(os)"
    }

    private func prepareDiagnosticReport() {
        do {
            UIPasteboard.general.string = SupportMail.to
            let url = try DevLog.shared.makeReportFile()
            reportFileURL = url
            if MFMailComposeViewController.canSendMail() {
                showMailComposer = true
            } else {
                showReportShareSheet = true
            }
        } catch {
            cleanupReportFile()
            showReportShareFailed = true
        }
    }

    private func cleanupReportFile() {
        if let reportFileURL {
            try? FileManager.default.removeItem(at: reportFileURL)
        }
        reportFileURL = nil
    }

    private func favoritePlacePosition(placeIndex: Int) -> GlassRowPosition {
        let offset = places.isEmpty ? 1 : 0
        return GlassRowPosition.index(placeIndex + offset, in: favoritePlacesRowCount)
    }

    private static func hourLabel(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
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
        ToastPresenter.shared.show(.deleted)
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

private struct ShellPalettePicker: View {
    @Binding var selection: ShellPalette
    @Environment(\.colorScheme) private var colorScheme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ShellPalette.allCases) { palette in
                Button {
                    selection = palette
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: palette.gradientColors(for: colorScheme),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        if selection == palette {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 2.5)
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.white)
                        }
                    }
                    .frame(width: 36, height: 36)
                    .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.shellPaletteName(palette))
                .accessibilityAddTraits(selection == palette ? .isSelected : [])
                .accessibilityIdentifier("settings.shellPalette.\(palette.rawValue)")
            }
        }
        .padding(.vertical, 8)
        .accessibilityIdentifier("settings.shellPalette")
        .accessibilityElement(children: .contain)
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
