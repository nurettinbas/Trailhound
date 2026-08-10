import SwiftData
import SwiftUI

/// Week summary + search + date/category/vehicle/place filters pinned above the trip rows.
struct TripListFiltersBar: View {
    @Binding var searchText: String
    @Binding var selectedDateSection: TripDateSection?
    @Binding var selectedCategoryID: String?
    @Binding var selectedVehicleFilter: TripListPage.VehicleFilter?
    @Binding var selectedPlaceID: UUID?
    var vehicles: [VehicleProfile] = []
    var places: [SavedPlace] = []
    /// Compact “This week” strip shown above search when non-empty.
    var weekSummaryText: String = ""

    @Namespace private var dateChipNamespace
    @Namespace private var vehicleChipNamespace
    @Namespace private var placeChipNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFiltersExpanded = false

    private var dateSelectionKey: String {
        if let selectedDateSection { return "date:\(selectedDateSection.rawValue)" }
        return "date:all"
    }

    private var activeChipFilterCount: Int {
        var count = 0
        if selectedDateSection != nil { count += 1 }
        if selectedCategoryID != nil { count += 1 }
        if selectedVehicleFilter != nil { count += 1 }
        if selectedPlaceID != nil { count += 1 }
        return count
    }

    private var hasChipFiltersActive: Bool {
        activeChipFilterCount > 0
    }

    private var showsWeekSummary: Bool {
        !weekSummaryText.isEmpty
    }

