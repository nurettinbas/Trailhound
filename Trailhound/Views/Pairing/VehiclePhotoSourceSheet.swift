import SwiftUI

/// Premium photo source picker (library / camera) — same blue atmosphere as the rest of Trailhound.
struct VehiclePhotoSourceSheet: View {
    let canUseCamera: Bool
    let onLibrary: () -> Void
    let onCamera: () -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var appeared = false

    var body: some View {
        // Background is owned by `VehiclePhotoFlowSheet` so expand is one surface.
        VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.28 : 0.45))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)
                    .padding(.bottom, 16)

                Text(L10n.pairingTabVehiclePhoto)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)

                Text(L10n.pairingTabVehiclePhotoSourceSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.top, 4)
                    .padding(.bottom, 18)

                VStack(spacing: 10) {
                    sourceRow(
                        index: 0,
                        icon: "photo.on.rectangle.angled",
                        title: L10n.pairingTabVehiclePhotoChoose,
                        subtitle: L10n.pairingTabVehiclePhotoChooseSubtitle,
                        action: onLibrary
                    )

                    if canUseCamera {
                        sourceRow(
                            index: 1,
                            icon: "camera.fill",
                            title: L10n.pairingTabVehiclePhotoCamera,
                            subtitle: L10n.pairingTabVehiclePhotoCameraSubtitle,
                            action: onCamera
                        )
                    }
                }
                .padding(.horizontal, 16)

                Button(L10n.cancel, action: onCancel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .glassChrome(cornerRadius: GlassTokens.chipRadius)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 16)
                    .buttonStyle(VehiclePhotoPressStyle())
        }
        .onAppear {
            guard !reduceMotion else {
                appeared = true
                return
            }
            withAnimation(TrailhoundMotion.photoSettle) {
                appeared = true
            }
        }
    }

    private func sourceRow(
        index: Int,
        icon: String,
        title: String,
        subtitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            TrailhoundHaptics.selection()
            action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(TrailhoundBrandColors.brandBottom)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(TrailhoundBrandColors.brandBottom.opacity(0.18))
                    )
                    .symbolEffect(.bounce, value: appeared)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .glassChrome(cornerRadius: 16)
        }
        .buttonStyle(VehiclePhotoPressStyle())
        .opacity(appeared || reduceMotion ? 1 : 0)
        .offset(y: appeared || reduceMotion ? 0 : 10)
        .animation(
            reduceMotion ? nil : TrailhoundMotion.photoSettle.delay(Double(index) * 0.04),
            value: appeared
        )
    }
}
