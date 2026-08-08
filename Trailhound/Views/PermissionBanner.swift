import SwiftUI

struct LocationPermissionBadge: View {
  let state: LocationService.AuthorizationState

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: icon)
        .font(.caption2)
      Text(label)
        .font(.caption2.weight(.semibold))
    }
    .foregroundStyle(color)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(color.opacity(0.15))
    .clipShape(Capsule())
    .accessibilityLabel(label)
  }

  private var icon: String {
    switch state {
    case .authorizedAlways: "location.fill"
    case .authorizedWhenInUse: "location.circle"
    case .denied, .restricted: "location.slash.fill"
    case .notDetermined: "location"
    }
  }

  private var label: String {
    switch state {
    case .authorizedAlways: L10n.locationBadgeAlways
    case .authorizedWhenInUse: L10n.locationBadgeWhenInUse
    case .denied, .restricted, .notDetermined: L10n.locationBadgeDenied
    }
  }

  private var color: Color {
    switch state {
    case .authorizedAlways: .green
    case .authorizedWhenInUse: .orange
    case .denied, .restricted, .notDetermined: .red
    }
  }
}

extension ToolbarContent {
  @ToolbarContentBuilder
  func hideSharedToolbarBackgroundIfAvailable() -> some ToolbarContent {
    if #available(iOS 26.0, *) {
      sharedBackgroundVisibility(.hidden)
    } else {
      self
    }
  }
}

struct LocationAlwaysRequiredBanner: View {
  @Environment(LocationService.self) private var locationService

  var body: some View {
    if locationService.authorizationState == .authorizedAlways {
      EmptyView()
    } else {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 6) {
          Text(L10n.pairingLocationWarning)
            .font(.caption)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
          locationAction
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.orange.opacity(0.12))
      .glassCard(cornerRadius: 12, contentInset: 0)
    }
  }

  @ViewBuilder
  private var locationAction: some View {
    switch locationService.authorizationState {
    case .notDetermined, .authorizedWhenInUse:
      Button(L10n.locationBannerGrant) {
        locationService.requestPermission()
      }
      .font(.caption.bold())
    case .denied, .restricted:
      Button(L10n.locationBannerSettings) {
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
      }
      .font(.caption.bold())
    case .authorizedAlways:
      EmptyView()
    }
  }
}

struct LocationPermissionBanner: View {
  @Environment(LocationService.self) private var locationService

  var body: some View {
    switch locationService.authorizationState {
    case .authorizedAlways:
      EmptyView()
    case .authorizedWhenInUse:
      banner(
        message: L10n.string("location.banner.when_in_use"),
        systemImage: "location.circle",
        openSettings: true
      )
    case .denied, .restricted:
      banner(
        message: L10n.string("location.banner.denied"),
        systemImage: "location.slash.fill",
        openSettings: true
      )
    case .notDetermined:
      banner(
        message: L10n.string("location.banner.not_determined"),
        systemImage: "location.fill",
        openSettings: false,
        actionTitle: L10n.string("location.banner.grant"),
        action: { locationService.requestPermission() }
      )
    }
  }

  @ViewBuilder
  private func banner(
    message: String,
    systemImage: String,
    openSettings: Bool,
    actionTitle: String? = nil,
    action: (() -> Void)? = nil
  ) -> some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: systemImage)
        .foregroundStyle(.orange)
      Text(message)
        .font(.caption)
        .foregroundStyle(.primary)
      Spacer(minLength: 0)
      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .font(.caption.bold())
      } else if openSettings {
        Button(L10n.string("location.banner.settings")) {
          if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
          }
        }
        .font(.caption.bold())
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(Color.orange.opacity(0.12))
    .glassCard(cornerRadius: 12, contentInset: 0)
    .padding(.horizontal)
  }
}

struct GPSQualityBadge: View {
  let quality: LocationService.GPSQuality
  var compact: Bool = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    HStack(spacing: compact ? 3 : 4) {
      Image(systemName: icon)
        .font(compact ? .system(size: 9, weight: .semibold) : .caption2)
        .symbolEffect(.bounce, value: quality)
      Text(label)
        .font(compact ? .system(size: 10, weight: .medium) : .caption2.weight(.medium))
        .lineLimit(1)
        .minimumScaleFactor(compact ? 0.75 : 1)
    }
    .foregroundStyle(color)
    .padding(.horizontal, compact ? 6 : 8)
    .padding(.vertical, compact ? 3 : 4)
    .background(color.opacity(0.15))
    .clipShape(Capsule())
    .animation(reduceMotion ? nil : TrailhoundMotion.gentle, value: quality)
    .accessibilityLabel(label)
  }

  private var icon: String {
    switch quality {
    case .good: "location.fill"
    case .weak: "location.circle"
    case .lost: "location.slash"
    }
  }

  private var label: String {
    switch quality {
    case .good: L10n.string("gps.quality.good")
    case .weak: L10n.string("gps.quality.weak")
    case .lost: L10n.string("gps.quality.lost")
    }
  }

  private var color: Color {
    switch quality {
    case .good: .green
    case .weak: .orange
    case .lost: .red
    }
  }
}
