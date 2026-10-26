import StoreKit
import StoreKitTest
import XCTest
@testable import Trailhound

@MainActor
final class TipJarStoreTests: XCTestCase {
    private var session: SKTestSession?

    private static var configurationURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Trailhound/TrailhoundTips.storekit")
    }

    override func tearDown() {
        session?.clearTransactions()
        session = nil
        super.tearDown()
    }

    func testConfigurationListsTheThreeConsumableTips() throws {
        let data = try Data(contentsOf: Self.configurationURL)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = try XCTUnwrap(root["products"] as? [[String: Any]])
        XCTAssertEqual(products.compactMap { $0["productID"] as? String }, TipJarStore.productIDs)
        XCTAssertTrue(products.allSatisfy { $0["type"] as? String == "Consumable" })
        let prices = products.compactMap { ($0["displayPrice"] as? String).flatMap(Double.init) }
        XCTAssertEqual(prices, prices.sorted())
    }

    func testProductsLoadSortedByPrice() async throws {
        let products = try await loadProducts(TipJarStore.productIDs)
        XCTAssertEqual(Set(products.map(\.id)), Set(TipJarStore.productIDs))
        XCTAssertEqual(TipJarStore.sortedByPrice(products).map(\.id), TipJarStore.productIDs)
        XCTAssertTrue(products.allSatisfy { $0.type == .consumable })
    }

    func testTipFinishesTheTransaction() async throws {
        let fetched = try await loadProducts(["com.trailhound.app.tip.small"])
        let product = try XCTUnwrap(fetched.first)
        let store = TipJarStore()
        let succeeded = await store.tip(product)
        XCTAssertTrue(succeeded)
        XCTAssertNil(store.purchasingID)

        var unfinished = 0
        for await _ in Transaction.unfinished { unfinished += 1 }
        XCTAssertEqual(unfinished, 0)
    }

    /// The StoreKit test service is not reachable from every runner (for example `xcodebuild` without Xcode open).
    private func loadProducts(_ ids: [String]) async throws -> [Product] {
        let session = try SKTestSession(contentsOf: Self.configurationURL)
        session.disableDialogs = true
        session.clearTransactions()
        self.session = session
        let products = try await Product.products(for: ids)
        if products.isEmpty {
            throw XCTSkip("StoreKit test session unavailable on this runner; run from Xcode.")
        }
        return products
    }
}
