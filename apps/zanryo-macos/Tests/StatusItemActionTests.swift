import AppKit
import XCTest
@testable import Zanryo

final class StatusItemActionTests: XCTestCase {
    func testRightMouseAndControlClickUseContextMenu() {
        XCTAssertEqual(
            StatusItemAction.resolve(eventType: .rightMouseUp, modifierFlags: []),
            .showContextMenu
        )
        XCTAssertEqual(
            StatusItemAction.resolve(eventType: .leftMouseUp, modifierFlags: [.control]),
            .showContextMenu
        )
    }

    func testPrimaryClickTogglesPopover() {
        XCTAssertEqual(
            StatusItemAction.resolve(eventType: .leftMouseUp, modifierFlags: []),
            .togglePopover
        )
    }
}
