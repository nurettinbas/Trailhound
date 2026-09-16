import AppIntents
import SwiftData
import SwiftUI
import UIKit

struct PairingShortcutsAutomationCard: View {
    var onOpenGuide: () -> Void
    var onOpenTest: () -> Void
    var onOpenTroubleshoot: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Bindable private var settings = AppSettings.shared
    @Bindable private var setup = ShortcutsSetupStore.shared

    var body: some View {
        Group {
            if settings.hasCompletedShortcutsGuide {
                completedRow
            } else {
                Button(action: onOpenGuide) {
                    cardRow {
                        Text(L10n.pairingShortcutsGuideCardButton)
                            .font(.caption2.weight(.semibold))
                            .glassAccentForeground()
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .glassDisclosureInk()
                    }
                }
                .buttonStyle(.glassPlainHit)
            }
        }
    }

    private var completedRow: some View {
        cardRow {
            VStack(alignment: .trailing, spacing: 6) {
                Button(action: onOpenTest) {
                    Text(L10n.pairingShortcutsGuideCardTest)
                        .font(.caption2.weight(.semibold))
                        .glassAccentForeground()
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.glassPlainHit)

                Button(action: onOpenTroubleshoot) {
                    Text(L10n.pairingShortcutsGuideCardTroubleshoot)
                        .font(.caption2.weight(.semibold))
                        .glassAccentForeground()
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.glassPlainHit)
            }
        }
    }

    private func cardRow<Trailing: View>(@ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(shellPalette.tintColor(for: colorScheme).opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.body)
                    .glassAccentForeground()
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.pairingShortcutsGuideCardTitle)
                    .font(.subheadline.weight(.semibold))
                    .glassPrimaryInk()
                Text(cardSubtitle)
                    .font(.caption)
                    .glassSecondaryInk()
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            trailing()
        }
        .contentShape(Rectangle())
    }

    private var cardSubtitle: String {
        if settings.hasCompletedShortcutsGuide, setup.hasCompletedTest {
            return L10n.pairingShortcutsGuideCardTested
        }
        return L10n.pairingShortcutsGuideCardSubtitle
    }
}

struct PairingShortcutsAutomationGuideView: View {
    var entry: ShortcutsWizardEntry = .start

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Environment(LocationService.self) private var locationService
    @Bindable private var settings = AppSettings.shared
    @Bindable private var setup = ShortcutsSetupStore.shared
    @Query private var vehicles: [VehicleProfile]

    @State private var stepIndex = 0
    @State private var completedStepIDs: Set<String> = []
    @State private var stepCompletePulse = false
    @State private var heroBeat: CGFloat = 0
    @State private var didApplyEntry = false
    @State private var editingVehicle: EditingVehicleSheet?
    @State private var testOutcome: ShortcutsWizardTestOutcome?
    @State private var watchArmed = false

    private var brandAccent: Color { shellPalette.tintColor(for: colorScheme) }
    private var steps: [GuideWizardStep] { Self.makeSteps() }
    private var currentStep: GuideWizardStep { steps[min(stepIndex, steps.count - 1)] }
    private var isLastStep: Bool { stepIndex >= steps.count - 1 }
    private var isFirstStep: Bool { stepIndex <= 0 }

