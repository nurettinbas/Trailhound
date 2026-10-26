import StoreKit
import SwiftUI

struct TipJarView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = TipJarStore.shared

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphericBackground().ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(L10n.settingsTipJarMessage)
                            .font(.footnote)
                            .glassSecondaryInk()
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
                    .padding(16)
                }
            }
            .navigationTitle(L10n.settingsTipJar)
            .navigationBarTitleDisplayMode(.inline)
            .glassNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        GlassToolbarTitle(title: L10n.actionClose)
                    }
                    .accessibilityIdentifier("tipJar.close")
                }
            }
        }
        .toastHost(extraBottomPadding: 24)
        .task { await store.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch store.loadState {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        case .unavailable:
            Text(L10n.settingsTipJarUnavailable)
                .font(.footnote)
                .glassSecondaryInk()
                .accessibilityIdentifier("tipJar.unavailable")
        case .loaded:
            VStack(spacing: 12) {
                ForEach(store.products, id: \.id) { product in
                    tipRow(product)
                }
            }
        }
    }

    private func tipRow(_ product: Product) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName)
                    .font(.body.weight(.semibold))
                    .glassPrimaryInk()
                if !product.description.isEmpty {
                    Text(product.description)
                        .font(.footnote)
                        .glassSecondaryInk()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                Task { await store.tip(product) }
            } label: {
                if store.purchasingID == product.id {
                    ProgressView()
                } else {
                    Text(product.displayPrice)
                }
            }
            .trailhoundProminentButton()
            .disabled(store.purchasingID != nil)
            .accessibilityIdentifier("tipJar.product.\(product.id)")
            .accessibilityLabel("\(product.displayName), \(product.displayPrice)")
        }
        .glassElevatedTile()
    }
}
