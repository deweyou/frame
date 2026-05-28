import CoreGraphics
import XCTest
@testable import FrameApp

final class SelectionHistoryTests: XCTestCase {
    func testRestoresSelectionWhenActiveDisplayMatchesHistoryDisplay() {
        let rect = CGRect(x: 10, y: 20, width: 300, height: 180)
        let history = SelectionHistory(rect: rect, displayID: 1)

        XCTAssertEqual(history.rectForRestore(activeDisplayID: 1), rect)
    }

    func testDropsSelectionWhenActiveDisplayDiffersFromHistoryDisplay() {
        let history = SelectionHistory(
            rect: CGRect(x: 10, y: 20, width: 300, height: 180),
            displayID: 1
        )

        XCTAssertNil(history.rectForRestore(activeDisplayID: 2))
    }

    func testDropsSelectionWhenEitherDisplayIDIsUnknown() {
        let historyWithoutDisplay = SelectionHistory(
            rect: CGRect(x: 10, y: 20, width: 300, height: 180),
            displayID: nil
        )
        let historyWithDisplay = SelectionHistory(
            rect: CGRect(x: 10, y: 20, width: 300, height: 180),
            displayID: 1
        )

        XCTAssertNil(historyWithoutDisplay.rectForRestore(activeDisplayID: 1))
        XCTAssertNil(historyWithDisplay.rectForRestore(activeDisplayID: nil))
    }
}
