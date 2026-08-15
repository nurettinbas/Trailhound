import SwiftUI

struct TripRowView: View {
    let trip: Trip
    var places: [SavedPlace] = []
    var privacyRadius: Double = 500
    /// Resolved from `trip.vehicleID` upstream — relationship is not populated on list rows.
    var vehicle: VehicleProfile? = nil
    var morphNamespace: Namespace.ID?
    var morphID: UUID?
    /// Soft-lands the map thumbnail after stop→row morph.
    var emphasizeLanding: Bool = false

    @Bindable private var settings = AppSettings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thumbnail: UIImage?
    @State private var thumbnailLoaded = false

    private static let thumbnailSize: CGFloat = 45
    private static let vehicleBadgeSize: CGFloat = 16

    private var routeSummary: String {
        TripListViewModel.routeSummary(for: trip, places: places, privacyRadius: privacyRadius)
    }

    var body: some View {
        let fuelCurrencyCode = settings.fuelCurrency.rawValue
        HStack(alignment: .center, spacing: 12) {
            thumbnailView

            VStack(alignment: .leading, spacing: 5) {
                Text(routeSummary)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 5) {
                    HStack(spacing: 3) {
                        Image(systemName: "stopwatch")
                            .font(.system(size: 7, weight: .semibold))
                        Text(TripListViewModel.durationText(for: trip))
                            .font(.system(size: 9))
                            .lineLimit(1)
                    }
                    .foregroundStyle(TrailhoundBrandColors.brandBottom)

                    Text("·")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(.system(size: 7, weight: .semibold))
                        Text(TripListViewModel.dateText(for: trip))
                            .font(.system(size: 9))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)

                    if trip.categoryID == BuiltInCategory.businessID.uuidString {
                        Image(systemName: "briefcase.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(TrailhoundBrandColors.brandBottom)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 5) {
                    metricChip(icon: "road.lanes", text: TripListViewModel.distanceText(for: trip))

                    if let fuel = TripListViewModel.fuelText(for: trip) {
                        metricChip(icon: "fuelpump", text: fuel)
                            .id(fuelCurrencyCode)
                    }

                    if let maxLabel = TripListViewModel.maxSpeedLabel(for: trip) {
                        metricChip(icon: "speedometer", text: maxLabel)
                    }

                    if let avgLabel = TripListViewModel.averageSpeedLabel(for: trip) {
                        metricChip(icon: "gauge.with.dots.needle.33percent", text: avgLabel)
                    }
                }

                if let label = trip.label, !label.isEmpty {
                    Text(label)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background {
            if emphasizeLanding, !reduceMotion {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(TrailhoundBrandColors.brandBottom.opacity(0.14))
                    .padding(.horizontal, -4)
                    .padding(.vertical, -4)
            }
        }
        .overlay {
            if emphasizeLanding, !reduceMotion {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(TrailhoundBrandColors.brandBottom.opacity(0.35), lineWidth: 1)
                    .padding(.horizontal, -4)
                    .padding(.vertical, -4)
            }
        }
        .scaleEffect(emphasizeLanding && !reduceMotion ? 1.02 : 1)
        .animation(TrailhoundMotion.recordingMorph, value: emphasizeLanding)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
        .task(id: trip.id) {
            thumbnailLoaded = false
            thumbnail = nil

            if emphasizeLanding, !reduceMotion {
                // Brief hold so morph settles before snapshot lands.
                try? await Task.sleep(for: .milliseconds(140))
            }

            let image = await TripMapSnapshotCache.shared.snapshot(for: trip)
            if !reduceMotion {
                withAnimation(emphasizeLanding ? TrailhoundMotion.recordingMorph : TrailhoundMotion.gentle) {
                    thumbnail = image
                    thumbnailLoaded = true
                }
            } else {
                thumbnail = image
                thumbnailLoaded = true
            }
        }
    }

    private var accessibilitySummary: String {
        var parts = [routeSummary, TripListViewModel.durationText(for: trip)]
        parts.append(TripListViewModel.dateText(for: trip))
        parts.append(TripListViewModel.distanceText(for: trip))
        if let vehicle {
            parts.append(vehicle.name)
        }
        if let label = trip.label, !label.isEmpty {
            parts.append(label)
        }
        return parts.joined(separator: ", ")
    }

    @ViewBuilder
    private var thumbnailView: some View {
        Group {
            if let thumbnail, thumbnailLoaded {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity.combined(with: .scale(scale: emphasizeLanding ? 0.92 : 1)))
            } else {
                ZStack {
                    Color(.tertiarySystemFill)
                        .shimmer()
                    Image(systemName: "map")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
        .overlay(alignment: .topTrailing) {
            if let vehicle {
                vehicleBadge(for: vehicle)
                    .padding(2)
            }
        }
        .accessibilityHidden(true)
    }

    private func vehicleBadge(for vehicle: VehicleProfile) -> some View {
        let size = Self.vehicleBadgeSize
        return VehicleAvatarView(
            systemImage: VehicleIconOption.default.rawValue,
            photoFileName: vehicle.photoFileName,
            size: size,
            cornerRadius: size * 0.28,
            isElectricAccent: vehicle.fuelType == .electric,
            showsSymbolPlate: true,
            symbolFitsFrame: true
        )
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.28), radius: 1.5, y: 0.5)
    }

    private func metricChip(icon: String, text: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 7, weight: .semibold))
            Text(text)
                .font(.system(size: 8, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
    }
}

#Preview {
    List {
        TripRowView(trip: PreviewData.sampleTrip)
    }
}
