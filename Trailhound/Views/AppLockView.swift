import SwiftUI

struct AppLockView: View {
    @Environment(AppLockService.self) private var appLockService
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        ZStack {
            AtmosphericBackground()

            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 48))
                    .glassAccentForeground()
                Text(L10n.appLockTitle)
                    .font(.title2)
                if !appLockService.canUseDeviceAuthentication {
                    Text(L10n.appLockUnavailable)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                Button(L10n.appLockUnlock) {
                    Task { @MainActor in
                        _ = await appLockService.authenticateIfNeeded(enabled: settings.appLockEnabled)
                    }
                }
                .trailhoundProminentButton()
            }
            .padding(28)
            .glassCard(contentInset: 0)
            .padding(.horizontal, 32)
        }
    }
}
