import SwiftUI

private enum OnboardingStep: Int, CaseIterable {
    case welcome
    case location
    case vehicleCare
    case shortcuts

    static var count: Int { allCases.count }
}

struct OnboardingView: View {
    @Environment(LocationService.self) private var locationService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Bindable private var settings = AppSettings.shared

    @State private var page = OnboardingStep.welcome.rawValue
    @State private var showShortcutsAutomationGuide = false

    @State private var brandReveal: CGFloat = 0
    @State private var heroReveal: CGFloat = 0
    @State private var driveInProgress: CGFloat = 0
    @State private var beatProgress: CGFloat = 0
    @State private var detailsReveal: CGFloat = 0
    @State private var entranceToken = 0

    private var pageCount: Int { OnboardingStep.count }
    private var currentStep: OnboardingStep {
        OnboardingStep(rawValue: page) ?? .welcome
    }

    private var sceneIsLive: Bool {
        scenePhase == .active && heroReveal > 0.02
    }

    var body: some View {
        ZStack {
            AtmosphericBackground(style: .canvas)

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcomePage
                        .tag(OnboardingStep.welcome.rawValue)
                    locationPage
                        .tag(OnboardingStep.location.rawValue)
                    vehicleCarePage
                        .tag(OnboardingStep.vehicleCare.rawValue)
                    shortcutsPage
                        .tag(OnboardingStep.shortcuts.rawValue)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(TrailhoundMotion.gentle, value: page)

                pageIndicator
                    .padding(.top, 8)

                bottomBar
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                    .opacity(detailsReveal)
                    .offset(y: (1 - detailsReveal) * 12)
            }
        }
        .sheet(isPresented: $showShortcutsAutomationGuide) {
            PairingShortcutsAutomationGuideView()
        }
        .task(id: entranceToken) {
            await runEntrance(for: currentStep)
        }
        .onChange(of: page) { _, _ in
            prepareEntrance()
            entranceToken &+= 1
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        onboardingHeroPage(
            kind: .welcomeDrive,
            title: L10n.string("onboarding.welcome.title"),
            message: L10n.string("onboarding.welcome.message"),
            showsBrandColdOpen: true
        ) {
            VStack(alignment: .leading, spacing: 14) {
                onboardingFeatureRow(
                    icon: "point.topleft.down.curvedto.point.bottomright.up",
                    text: L10n.string("onboarding.features.routes")
                )
                onboardingFeatureRow(
                    icon: "chart.bar.fill",
                    text: L10n.string("onboarding.features.insights")
                )
                onboardingFeatureRow(
                    icon: "record.circle",
                    text: L10n.string("onboarding.features.recording")
                )
                onboardingFeatureRow(
                    icon: "bolt.horizontal.circle.fill",
                    text: L10n.string("onboarding.features.auto")
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    private var locationPage: some View {
        onboardingHeroPage(
            kind: .locationPin,
            title: L10n.string("onboarding.location.title"),
            message: L10n.string("onboarding.location.message")
        ) {
            VStack(spacing: 12) {
                LocationPermissionBadge(state: locationService.authorizationState)

                locationPermissionActions
            }
        }
    }

    private var vehicleCarePage: some View {
        onboardingHeroPage(
            kind: .vehicleCare,
            title: L10n.string("onboarding.vehicle_care.title"),
            message: L10n.string("onboarding.vehicle_care.message")
        ) {
            VStack(alignment: .leading, spacing: 14) {
                onboardingFeatureRow(
                    icon: "calendar.badge.clock",
                    text: L10n.string("onboarding.vehicle_care.reminders")
                )
                onboardingFeatureRow(
                    icon: "creditcard.circle.fill",
                    text: L10n.string("onboarding.vehicle_care.expenses")
                )
                onboardingFeatureRow(
                    icon: "chart.pie.fill",
                    text: L10n.string("onboarding.vehicle_care.charts")
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
        }
    }

    private var shortcutsPage: some View {
        onboardingHeroPage(
            kind: .shortcutsLink,
            title: L10n.string("onboarding.shortcuts.title"),
            message: L10n.string("onboarding.shortcuts.message")
        ) {
            Button {
                showShortcutsAutomationGuide = true
                TrailhoundHaptics.selection()
            } label: {
                HStack(spacing: 6) {
                    Text(L10n.string("onboarding.shortcuts.link"))
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                }
                .font(.body.weight(.semibold))
            }
            .foregroundStyle(TrailhoundBrandColors.brandBottom)
            .padding(.top, 4)
        }
    }

    // MARK: - Building blocks

    private func onboardingHeroPage<Extra: View>(
        kind: OnboardingHeroKind,
        title: String,
        message: String? = nil,
        showsBrandColdOpen: Bool = false,
        @ViewBuilder extra: () -> Extra = { EmptyView() }
    ) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 12)

            ZStack {
                if showsBrandColdOpen {
                    TrailhoundBrandMark(showsWordmark: true, symbolSize: 96)
                        .opacity(Double(brandReveal) * Double(1 - heroReveal))
                        .scaleEffect(0.92 + 0.08 * brandReveal)
                        .allowsHitTesting(false)
                }

                OnboardingHeroScene(
                    kind: kind,
                    driveInProgress: driveInProgress,
                    beatProgress: beatProgress,
                    isAnimating: sceneIsLive && page == stepRawValue(for: kind)
                )
                .opacity(heroReveal)
                .offset(y: (1 - heroReveal) * 18)
                .scaleEffect(0.96 + 0.04 * heroReveal, anchor: .center)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: TrailhoundRoadSceneMetrics.hero.sceneHeight)

            VStack(spacing: 12) {
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                if let message {
                    Text(message)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 8)
            .opacity(detailsReveal)
            .offset(y: (1 - detailsReveal) * 10)

            extra()
                .opacity(detailsReveal)
                .offset(y: (1 - detailsReveal) * 8)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private func stepRawValue(for kind: OnboardingHeroKind) -> Int {
        switch kind {
        case .welcomeDrive: return OnboardingStep.welcome.rawValue
        case .locationPin: return OnboardingStep.location.rawValue
        case .vehicleCare: return OnboardingStep.vehicleCare.rawValue
        case .shortcutsLink: return OnboardingStep.shortcuts.rawValue
        }
    }

    private func onboardingFeatureRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(TrailhoundBrandColors.brandBottom)
                .frame(width: 28, alignment: .center)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var locationPermissionActions: some View {
        switch locationService.authorizationState {
        case .authorizedAlways:
            Text(L10n.string("onboarding.permission.granted"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        case .denied, .restricted:
            Button(L10n.locationBannerSettings) {
                openAppSettings()
            }
            .buttonStyle(.borderedProminent)
            .tint(TrailhoundBrandColors.brandBottom)
        case .notDetermined, .authorizedWhenInUse:
            Button(L10n.string("onboarding.location.enable_always")) {
                locationService.requestPermission()
                TrailhoundHaptics.selection()
            }
            .buttonStyle(.borderedProminent)
            .tint(TrailhoundBrandColors.brandBottom)
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { index in
                Capsule()
                    .fill(index == page ? Color.primary : Color.secondary.opacity(0.25))
                    .frame(width: index == page ? 18 : 8, height: 8)
                    .animation(TrailhoundMotion.gentle, value: page)
            }
        }
        .opacity(detailsReveal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(format: L10n.string("onboarding.step_a11y"), page + 1, pageCount))
    }

    private var bottomBar: some View {
        HStack {
            if page > 0 {
                Button(L10n.string("onboarding.back")) {
                    withAnimation(TrailhoundMotion.gentle) {
                        page -= 1
                    }
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            if page < pageCount - 1 {
                Button(L10n.string("onboarding.next")) {
                    withAnimation(TrailhoundMotion.gentle) {
                        page += 1
                    }
                    TrailhoundHaptics.selection()
                }
                .buttonStyle(.borderedProminent)
                .tint(TrailhoundBrandColors.brandBottom)
            } else {
                Button(L10n.string("onboarding.finish")) {
                    finishOnboarding()
                }
                .buttonStyle(.borderedProminent)
                .tint(TrailhoundBrandColors.brandBottom)
            }
        }
    }

    // MARK: - Entrance

    @MainActor
    private func prepareEntrance() {
        if reduceMotion {
            settleEntrance()
            return
        }
        brandReveal = 0
        heroReveal = 0
        driveInProgress = 0
        beatProgress = 0
        detailsReveal = 0
    }

    @MainActor
    private func settleEntrance() {
        brandReveal = 0
        heroReveal = 1
        driveInProgress = 1
        beatProgress = 1
        detailsReveal = 1
    }

    @MainActor
    private func runEntrance(for step: OnboardingStep) async {
        if reduceMotion {
            settleEntrance()
            return
        }

        brandReveal = 0
        heroReveal = 0
        driveInProgress = step == .welcome ? 0 : 1
        beatProgress = 0
        detailsReveal = 0

        if step == .welcome {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                brandReveal = 1
            }
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else {
                settleEntrance()
                return
            }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                heroReveal = 1
                brandReveal = 0
            }
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else {
                settleEntrance()
                return
            }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                driveInProgress = 1
            }
            beatProgress = 1
        } else {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                heroReveal = 1
            }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else {
                settleEntrance()
                return
            }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.84)) {
                beatProgress = 1
            }
        }

        try? await Task.sleep(for: .milliseconds(90))
        guard !Task.isCancelled else {
            settleEntrance()
            return
        }
        withAnimation(.easeOut(duration: 0.18)) {
            detailsReveal = 1
        }
    }

    // MARK: - Actions

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    private func finishOnboarding() {
        settings.completeOnboarding()
        settings.skipCarSetup()
        TrailhoundHaptics.pairingSucceeded()
    }
}

#Preview {
    OnboardingView()
        .environment(LocationService())
}