    private var sortedVehicles: [VehicleProfile] {
        vehicles.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var vehiclePhotoPrefetchID: String {
        VehiclePhotoStore.prefetchTaskID(for: vehicles)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsWeekSummary {
                weekSummaryRow
            }

            HStack(alignment: .center, spacing: 8) {
                searchField
                filtersToggleButton
                if hasChipFiltersActive {
                    clearFiltersButton
                }
            }
            .animation(reduceMotion ? nil : TrailhoundMotion.cardSpring, value: hasChipFiltersActive)

            if isFiltersExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    dateFilterRow
                    TripFilterChips(selectedCategoryID: $selectedCategoryID, usesCardInsets: false)
                    vehicleFilterRow
                    if !sortedPlaces.isEmpty {
                        placeFilterRow
                    }
                }
                .transition(filtersRevealTransition)
            }
        }
        .animation(reduceMotion ? nil : TrailhoundMotion.cardSpring, value: isFiltersExpanded)
        .task(id: vehiclePhotoPrefetchID) {
            await VehiclePhotoStore.shared.prefetch(vehicles: vehicles)
        }
    }

    private var weekSummaryRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .frame(width: 16)

            Text(L10n.sectionThisWeek)
                .font(.caption.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 6)

            Text(weekSummaryText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
                .numericTextAnimation(value: weekSummaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L10n.sectionThisWeek). \(weekSummaryText)")
    }

    private var filtersRevealTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            TextField(L10n.searchTrips, text: $searchText)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.placePickerSearchClear)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(minHeight: 36)
        .glassField(cornerRadius: 10)
    }

    private var filtersToggleButton: some View {
        Button {
            TrailhoundHaptics.selection()
            if reduceMotion {
                isFiltersExpanded.toggle()
            } else {
                withAnimation(TrailhoundMotion.cardSpring) {
                    isFiltersExpanded.toggle()
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 18, weight: .semibold))
                .symbolVariant(isFiltersExpanded || hasChipFiltersActive ? .fill : .none)
                .foregroundStyle(
                    isFiltersExpanded || hasChipFiltersActive
                        ? TrailhoundBrandColors.brandBottom
                        : Color.secondary
                )
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                .glassField(cornerRadius: 10)
                .overlay(alignment: .topTrailing) {
                    if activeChipFilterCount > 0 {
                        Text("\(activeChipFilterCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 16, minHeight: 16)
                            .padding(.horizontal, 3)
                            .background(TrailhoundBrandColors.brandBottom, in: Capsule())
                            .offset(x: 4, y: -4)
                            .transition(reduceMotion ? .identity : .scale.combined(with: .opacity))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.tripsFilters)
        .accessibilityValue(
            activeChipFilterCount > 0
                ? "\(activeChipFilterCount)"
                : ""
        )
        .accessibilityAddTraits(isFiltersExpanded ? .isSelected : [])
    }

    private var clearFiltersButton: some View {
        Button {
            TrailhoundHaptics.selection()
            clearChipFilters()
        } label: {
            Image(systemName: "xmark.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(TrailhoundBrandColors.brandBottom)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                .glassField(cornerRadius: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.tripsFiltersClear)
        .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.85)))
    }

    private func clearChipFilters() {
        let clear = {
            selectedDateSection = nil
            selectedCategoryID = nil
            selectedVehicleFilter = nil
            selectedPlaceID = nil
        }
        if reduceMotion {
            clear()
        } else {
            withAnimation(TrailhoundMotion.cardSpring) {
                clear()
            }
        }
    }

    private var sortedPlaces: [SavedPlace] {
        places.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var placeSelectionKey: String {
        if let selectedPlaceID { return "place:\(selectedPlaceID.uuidString)" }
        return "place:all"
    }

    private var dateFilterRow: some View {
        filterChipRow(label: L10n.filterDate) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        dateChip(
                            title: L10n.all,
                            key: "date:all",
                            isSelected: selectedDateSection == nil
                        ) {
                            selectedDateSection = nil
                        }
                        ForEach(TripDateSection.allCases) { section in
                            dateChip(
                                title: section.title,
                                key: "date:\(section.rawValue)",
                                isSelected: selectedDateSection == section
                            ) {
                                selectedDateSection = selectedDateSection == section ? nil : section
                            }
                        }
                    }
                    .animation(reduceMotion ? nil : TrailhoundMotion.cardSpring, value: dateSelectionKey)
                }
                .onChange(of: dateSelectionKey) { _, newKey in
                    revealChip(withID: newKey, using: proxy)
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }

    private var vehicleSelectionKey: String {
        switch selectedVehicleFilter {
        case .unassigned: return "vehicle:unassigned"
        case .vehicle(let id): return "vehicle:\(id.uuidString)"
        case nil: return "vehicle:all"
        }
    }

    private var vehicleFilterRow: some View {
        filterChipRow(label: L10n.filterVehicle) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        vehicleChip(
                            title: L10n.all,
                            key: "vehicle:all",
                            isSelected: selectedVehicleFilter == nil
                        ) {
                            selectedVehicleFilter = nil
                        }
                        vehicleChip(
                            title: L10n.string("stats.vehicle.unassigned"),
                            key: "vehicle:unassigned",
                            isSelected: selectedVehicleFilter == .unassigned
                        ) {
                            selectedVehicleFilter = selectedVehicleFilter == .unassigned ? nil : .unassigned
                        }
                        ForEach(sortedVehicles) { vehicle in
                            let key = "vehicle:\(vehicle.id.uuidString)"
                            let filter = TripListPage.VehicleFilter.vehicle(vehicle.id)
                            vehicleChip(
                                title: vehicle.name,
                                key: key,
                                isSelected: selectedVehicleFilter == filter,
                                avatarSystemImage: vehicle.systemImage,
                                avatarPhotoFileName: vehicle.photoFileName,
                                avatarIsElectric: vehicle.fuelType == .electric
                            ) {
                                selectedVehicleFilter = selectedVehicleFilter == filter ? nil : filter
                            }
                        }
                    }
                    .animation(reduceMotion ? nil : TrailhoundMotion.cardSpring, value: vehicleSelectionKey)
                }
                .onChange(of: vehicleSelectionKey) { _, newKey in
                    revealChip(withID: newKey, using: proxy)
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }

    private var placeFilterRow: some View {
        filterChipRow(label: L10n.filterPlace) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        placeChip(
                            title: L10n.all,
                            key: "place:all",
                            isSelected: selectedPlaceID == nil
                        ) {
                            selectedPlaceID = nil
                        }
                        ForEach(sortedPlaces, id: \.id) { place in
                            let key = "place:\(place.id.uuidString)"
                            placeChip(
                                title: place.name,
                                key: key,
                                isSelected: selectedPlaceID == place.id
                            ) {
                                selectedPlaceID = selectedPlaceID == place.id ? nil : place.id
                            }
                        }
                    }
                    .animation(reduceMotion ? nil : TrailhoundMotion.cardSpring, value: placeSelectionKey)
                }
                .onChange(of: placeSelectionKey) { _, newKey in
                    revealChip(withID: newKey, using: proxy)
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
    }

    private func filterChipRow<Content: View>(
        label: String,
        @ViewBuilder chips: () -> Content
    ) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text("\(label):")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityHidden(true)

            chips()
        }
        .frame(height: 32)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func dateChip(
        title: String,
        key: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        GlassFilterChip(
            title: title,
            isSelected: isSelected,
            namespace: dateChipNamespace,
            highlightID: "tripDateFilterHighlight",
            size: .compact,
            action: {
                if reduceMotion {
                    action()
                } else {
                    withAnimation(TrailhoundMotion.cardSpring) {
                        action()
                    }
                }
            }
        )
        .id(key)
    }

    private func vehicleChip(
        title: String,
        key: String,
        isSelected: Bool,
        avatarSystemImage: String? = nil,
        avatarPhotoFileName: String? = nil,
        avatarIsElectric: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        GlassFilterChip(
            title: title,
            isSelected: isSelected,
            namespace: vehicleChipNamespace,
            highlightID: "tripVehicleFilterHighlight",
            size: .compact,
            avatarSystemImage: avatarSystemImage,
            avatarPhotoFileName: avatarPhotoFileName,
            avatarIsElectric: avatarIsElectric,
            action: {
                if reduceMotion {
                    action()
                } else {
                    withAnimation(TrailhoundMotion.cardSpring) {
                        action()
                    }
                }
            }
        )
        .id(key)
    }

    private func placeChip(
        title: String,
        key: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        GlassFilterChip(
            title: title,
            isSelected: isSelected,
            namespace: placeChipNamespace,
            highlightID: "tripPlaceFilterHighlight",
            size: .compact,
            action: {
                if reduceMotion {
                    action()
                } else {
                    withAnimation(TrailhoundMotion.cardSpring) {
                        action()
                    }
                }
            }
        )
        .id(key)
    }

    private func revealChip(withID id: String, using proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(id, anchor: .center)
        } else {
            withAnimation(TrailhoundMotion.cardSpring) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }
}

