import SwiftData
import SwiftUI

/// Search + date + category filters pinned directly above the trip rows.
struct TripListFiltersBar: View {
    @Binding var searchText: String
    @Binding var selectedDateSection: TripDateSection?
    @Binding var selectedCategoryID: String?

    @Namespace private var dateChipNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFiltersExpanded = false

    private var dateSelectionKey: String {
        if let selectedDateSection { return "date:\(selectedDateSection.rawValue)" }
        return "date:all"
    }

    private var hasChipFiltersActive: Bool {
        selectedDateSection != nil || selectedCategoryID != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                searchField
                filtersToggleButton
            }
            .padding(.horizontal, GlassTokens.listContentHorizontalInset)

            if isFiltersExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    dateFilterRow
                    TripFilterChips(selectedCategoryID: $selectedCategoryID)
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
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.tripsFilters)
        .accessibilityAddTraits(isFiltersExpanded ? .isSelected : [])
    }

    private var dateFilterRow: some View {
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
                .padding(.horizontal, GlassTokens.listContentHorizontalInset)
                .animation(reduceMotion ? nil : TrailhoundMotion.cardSpring, value: dateSelectionKey)
            }
            .onChange(of: dateSelectionKey) { _, newKey in
                revealChip(withID: newKey, using: proxy)
            }
        }
        .frame(height: 36)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
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
                .padding(.horizontal, GlassTokens.listContentHorizontalInset)
                .animation(reduceMotion ? nil : TrailhoundMotion.cardSpring, value: selectionKey)
            }
            .onChange(of: selectionKey) { _, newKey in
                revealChip(withID: newKey, using: proxy)
            }
        }
        .frame(height: 36)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
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
