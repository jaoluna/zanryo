import AppKit
import XCTest
@testable import Zanryo

@MainActor
final class StatusItemContextMenuTests: XCTestCase {
    func testContextMenuHasRefreshAndQuitAndDisablesRefreshWhileBusy() {
        let menu = StatusItemContextMenu.makeMenu(
            isRefreshing: true,
            onRefresh: {},
            onQuit: {}
        )

        XCTAssertEqual(menu.items.map(\.title), ["Refresh now", "", "Quit Zanryo"])
        XCTAssertFalse(menu.items[0].isEnabled)
        XCTAssertEqual(menu.items[2].keyEquivalent, "q")
        XCTAssertEqual(menu.items[2].keyEquivalentModifierMask, [.command])
    }

    func testContextMenuRoutesRefreshAndQuitActions() throws {
        var refreshCount = 0
        var quitCount = 0
        let menu = StatusItemContextMenu.makeMenu(
            isRefreshing: false,
            onRefresh: { refreshCount += 1 },
            onQuit: { quitCount += 1 }
        )
        let refreshItem = try XCTUnwrap(menu.items.first)
        let quitItem = try XCTUnwrap(menu.items.last)
        let refreshTarget = try XCTUnwrap(refreshItem.target as? NSObject)
        let quitTarget = try XCTUnwrap(quitItem.target as? NSObject)

        _ = refreshTarget.perform(try XCTUnwrap(refreshItem.action), with: refreshItem)
        _ = quitTarget.perform(try XCTUnwrap(quitItem.action), with: quitItem)

        XCTAssertEqual(refreshCount, 1)
        XCTAssertEqual(quitCount, 1)
    }
}
