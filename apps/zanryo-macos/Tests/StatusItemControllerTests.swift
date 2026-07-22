import AppKit
import XCTest
@testable import Zanryo

@MainActor
final class StatusItemControllerTests: XCTestCase {
    func testUpdateEmbedsAccessibleDragonPresentationWithoutButtonTitle() throws {
        let controller = StatusItemController(onAction: { _, _, _ in })
        defer { controller.invalidate() }
        let presentation = StatusPresentation(
            modules: [
                ProviderModule(
                    provider: .openAI,
                    remainingPercent: 15,
                    reset: "5d 3h",
                    resetSpoken: "5 days and 3 hours",
                    isStale: false
                )
            ]
        )

        controller.update(presentation)

        let button = try XCTUnwrap(controller.button)
        XCTAssertEqual(button.attributedTitle.string, "")
        XCTAssertEqual(button.accessibilityLabel(), presentation.accessibilityLabel)
        XCTAssertEqual(controller.presentation, presentation)
        XCTAssertGreaterThan(controller.contentSize.width, 18)
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
