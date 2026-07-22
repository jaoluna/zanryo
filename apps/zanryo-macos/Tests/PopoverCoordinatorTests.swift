import AppKit
import XCTest
@testable import Zanryo

@MainActor
final class PopoverCoordinatorTests: XCTestCase {
    func testToggleAnchorsPopoverWithoutActivatingTheApp() throws {
        let store = ZanryoStore(provider: ImmediateDashboardProvider())
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 96, height: 22))
        var events: [String] = []
        var behavior: NSPopover.Behavior?
        let coordinator = PopoverCoordinator(
            store: store,
            showPopover: { popover, _ in
                behavior = popover.behavior
                events.append("show")
            }
        )

        coordinator.toggle(relativeTo: button)

        XCTAssertEqual(events, ["show"])
        XCTAssertEqual(behavior, .applicationDefined)
    }

    func testOutsideClickMonitorClosesPopoverAndTearsDownMonitor() throws {
        let store = ZanryoStore(provider: ImmediateDashboardProvider())
        let button = NSStatusBarButton(frame: NSRect(x: 0, y: 0, width: 96, height: 22))
        let monitorToken = NSObject()
        var outsideClickHandler: (() -> Void)?
        var removedMonitor: Any?
        var closeCount = 0
        let coordinator = PopoverCoordinator(
            store: store,
            showPopover: { _, _ in },
            startOutsideClickMonitoring: { handler in
                outsideClickHandler = handler
                return monitorToken
            },
            stopOutsideClickMonitoring: { monitor in
                removedMonitor = monitor
            },
            closePopover: { _ in closeCount += 1 }
        )

        coordinator.toggle(relativeTo: button)
        outsideClickHandler?()

        XCTAssertEqual(closeCount, 1)
        XCTAssertTrue((removedMonitor as AnyObject) === monitorToken)
    }
}

private actor ImmediateDashboardProvider: DashboardProviding {
    func cached() async throws -> DashboardSnapshot? {
        nil
    }

    func refresh() async throws -> DashboardSnapshot {
        let now = Date(timeIntervalSince1970: 1_774_171_200)
        let weekly = RateLimit(
            kind: .weekly,
            limitId: "codex",
            remainingPercent: 40,
            resetsAt: now.addingTimeInterval(5 * 86_400),
            observedAt: now
        )

        return DashboardSnapshot(
            quota: QuotaSnapshot(
                weekly: weekly,
                spark: nil,
                other: [],
                freshness: .fresh
            ),
            forecast: ForecastReport(
                status: .collectingHistory,
                confidence: .collecting,
                consumedPerDay: nil,
                sustainablePerDay: nil,
                paceDifference: nil,
                estimatedDepletionAt: nil,
                rateRange: nil,
                chart: ChartSeries(observed: [], forecast: [], sustainable: [])
            )
        )
    }
}