struct TripFilterChips: View {
    @Query(sort: \UserCategory.sortOrder) private var categories: [UserCategory]
    @Binding var selectedCategoryID: String?
    /// When embedded in a glass card, outer list insets already handle horizontal padding.
    var usesCardInsets: Bool = true

    @Namespace private var chipNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectionKey: String {
        if let selectedCategoryID { return "category:\(selectedCategoryID)" }
        return "all"
    }

    private var leadingInset: CGFloat {
        usesCardInsets ? GlassTokens.listContentHorizontalInset : 0
    }

    private var trailingInset: CGFloat {
        usesCardInsets ? GlassTokens.listContentHorizontalInset : 0
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text("\(L10n.filterCategory):")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
                .padding(.leading, leadingInset)
                .accessibilityHidden(true)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(
                            title: L10n.all,
                            key: "all",
                            isSelected: selectedCategoryID == nil
                        ) {
                            selectedCategoryID = nil
                        }
                        ForEach(categories) { category in
                            let id = category.id.uuidString
                            filterChip(
                                title: category.name,
                                key: "category:\(id)",
                                isSelected: selectedCategoryID == id
                            ) {
                                selectedCategoryID = selectedCategoryID == id ? nil : id
                            }
                        }
                    }
                    .padding(.trailing, trailingInset)
                    .animation(reduceMotion ? nil : TrailhoundMotion.cardSpring, value: selectionKey)
                }
                .onChange(of: selectionKey) { _, newKey in
                    revealChip(withID: newKey, using: proxy)
                }
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        }
        .frame(height: 32)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.filterCategory)
    }

    private func revealChip(withID id: String, using proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(id, anchor: .center)
        } else {
            withAnimation(TrailhoundMotion.cardSpring) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private func filterChip(
        title: String,
        key: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        GlassFilterChip(
            title: title,
            isSelected: isSelected,
            namespace: chipNamespace,
            highlightID: "tripFilterHighlight",
            size: .compact,
            action: {
                if reduceMotion {
                    action()
                } else {
                    withAnimation(TrailhoundMotion.cardSpring) {
                        action()
                    }
                }
            }
        )
        .id(key)
    }
}
