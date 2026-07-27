import SwiftUI

struct TripRowView: View {
    let trip: Trip
    var places: [SavedPlace] = []
    var privacyRadius: Double = 500
    var morphNamespace: Namespace.ID?
    var morphID: UUID?
    /// Soft-lands the map thumbnail after stop→row morph.
    var emphasizeLanding: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var thumbnail: UIImage?
    @State private var thumbnailLoaded = false

    private var routeSummary: String {
        TripListViewModel.routeSummary(for: trip, places: places, privacyRadius: privacyRadius)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            thumbnailView

            VStack(alignment: .leading, spacing: 6) {
                Text(routeSummary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    HStack(spacing: 3) {
                        Image(systemName: "stopwatch")
                            .font(.system(size: 9, weight: .semibold))
                        Text(TripListViewModel.durationText(for: trip))
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(TrailhoundBrandColors.brandBottom)

                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    HStack(spacing: 3) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9, weight: .semibold))
                        Text(TripListViewModel.dateText(for: trip))
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)

                    if trip.categoryID == BuiltInCategory.businessID.uuidString {
                        Image(systemName: "briefcase.fill")
                            .font(.caption2)
                            .foregroundStyle(TrailhoundBrandColors.brandBottom)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 6) {
                    metricChip(icon: "road.lanes", text: TripListViewModel.distanceText(for: trip))

                    if let fuel = TripListViewModel.fuelText(for: trip) {
                        metricChip(icon: "fuelpump", text: fuel)
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
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
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
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }

    private func metricChip(icon: String, text: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.caption2.weight(.medium))
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
