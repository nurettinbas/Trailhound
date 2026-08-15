import XCTest
@testable import Trailhound

final class VehicleExpenseEditorDraftTests: XCTestCase {
    func testAmountParsesWholeDigitsOnly() {
        var draft = VehicleExpenseEditorDraft()
        draft.amountText = "10000"
        XCTAssertEqual(draft.amount, 10_000)
    }

    func testAmountRejectsDecimalCommaOrDot() {
        var draft = VehicleExpenseEditorDraft()
        draft.amountText = "10.50"
        XCTAssertNil(draft.amount)

        draft.amountText = "10,50"
        XCTAssertNil(draft.amount)
    }

    func testAmountRejectsEmptyAndNonDigits() {
        var draft = VehicleExpenseEditorDraft()
        draft.amountText = ""
        XCTAssertNil(draft.amount)

        draft.amountText = "abc"
        XCTAssertNil(draft.amount)
    }

    func testPrefillFromExpenseUsesRoundedWholeNumber() {
        let expense = VehicleExpense(category: .fuel, amount: 1250.50, occurredAt: Date())
        let draft = VehicleExpenseEditorDraft(from: expense)
        XCTAssertEqual(draft.amountText, "1251")
        XCTAssertEqual(draft.amount, 1251)
    }
}
