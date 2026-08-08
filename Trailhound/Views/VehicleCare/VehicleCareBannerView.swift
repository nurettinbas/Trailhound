import SwiftUI

struct VehicleCareBannerView: View {
    let item: VehicleDueItem
    var onTap: () -> Void
    var onDismiss: () -> Void

    private var isOverdue: Bool { item.state.isOverdue }

    private var accent: Color {
        isOverdue ? .red : .orange
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isOverdue ? "exclamationmark.triangle.fill" : "calendar.badge.clock")
                .font(.callout.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 20)

            Text(item.vehicleName)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(
                VehicleCareDueCalculator.subtitle(for: item.state, title: item.title)
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .multilineTextAlignment(.trailing)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct VehicleCareBannerRowBackground: View {
    let state: VehicleCareDueState

    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        state.isOverdue ? .red : .orange
    }

    private var tintOpacity: Double {
        colorScheme == .dark ? 0.32 : 0.22
    }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: GlassTokens.cardRadius,
            bottomLeadingRadius: GlassTokens.cardRadius,
            bottomTrailingRadius: GlassTokens.cardRadius,
            topTrailingRadius: GlassTokens.cardRadius,
            style: .continuous
        )
    }

    var body: some View {
        ZStack {
            GlassSectionRowBackground(position: .only)
            shape
                .fill(tint.opacity(tintOpacity))
                .padding(.horizontal, GlassTokens.panelHorizontalInset)
        }
    }
}

extension View {
    func vehicleCareBannerRow(state: VehicleCareDueState) -> some View {
        listRowBackground(VehicleCareBannerRowBackground(state: state))
            .listRowInsets(
                EdgeInsets(
                    top: 8,
                    leading: GlassTokens.listContentHorizontalInset,
                    bottom: 8,
                    trailing: GlassTokens.listContentHorizontalInset
                )
            )
            .listRowSeparator(.hidden)
    }
}
