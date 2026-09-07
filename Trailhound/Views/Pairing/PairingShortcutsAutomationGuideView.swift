import AppIntents
import SwiftUI
import UIKit

struct PairingShortcutsAutomationCard: View {
    let onOpenGuide: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette

    var body: some View {
        Button(action: onOpenGuide) {
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
                        .foregroundStyle(.primary)
                    Text(L10n.pairingShortcutsGuideCardSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Text(L10n.pairingShortcutsGuideCardButton)
                    .font(.caption2.weight(.semibold))
                    .glassAccentForeground()
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct PairingShortcutsAutomationGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellPalette) private var shellPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable private var settings = AppSettings.shared

    @State private var stepIndex = 0
    @State private var completedStepIDs: Set<String> = []
    @State private var stepCompletePulse = false
    @State private var heroBeat: CGFloat = 0

    private var brandAccent: Color { shellPalette.tintColor(for: colorScheme) }
    private var steps: [GuideWizardStep] { Self.makeSteps() }
    private var currentStep: GuideWizardStep { steps[min(stepIndex, steps.count - 1)] }
    private var isLastStep: Bool { stepIndex >= steps.count - 1 }
    private var isFirstStep: Bool { stepIndex <= 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphericBackground().ignoresSafeArea()

                VStack(spacing: 0) {
                    progressRail
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    heroChrome
                        .padding(.bottom, 8)

                    ScrollViewReader { proxy in
                        ScrollView {
                            Group {
                                if showsStackedAutomationSteps {
                                    stackedAutomationSteps
                                } else {
                                    stepContent(for: currentStep)
                                        .id(currentStep.id)
                                        .transition(reduceMotion ? .opacity : TrailhoundMotion.softRiseTransition)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .onChange(of: stepIndex) { _, newIndex in
                            guard showsStackedAutomationSteps else { return }
                            withAnimation(reduceMotion ? nil : TrailhoundMotion.snappy) {
                                proxy.scrollTo(steps[newIndex].id, anchor: .top)
                            }
                        }
                    }

                    bottomChrome
                }
            }
            .navigationTitle(L10n.pairingShortcutsGuideTitle)
            .navigationBarTitleDisplayMode(.inline)
            .glassNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.pairingShortcutsGuideDone) {
                        dismiss()
                    }
                }
            }
            .animation(reduceMotion ? nil : TrailhoundMotion.snappy, value: stepIndex)
        }
    }

    /// Connect + disconnect steps accumulate on screen (newest on top).
    private var showsStackedAutomationSteps: Bool {
        switch currentStep.kind {
        case .connectStep, .disconnectStep:
            return true
        default:
            return false
        }
    }

    private var firstAutomationStepIndex: Int {
        steps.firstIndex { step in
            switch step.kind {
            case .connectStep, .disconnectStep: true
            default: false
            }
        } ?? 2
    }

