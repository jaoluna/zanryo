import AppKit
import XCTest
@testable import Zanryo

@MainActor
final class StatusItemControllerTests: XCTestCase {
    func testUpdateAppliesTitleAndAccessibilityToStatusButton() throws {
        let controller = StatusItemController(onToggle: { _ in })
        defer { controller.invalidate() }
        let title = StatusTitle(
            attributed: NSAttributedString(string: "Zanryo 15% · 5d 3h"),
            accessibilityLabel: "Weekly Codex quota has 15 percent remaining."
        )

        controller.update(title)

        let button = try XCTUnwrap(controller.button)
        XCTAssertEqual(button.attributedTitle.string, "Zanryo 15% · 5d 3h")
        XCTAssertEqual(button.accessibilityLabel(), title.accessibilityLabel)
    }

    func testPrimaryClickInvokesPopoverToggleWithStatusButton() throws {
        var receivedAction: StatusItemAction?
        var clickedButton: NSStatusBarButton?
        let controller = StatusItemController { action, button, _ in
            receivedAction = action
            clickedButton = button
        }
        defer { controller.invalidate() }
        let button = try XCTUnwrap(controller.button)

        button.performClick(nil)

        XCTAssertEqual(receivedAction, .togglePopover)
        XCTAssertTrue(clickedButton === button)
    }

    func testHighlightUpdatesStatusButtonState() throws {
        let controller = StatusItemController { _, _, _ in }
        defer { controller.invalidate() }
        let button = try XCTUnwrap(controller.button)

        controller.setHighlighted(true)

        XCTAssertTrue(button.isHighlighted)
        controller.setHighlighted(false)
        XCTAssertFalse(button.isHighlighted)
    }

    func testInvalidationIsIdempotent() {
        let controller = StatusItemController { _, _, _ in }

        XCTAssertNoThrow({
            controller.invalidate()
            controller.invalidate()
        }())
    }
}
