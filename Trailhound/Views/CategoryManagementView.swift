import SwiftData
import SwiftUI

enum SettingsFocusedField: Hashable {
    case fuelPrice
    case privacyRadius
    case newCategory
}

struct CategoryManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserCategory.sortOrder) private var categories: [UserCategory]
    @FocusState.Binding var focusedField: SettingsFocusedField?
    @State private var newCategoryName = ""

    private var rowCount: Int {
        categories.count + 1
    }

    var body: some View {
        Section(L10n.categorySection) {
            ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                HStack {
                    Image(systemName: category.systemImage)
                    Text(category.name)
                    if category.isBuiltIn {
                        Spacer()
                        Text(L10n.categoryBuiltinBadge)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .glassRow(position: GlassRowPosition.index(index, in: rowCount))
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
                Button(L10n.actionAdd) {
                    addCategory()
                }
                .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .glassRow(position: .last)
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
