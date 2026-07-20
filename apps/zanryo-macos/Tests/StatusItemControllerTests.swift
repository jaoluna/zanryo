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

    func testClickInvokesToggleWithStatusButton() throws {
        var clickedButton: NSStatusBarButton?
        let controller = StatusItemController { clickedButton = $0 }
        defer { controller.invalidate() }
        let button = try XCTUnwrap(controller.button)

        button.performClick(nil)

        XCTAssertTrue(clickedButton === button)
    }
}
