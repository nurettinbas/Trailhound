import SwiftData
import SwiftUI

enum SettingsFocusedField: Hashable {
    case newCategory
    case fuelPrice
    case privacyRadius

    var previous: SettingsFocusedField? {
        switch self {
        case .newCategory: nil
        case .fuelPrice: .newCategory
        case .privacyRadius: .fuelPrice
        }
    }

    var next: SettingsFocusedField? {
        switch self {
        case .newCategory: .fuelPrice
        case .fuelPrice: .privacyRadius
        case .privacyRadius: nil
        }
    }

    var title: String {
        switch self {
        case .newCategory: L10n.categoryNewPlaceholder
        case .fuelPrice: L10n.settingsFuelPrice
        case .privacyRadius: L10n.settingsPrivacyRadius
        }
    }
}

struct CategoryManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserCategory.sortOrder) private var categories: [UserCategory]
    @FocusState.Binding var focusedField: SettingsFocusedField?
    @State private var newCategoryName = ""

    private var rowCount: Int {
        categories.count + 1
    }

    private var compactRowInsets: EdgeInsets {
        EdgeInsets(
            top: 7,
            leading: GlassTokens.listContentHorizontalInset,
            bottom: 7,
            trailing: GlassTokens.listContentHorizontalInset
        )
    }

    var body: some View {
        Section(L10n.categorySection) {
            ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                HStack(spacing: 10) {
                    Image(systemName: category.systemImage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text(category.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    if category.isBuiltIn {
                        Spacer(minLength: 8)
                        Text(L10n.categoryBuiltinBadge)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .glassRow(position: GlassRowPosition.index(index, in: rowCount))
                .listRowInsets(compactRowInsets)
                .swipeActions(edge: .trailing, allowsFullSwipe: !category.isBuiltIn) {
                    if !category.isBuiltIn {
                        Button(role: .destructive) {
                            deleteCategory(category)
                        } label: {
                            Label(L10n.delete, systemImage: "trash")
                        }
                        .destructiveTint()
                    }
                }
            }

            HStack {
                TextField(L10n.categoryNewPlaceholder, text: $newCategoryName)
                    .focused($focusedField, equals: .newCategory)
                    .glassInputField()
                Button(L10n.actionAdd) {
                    addCategory()
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 10))
                .tint(TrailhoundBrandColors.brandBottom)
                .fixedSize()
                .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .glassRow(position: .last)
            .listRowInsets(compactRowInsets)
        }
    }

    private func addCategory() {
        let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let order = (categories.map(\.sortOrder).max() ?? 0) + 1
        let category = UserCategory(name: name, sortOrder: order)
        modelContext.insert(category)
        try? modelContext.save()
        newCategoryName = ""
        ToastPresenter.shared.show(.categoryAdded)
    }

    private func deleteCategory(_ category: UserCategory) {
        guard !category.isBuiltIn else { return }
        modelContext.delete(category)
        try? modelContext.save()
        ToastPresenter.shared.show(.categoryDeleted)
    }
}