    private var sortedVehicles: [VehicleProfile] {
        vehicles.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var selectedVehicleName: String? {
        guard let id = setup.vehicleID else { return nil }
        return vehicles.first(where: { $0.id == id })?.name
    }

    private var canAdvance: Bool {
        switch currentStep.kind {
        case .trigger: setup.trigger != nil
        case .vehicle: setup.vehicleID != nil
        default: true
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphericBackground().ignoresSafeArea()

                VStack(spacing: 0) {
                    progressRail
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 8)

                    summaryStrip
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)

                    heroChrome
                        .padding(.bottom, 8)

                    if currentStep.kind == .silentStart,
                       locationService.authorizationState != .authorizedAlways {
                        LocationAlwaysRequiredBanner()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }

                    ScrollView {
                        stepContent(for: currentStep)
                            .id(currentStep.id)
                            .transition(.opacity)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                    }
                    .scrollBounceBehavior(.basedOnSize)

                    bottomChrome
                }
            }
            .navigationTitle(L10n.pairingShortcutsGuideTitle)
            .navigationBarTitleDisplayMode(.inline)
            .glassNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        GlassToolbarTitle(title: L10n.pairingShortcutsGuideDone)
                    }
                }
            }
            .animation(reduceMotion ? nil : TrailhoundMotion.snappy, value: stepIndex)
            .onAppear(perform: applyEntryIfNeeded)
            .sheet(item: $editingVehicle) { item in
                NavigationStack {
                    VehicleDetailView(vehicleID: item.id)
                }
            }
        }
    }

    private var progressRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.pairingShortcutsGuideStepProgress(current: stepIndex + 1, total: steps.count))
                .font(.caption.weight(.semibold))
                .glassSecondaryInk()

            GeometryReader { geo in
                let progress = CGFloat(stepIndex + 1) / CGFloat(max(steps.count, 1))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                    Capsule()
                        .fill(brandAccent)
                        .frame(width: max(8, geo.size.width * progress))
                }
            }
            .frame(height: 4)
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 8) {
            if let trigger = setup.trigger {
                Label(triggerTitle(trigger), systemImage: resolvedTriggerSymbol(for: trigger))
                    .labelStyle(.titleAndIcon)
            }
            if let name = selectedVehicleName {
                Text(name)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .font(.caption.weight(.semibold))
        .glassSecondaryInk()
        .frame(minHeight: 16)
    }

    @ViewBuilder
    private var heroChrome: some View {
        switch currentStep.kind {
        case .silentStart, .handoff:
            ZStack {
                OnboardingHeroScene(
                    kind: currentStep.kind == .handoff ? .shortcutsLink : .welcomeDrive,
                    driveInProgress: 1,
                    beatProgress: heroBeat,
                    isAnimating: scenePhase == .active && !reduceMotion
                )

                if stepCompletePulse {
                    SoftPulseRing(
                        color: UIColor(brandAccent),
                        isActive: true,
                        reduceMotion: reduceMotion
                    )
                    .frame(width: 72, height: 72)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .frame(height: 140)
            .padding(.horizontal, 16)
        case .test:
            ZStack {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(brandAccent)
                if stepCompletePulse {
                    SoftPulseRing(
                        color: UIColor(brandAccent),
                        isActive: true,
                        reduceMotion: reduceMotion
                    )
                    .frame(width: 72, height: 72)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .frame(height: 88)
        default:
            EmptyView()
        }
    }

    private var bottomChrome: some View {
        HStack(spacing: 12) {
            Button {
                goBack()
            } label: {
                Text(L10n.pairingShortcutsGuideBack)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isFirstStep)

            Button {
                advance()
            } label: {
                Text(isLastStep ? L10n.pairingShortcutsGuideDone : L10n.pairingShortcutsGuideNext)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .trailhoundProminentButton()
            .tint(brandAccent)
            .disabled(!canAdvance)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            GlassToolbarControlBackground(shape: Rectangle())
        }
    }

    @ViewBuilder
    private func stepContent(for step: GuideWizardStep) -> some View {
        switch step.kind {
        case .trigger:
            triggerSection
        case .vehicle:
            vehicleSection
        case .silentStart:
            silentStartSection
        case .connect:
            connectSection
        case .disconnect:
            disconnectSection
        case .handoff:
            handoffSection
        case .test:
            testSection
        case .checklist:
            checklistSection
        }
    }

    private var triggerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            guideSectionHeader(title: L10n.pairingShortcutsGuideTriggersTitle, symbol: "list.bullet.rectangle")
            Text(L10n.pairingShortcutsGuideTriggersIntro)
                .font(.subheadline)
                .glassSecondaryInk()
                .fixedSize(horizontal: false, vertical: true)

            triggerChoice(
                trigger: .bluetooth,
                title: L10n.pairingShortcutsGuideTriggersBluetoothTitle,
                body: L10n.pairingShortcutsGuideTriggersBluetoothBody
            )
            triggerChoice(
                trigger: .carplay,
                title: L10n.pairingShortcutsGuideTriggersCarPlayTitle,
                body: L10n.pairingShortcutsGuideTriggersCarPlayBody,
                note: L10n.pairingShortcutsGuideTriggersCarPlayWirelessNote
            )
            triggerChoice(
                trigger: .wifi,
                title: L10n.pairingShortcutsGuideTriggersWiFiTitle,
                body: L10n.pairingShortcutsGuideTriggersWiFiBody
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassChrome(cornerRadius: 12)
    }

    private func triggerChoice(
        trigger: ShortcutsSetupTrigger,
        title: String,
        body: String,
        note: String? = nil
    ) -> some View {
        let selected = setup.trigger == trigger
        return Button {
            setup.persistTrigger(trigger)
            TrailhoundHaptics.selection()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: resolvedTriggerSymbol(for: trigger))
                    .font(.title3.weight(.semibold))
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(body)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    if let note {
                        Text(note)
                            .font(.caption2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Color.white : GlassText.primary(for: colorScheme))
        }
        .buttonStyle(.glassPlainHit)
        .trailhoundCardPress()
        .glassNestedChoice(isSelected: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var vehicleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            guideSectionHeader(title: L10n.pairingShortcutsGuideVehicleTitle, symbol: "car.fill")
            Text(L10n.pairingShortcutsGuideVehicleBody)
                .font(.subheadline)
                .glassSecondaryInk()
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.pairingShortcutsGuideVehicleNote)
                .font(.footnote)
                .glassSecondaryInk()
                .fixedSize(horizontal: false, vertical: true)

            if sortedVehicles.isEmpty {
                Text(L10n.pairingShortcutsGuideVehicleEmpty)
                    .font(.subheadline)
                    .glassSecondaryInk()
            } else {
                VStack(spacing: 8) {
                    ForEach(sortedVehicles, id: \.id) { vehicle in
                        vehicleChoice(vehicle)
                    }
                }
            }

            Button(action: addVehicle) {
                Text(L10n.pairingShortcutsGuideVehicleAdd)
            }
            .trailhoundCompactProminentButton()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassChrome(cornerRadius: 12)
    }

    private func vehicleChoice(_ vehicle: VehicleProfile) -> some View {
        let selected = setup.vehicleID == vehicle.id
        return Button {
            setup.persistVehicleID(vehicle.id)
            TrailhoundHaptics.selection()
        } label: {
            HStack(spacing: 12) {
                VehicleAvatarView(
                    systemImage: vehicle.systemImage,
                    photoFileName: vehicle.photoFileName,
                    size: 36,
                    cornerRadius: 8,
                    isElectricAccent: vehicle.fuelType == .electric,
                    showsPhotoShine: vehicle.photoFileName != nil
                )
                Text(vehicle.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .foregroundStyle(selected ? Color.white : GlassText.primary(for: colorScheme))
        }
        .buttonStyle(.glassPlainHit)
        .trailhoundCardPress()
        .glassNestedChoice(isSelected: selected)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var silentStartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            guideSectionHeader(title: L10n.pairingShortcutsGuidePrerequisiteTitle, symbol: "checkmark.shield")
            Text(L10n.pairingShortcutsGuidePrerequisiteBody)
                .font(.subheadline)
                .glassSecondaryInk()
                .fixedSize(horizontal: false, vertical: true)
            Toggle(L10n.pairingShortcutsGuideSilentStart, isOn: $settings.confirmExternalRecordingStart.inverted)
                .glassToggleStyle()
                .font(.subheadline)
                .tint(brandAccent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassChrome(cornerRadius: 12)
    }

    private var connectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            guideSectionHeader(title: L10n.pairingShortcutsGuideConnectTitle, symbol: "play.circle.fill")
            ForEach(Array(connectSteps.enumerated()), id: \.offset) { index, _ in
                numberedInstructionRow(
                    number: index + 1,
                    icon: connectIcons[index],
                    text: connectStepText(index)
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassChrome(cornerRadius: 12)
    }

    private var disconnectSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            guideSectionHeader(title: L10n.pairingShortcutsGuideDisconnectTitle, symbol: "stop.circle.fill")
            ForEach(Array(disconnectSteps.enumerated()), id: \.offset) { index, text in
                numberedInstructionRow(
                    number: index + 1,
                    icon: disconnectIcons[index],
                    text: text
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassChrome(cornerRadius: 12)
    }

    private func numberedInstructionRow(number: Int, icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(brandAccent)
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(brandAccent)
                Text(text)
                    .font(.subheadline)
                    .glassPrimaryInk()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .glassNestedChoice(isSelected: false)
    }

    private var handoffSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            guideSectionHeader(title: L10n.pairingShortcutsGuideHandoffTitle, symbol: "arrow.up.forward.app")
            Text(L10n.pairingShortcutsGuideHandoffBody)
                .font(.subheadline)
                .glassSecondaryInk()
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.pairingShortcutsGuideNote)
                .font(.footnote)
                .glassSecondaryInk()
                .fixedSize(horizontal: false, vertical: true)
            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(L10n.pairingShortcutsGuideOpenShortcuts)
            Toggle(
                L10n.pairingShortcutsGuideFinishedToggle,
                isOn: Binding(
                    get: { settings.hasCompletedShortcutsGuide },
                    set: { newValue in
                        if newValue {
                            settings.markShortcutsGuideCompleted()
                            TrailhoundHaptics.pairingSucceeded()
                            ToastPresenter.shared.show(.shortcutsGuideFinished)
                            playStepComplete()
                        }
                    }
                )
            )
            .font(.subheadline)
            .tint(brandAccent)
            .disabled(settings.hasCompletedShortcutsGuide)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassChrome(cornerRadius: 12)
    }

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            guideSectionHeader(title: L10n.pairingShortcutsGuideTestTitle, symbol: "bolt.horizontal.circle")
            Text(L10n.pairingShortcutsGuideTestBody)
                .font(.subheadline)
                .glassSecondaryInk()
                .fixedSize(horizontal: false, vertical: true)

            Button(action: runWizardTest) {
                Text(L10n.pairingShortcutsGuideTestButton)
                    .frame(maxWidth: .infinity)
            }
            .trailhoundProminentButton()
            .tint(brandAccent)

            if let testOutcome {
                Text(outcomeText(testOutcome))
                    .font(.subheadline.weight(.medium))
                    .glassPrimaryInk()
                    .fixedSize(horizontal: false, vertical: true)
                    .glassNestedChoice(isSelected: false)
            }

            if testOutcome == .recordingStarted || testOutcome == .awaitingConfirmation {
                Button(action: stopWizardTest) {
                    Text(L10n.pairingShortcutsGuideTestStop)
                        .frame(maxWidth: .infinity)
                }
                .trailhoundDestructiveButton()
            }

            Toggle(L10n.pairingShortcutsGuideTestWatch, isOn: watchBinding)
                .font(.subheadline)
                .tint(brandAccent)
            if watchArmed || setup.pendingWatchAt != nil {
                Text(L10n.pairingShortcutsGuideTestWatchArmed)
                    .font(.caption)
                    .glassSecondaryInk()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassChrome(cornerRadius: 12)
    }

    private var watchBinding: Binding<Bool> {
        Binding(
            get: { watchArmed || setup.pendingWatchAt != nil },
            set: { newValue in
                watchArmed = newValue
                if newValue {
                    setup.armExternalStartWatch()
                } else {
                    _ = setup.consumePendingWatchIfReached(now: Date.distantPast)
                }
            }
        )
    }

    private var checklistSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            guideSectionHeader(title: L10n.pairingShortcutsGuideChecklistTitle, symbol: "checklist")
            Text(L10n.pairingShortcutsGuideChecklistIntro)
                .font(.subheadline)
                .glassSecondaryInk()
                .fixedSize(horizontal: false, vertical: true)
            ForEach(ShortcutsSetupChecklistItem.allCases) { item in
                checklistRow(item)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassChrome(cornerRadius: 12)
    }

    private func checklistRow(_ item: ShortcutsSetupChecklistItem) -> some View {
        let checked = setup.isChecked(item)
        return Button {
            setup.toggle(item)
            TrailhoundHaptics.selection()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(checked ? brandAccent : GlassText.secondary(for: colorScheme))
                Text(checklistText(item))
                    .font(.subheadline)
                    .glassPrimaryInk()
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.glassPlainHit)
        .glassNestedChoice(isSelected: false)
    }

    private func guideSectionHeader(title: String, symbol: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(brandAccent)
            Text(title)
                .font(.headline)
        }
    }

    private var connectSteps: [String] {
        [
            L10n.pairingShortcutsGuideConnectStep1,
            L10n.pairingShortcutsGuideConnectStep2,
            L10n.pairingShortcutsGuideConnectStep3,
            L10n.pairingShortcutsGuideConnectStep4,
            L10n.pairingShortcutsGuideConnectStep5,
            L10n.pairingShortcutsGuideConnectStep6,
            L10n.pairingShortcutsGuideConnectStep7
        ]
    }

    private var disconnectSteps: [String] {
        [
            L10n.pairingShortcutsGuideDisconnectStep1,
            L10n.pairingShortcutsGuideDisconnectStep2,
            L10n.pairingShortcutsGuideDisconnectStep3,
            L10n.pairingShortcutsGuideDisconnectStep4
        ]
    }

    private var connectIcons: [String] {
        [
            "apps.iphone",
            "square.and.pencil",
            "car.side.fill",
            "bolt.horizontal.circle",
            "point.3.connected.trianglepath.dotted",
            "arrow.up.forward.app",
            "bell.slash.fill"
        ]
    }

    private var disconnectIcons: [String] {
        ["plus.circle.fill", "point.3.connected.trianglepath.dotted", "stop.fill", "bell.slash.fill"]
    }

    private func connectStepText(_ index: Int) -> String {
        guard index == 4 else { return connectSteps[index] }
        switch setup.trigger {
        case .bluetooth: return L10n.pairingShortcutsGuideConnectStep5Bluetooth
        case .carplay: return L10n.pairingShortcutsGuideConnectStep5CarPlay
        case .wifi: return L10n.pairingShortcutsGuideConnectStep5WiFi
        case nil: return L10n.pairingShortcutsGuideConnectStep5
        }
    }

    private func triggerTitle(_ trigger: ShortcutsSetupTrigger) -> String {
        switch trigger {
        case .bluetooth: L10n.pairingShortcutsGuideTriggersBluetoothTitle
        case .carplay: L10n.pairingShortcutsGuideTriggersCarPlayTitle
        case .wifi: L10n.pairingShortcutsGuideTriggersWiFiTitle
        }
    }

    private func resolvedTriggerSymbol(for trigger: ShortcutsSetupTrigger) -> String {
        switch trigger {
        case .bluetooth:
            return UIImage(systemName: "bluetooth") != nil
                ? "bluetooth"
                : "antenna.radiowaves.left.and.right"
        case .carplay:
            return UIImage(systemName: "carplay") != nil
                ? "carplay"
                : "play.circle.fill"
        case .wifi:
            return "wifi"
        }
    }

    private func outcomeText(_ outcome: ShortcutsWizardTestOutcome) -> String {
        switch outcome {
        case .noVehicle: L10n.pairingShortcutsGuideTestResultNoVehicle
        case .awaitingConfirmation: L10n.pairingShortcutsGuideTestResultConfirm
        case .recordingStarted: L10n.pairingShortcutsGuideTestResultStarted
        case .locationNotAlways: L10n.pairingShortcutsGuideTestResultNoLocation
        case .idle: L10n.pairingShortcutsGuideTestResultIdle
        }
    }

    private func checklistText(_ item: ShortcutsSetupChecklistItem) -> String {
        switch item {
        case .personalAutomationEnabled: L10n.pairingShortcutsGuideChecklistPersonalAutomation
        case .askBeforeRunningOff: L10n.pairingShortcutsGuideChecklistAskBeforeRunning
        case .runShortcutNamed: L10n.pairingShortcutsGuideChecklistRunShortcut
        case .secondVehicleSecondShortcut: L10n.pairingShortcutsGuideChecklistSecondVehicle
        case .locationAlways: L10n.pairingShortcutsGuideChecklistLocationAlways
        case .silentStart: L10n.pairingShortcutsGuideChecklistSilentStart
        case .carplayWireless: L10n.pairingShortcutsGuideChecklistCarPlayWireless
        case .focusDoesNotBlock: L10n.pairingShortcutsGuideChecklistFocus
        case .returnViaShortcutsLink: L10n.pairingShortcutsGuideChecklistReturnLink
        }
    }

    private func runWizardTest() {
        let recording = AppServices.runtime.tripRecordingService
        guard let vehicleID = setup.vehicleID else {
            testOutcome = .noVehicle
            return
        }
        setup.markTestInFlight()
        ShortcutStartVehicleSelection.apply(
            vehicleID: vehicleID,
            using: recording
        )
        RecordingControlBridge.requestStartFromControlSurface()
        AppServices.runtime.processPendingRecordingRequests()
        let outcome = ShortcutsWizardTestClassifier.classify(
            hasVehicle: true,
            awaitingConfirmation: settings.awaitingExternalStartConfirmation,
            isRecording: recording.state.isActiveSession,
            locationAlways: locationService.authorizationState == .authorizedAlways
        )
        testOutcome = outcome
        if outcome == .recordingStarted || outcome == .awaitingConfirmation {
            setup.markTestCompleted()
            playStepComplete()
        }
        TrailhoundHaptics.selection()
    }

    private func stopWizardTest() {
        AppServices.runtime.tripRecordingService.discardActiveRecordingSession()
        testOutcome = nil
        TrailhoundHaptics.selection()
    }

    private func addVehicle() {
        let vehicle = VehicleProfile(
            name: suggestedVehicleName(),
            consumption: settings.fuelLitersPer100km
        )
        modelContext.insert(vehicle)
        guard (try? modelContext.save()) != nil else { return }
        setup.persistVehicleID(vehicle.id)
        if !UITestSupport.shouldSkipExternalEffects {
            TrailhoundShortcuts.updateAppShortcutParameters()
        }
        editingVehicle = EditingVehicleSheet(id: vehicle.id)
    }

    private func suggestedVehicleName() -> String {
        let base = L10n.vehicleDefaultName
        let existing = Set(vehicles.map(\.name))
        if !existing.contains(base) { return base }
        var index = 2
        while existing.contains("\(base) \(index)") {
            index += 1
        }
        return "\(base) \(index)"
    }

    private func applyEntryIfNeeded() {
        guard !didApplyEntry else { return }
        didApplyEntry = true
        switch entry {
        case .start:
            break
        case .test:
            stepIndex = steps.firstIndex { $0.kind == .test } ?? 6
        case .checklist:
            stepIndex = steps.firstIndex { $0.kind == .checklist } ?? 7
        }
        watchArmed = setup.pendingWatchAt != nil
    }

    private func advance() {
        markCurrentStepComplete()
        if isLastStep {
            dismiss()
            return
        }
        let delayMs: UInt64 = reduceMotion ? 0 : 180
        Task { @MainActor in
            if delayMs > 0 {
                try? await Task.sleep(for: .milliseconds(delayMs))
            }
            withAnimation(reduceMotion ? nil : TrailhoundMotion.cardSpring) {
                stepIndex += 1
            }
            if currentStep.kind == .handoff {
                withAnimation(reduceMotion ? nil : TrailhoundMotion.pinPop) {
                    heroBeat = 1
                }
            }
        }
    }

    private func goBack() {
        guard !isFirstStep else { return }
        withAnimation(reduceMotion ? nil : TrailhoundMotion.snappy) {
            stepIndex -= 1
        }
    }

    private func markCurrentStepComplete() {
        let id = currentStep.id
        guard !completedStepIDs.contains(id) else { return }
        completedStepIDs.insert(id)
        TrailhoundHaptics.selection()
        playStepComplete()
    }

    private func playStepComplete() {
        guard !reduceMotion else { return }
        stepCompletePulse = true
        withAnimation(TrailhoundMotion.pinPop) {
            heroBeat = 1
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(.easeOut(duration: 0.2)) {
                stepCompletePulse = false
            }
            if currentStep.kind != .handoff {
                heroBeat = 0
            }
        }
    }

    private static func makeSteps() -> [GuideWizardStep] {
        [
            GuideWizardStep(id: "trigger", kind: .trigger),
            GuideWizardStep(id: "vehicle", kind: .vehicle),
            GuideWizardStep(id: "silentStart", kind: .silentStart),
            GuideWizardStep(id: "connect", kind: .connect),
            GuideWizardStep(id: "disconnect", kind: .disconnect),
            GuideWizardStep(id: "handoff", kind: .handoff),
            GuideWizardStep(id: "test", kind: .test),
            GuideWizardStep(id: "checklist", kind: .checklist)
        ]
    }
}

private struct GuideWizardStep: Identifiable, Equatable {
    enum Kind: Equatable {
        case trigger
        case vehicle
        case silentStart
        case connect
        case disconnect
        case handoff
        case test
        case checklist
    }

    let id: String
    let kind: Kind
}

private extension Binding where Value == Bool {
    var inverted: Binding<Bool> {
        Binding(
            get: { !wrappedValue },
            set: { wrappedValue = !$0 }
        )
    }
}

private struct EditingVehicleSheet: Identifiable {
    let id: UUID
}

#Preview {
    PairingShortcutsAutomationGuideView()
        .modelContainer(PreviewData.shared.container)
        .environment(LocationService())
}
