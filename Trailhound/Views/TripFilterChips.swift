import SwiftData
import SwiftUI

/// Search + date + category + vehicle filters pinned directly above the trip rows.
struct TripListFiltersBar: View {
    @Binding var searchText: String
    @Binding var selectedDateSection: TripDateSection?
    @Binding var selectedCategoryID: String?
    @Binding var selectedVehicleFilter: TripListPage.VehicleFilter?
    var vehicles: [VehicleProfile] = []

    @Namespace private var dateChipNamespace
    @Namespace private var vehicleChipNamespace
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
        return count
    }

    private var hasChipFiltersActive: Bool {
        activeChipFilterCount > 0
    }

    private var sortedVehicles: [VehicleProfile] {
        vehicles.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                searchField
                filtersToggleButton
                if hasChipFiltersActive {
                    clearFiltersButton
                }
            }
            .padding(.horizontal, GlassTokens.listContentHorizontalInset)
            .animation(reduceMotion ? nil : TrailhoundMotion.cardSpring, value: hasChipFiltersActive)

            if isFiltersExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    dateFilterRow
                    TripFilterChips(selectedCategoryID: $selectedCategoryID)
                    vehicleFilterRow
                }
                .transition(filtersRevealTransition)
            }
        }
        .padding(.vertical, 4)
        .animation(reduceMotion ? nil : TrailhoundMotion.cardSpring, value: isFiltersExpanded)
    }

    private var filtersRevealTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(L10n.searchTrips, text: $searchText)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glassField(cornerRadius: 12)
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
                .font(.system(size: 20, weight: .semibold))
                .symbolVariant(isFiltersExpanded || hasChipFiltersActive ? .fill : .none)
                .foregroundStyle(
                    isFiltersExpanded || hasChipFiltersActive
                        ? TrailhoundBrandColors.brandBottom
                        : Color.secondary
                )
                .frame(width: 44, height: 44)
                .glassField(cornerRadius: 12)
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
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(TrailhoundBrandColors.brandBottom)
                .frame(width: 44, height: 44)
                .glassField(cornerRadius: 12)
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
        }
        if reduceMotion {
            clear()
        } else {
            withAnimation(TrailhoundMotion.cardSpring) {
                clear()
            }
        }
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
                    .padding(.trailing, GlassTokens.listContentHorizontalInset)
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
                                isSelected: selectedVehicleFilter == filter
                            ) {
                                selectedVehicleFilter = selectedVehicleFilter == filter ? nil : filter
                            }
                        }
                    }
                    .padding(.trailing, GlassTokens.listContentHorizontalInset)
                    .animation(reduceMotion ? nil : TrailhoundMotion.cardSpring, value: vehicleSelectionKey)
                }
                .onChange(of: vehicleSelectionKey) { _, newKey in
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
                .padding(.leading, GlassTokens.listContentHorizontalInset)
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
        action: @escaping () -> Void
    ) -> some View {
        GlassFilterChip(
            title: title,
            isSelected: isSelected,
            namespace: vehicleChipNamespace,
            highlightID: "tripVehicleFilterHighlight",
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

    @Namespace private var chipNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectionKey: String {
        if let selectedCategoryID { return "category:\(selectedCategoryID)" }
        return "all"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text("\(L10n.filterCategory):")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize()
                .padding(.leading, GlassTokens.listContentHorizontalInset)
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
                    .padding(.trailing, GlassTokens.listContentHorizontalInset)
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