    private var stackedAutomationSteps: some View {
        let revealed = Array(steps[firstAutomationStepIndex...stepIndex].reversed())
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(revealed.enumerated()), id: \.element.id) { _, step in
                let isCurrent = step.id == currentStep.id
                stackedAutomationCard(for: step, isCurrent: isCurrent)
                    .id(step.id)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity.combined(with: .scale(scale: 0.98))
                            )
                    )
            }
        }
    }

    private var progressRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.pairingShortcutsGuideStepProgress(current: stepIndex + 1, total: steps.count))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

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

    @ViewBuilder
    private var heroChrome: some View {
        switch currentStep.kind {
        case .prereq, .handoff:
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
        case .triggers, .connectStep, .disconnectStep:
            EmptyView()
        }
    }

    @ViewBuilder
    private func stepContent(for step: GuideWizardStep) -> some View {
        switch step.kind {
        case .prereq:
            prerequisiteSection
        case .triggers:
            triggerOptionsSection
        case .connectStep, .disconnectStep:
            // Rendered via `stackedAutomationSteps` while in this range.
            EmptyView()
        case .handoff:
            handoffSection
        }
    }

    @ViewBuilder
    private func stackedAutomationCard(for step: GuideWizardStep, isCurrent: Bool) -> some View {
        switch step.kind {
        case .connectStep(let index):
            automationStepCard(
                sectionTitle: L10n.pairingShortcutsGuideConnectTitle,
                sectionSymbol: "play.circle.fill",
                number: index + 1,
                text: connectSteps[index],
                icon: connectIcons[index],
                showsTriggerChips: index == 2,
                showsActionChip: index == 3,
                actionChipTitle: L10n.shortcutStartTitle,
                isCurrent: isCurrent,
                isComplete: !isCurrent || completedStepIDs.contains(step.id)
            )
        case .disconnectStep(let index):
            automationStepCard(
                sectionTitle: L10n.pairingShortcutsGuideDisconnectTitle,
                sectionSymbol: "stop.circle.fill",
                number: index + 1,
                text: disconnectSteps[index],
                icon: disconnectIcons[index],
                showsTriggerChips: index == 1,
                showsActionChip: index == 2,
                actionChipTitle: L10n.shortcutStopTitle,
                isCurrent: isCurrent,
                isComplete: !isCurrent || completedStepIDs.contains(step.id)
            )
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var prerequisiteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            guideSectionHeader(title: L10n.pairingShortcutsGuidePrerequisiteTitle, symbol: "checkmark.shield")

            Text(L10n.pairingShortcutsGuidePrerequisiteBody)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(L10n.pairingShortcutsGuideSilentStart, isOn: $settings.confirmExternalRecordingStart.inverted)
                .glassToggleStyle()
                .font(.subheadline)
                .tint(brandAccent)
        }
        .padding(14)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .glassChrome(cornerRadius: 12)
    }

    private var triggerOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            guideSectionHeader(title: L10n.pairingShortcutsGuideTriggersTitle, symbol: "list.bullet.rectangle")

            Text(L10n.pairingShortcutsGuideTriggersIntro)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                triggerOptionRow(
                    symbol: "bluetooth",
                    title: L10n.pairingShortcutsGuideTriggersBluetoothTitle,
                    body: L10n.pairingShortcutsGuideTriggersBluetoothBody
                )
                Divider().padding(.leading, 52)
                triggerOptionRow(
                    symbol: "carplay",
                    title: L10n.pairingShortcutsGuideTriggersCarPlayTitle,
                    body: L10n.pairingShortcutsGuideTriggersCarPlayBody
                )
                Divider().padding(.leading, 52)
                triggerOptionRow(
                    symbol: "wifi",
                    title: L10n.pairingShortcutsGuideTriggersWiFiTitle,
                    body: L10n.pairingShortcutsGuideTriggersWiFiBody
                )
            }
            .glassChrome(cornerRadius: 10)
        }
        .padding(14)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .glassChrome(cornerRadius: 12)
    }

    private var handoffSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            guideSectionHeader(title: L10n.pairingShortcutsGuideHandoffTitle, symbol: "arrow.up.forward.app")

            Text(L10n.pairingShortcutsGuideHandoffBody)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(L10n.pairingShortcutsGuideNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
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
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .glassChrome(cornerRadius: 12)
    }

    private func automationStepCard(
        sectionTitle: String,
        sectionSymbol: String,
        number: Int,
        text: String,
        icon: String,
        showsTriggerChips: Bool,
        showsActionChip: Bool,
        actionChipTitle: String,
        isCurrent: Bool,
        isComplete: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: sectionSymbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isCurrent ? brandAccent : brandAccent.opacity(0.55))
                Text(sectionTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCurrent ? .primary : .secondary)
                Spacer(minLength: 0)
                if isComplete && !isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(isComplete && !isCurrent ? Color.green : brandAccent)
                        .frame(width: 32, height: 32)
                    if isComplete && !isCurrent {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    } else {
                        Text("\(number)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .scaleEffect(isCurrent ? 1.06 : 1)
                .animation(reduceMotion ? nil : TrailhoundMotion.pinPop, value: isCurrent)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: icon)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isCurrent ? brandAccent : .secondary)
                            .padding(.top, 2)
                        Text(text)
                            .font(isCurrent ? .subheadline.weight(.medium) : .subheadline)
                            .foregroundStyle(isCurrent ? .primary : .secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if isCurrent, showsTriggerChips {
                        triggerChipsRow
                    }
                    if isCurrent, showsActionChip {
                        actionChip(title: actionChipTitle)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassChrome(cornerRadius: 12)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    brandAccent.opacity(isCurrent ? 0.35 : 0.12),
                    lineWidth: isCurrent ? 1.5 : 1
                )
        }
        .opacity(isCurrent ? 1 : 0.78)
        .scaleEffect(isCurrent ? 1 : 0.985, anchor: .top)
    }

    private func triggerOptionRow(
        symbol: String,
        title: String,
        body: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(brandAccent)
                    .frame(width: 36, height: 36)
                Image(systemName: resolvedTriggerSymbol(symbol))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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

    private func resolvedTriggerSymbol(_ symbol: String) -> String {
        switch symbol {
        case "bluetooth":
            return UIImage(systemName: "bluetooth") != nil
                ? "bluetooth"
                : "antenna.radiowaves.left.and.right"
        case "carplay":
            return UIImage(systemName: "carplay") != nil
                ? "carplay"
                : "play.circle.fill"
        default:
            return symbol
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

    private var triggerChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                triggerChip(symbol: "bluetooth", label: L10n.pairingShortcutsGuideTriggersBluetoothTitle)
                triggerChip(symbol: "carplay", label: L10n.pairingShortcutsGuideTriggersCarPlayTitle)
                triggerChip(symbol: "wifi", label: L10n.pairingShortcutsGuideTriggersWiFiTitle)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private func triggerChip(symbol: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: resolvedTriggerSymbol(symbol))
                .font(.system(size: 9, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(brandAccent)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(brandAccent.opacity(0.12))
        .clipShape(Capsule())
    }

    private func actionChip(title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "app.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(brandAccent)
            Text("Trailhound")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(brandAccent)
            Image(systemName: "chevron.right")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(brandAccent)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .glassChrome(cornerRadius: 12)
        .overlay {
            Capsule()
                .strokeBorder(brandAccent.opacity(0.25), lineWidth: 1)
        }
    }

    private func advance() {
        markCurrentStepComplete()
        if isLastStep {
            dismiss()
            return
        }

        // Stacking range keeps prior cards visible — short beat, then push the next on top.
        let delayMs: UInt64 = reduceMotion ? 0 : (showsStackedAutomationSteps ? 140 : 220)
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
        var result: [GuideWizardStep] = [
            GuideWizardStep(id: "prereq", kind: .prereq),
            GuideWizardStep(id: "triggers", kind: .triggers)
        ]
        for index in 0..<5 {
            result.append(GuideWizardStep(id: "connect-\(index)", kind: .connectStep(index)))
        }
        for index in 0..<4 {
            result.append(GuideWizardStep(id: "disconnect-\(index)", kind: .disconnectStep(index)))
        }
        result.append(GuideWizardStep(id: "handoff", kind: .handoff))
        return result
    }
}

private struct GuideWizardStep: Identifiable, Equatable {
    enum Kind: Equatable {
        case prereq
        case triggers
        case connectStep(Int)
        case disconnectStep(Int)
        case handoff
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

#Preview("Card") {
    List {
        PairingShortcutsAutomationCard(onOpenGuide: {})
            .glassListRow()
    }
    .glassListChrome()
}

#Preview("Guide") {
    PairingShortcutsAutomationGuideView()
}
