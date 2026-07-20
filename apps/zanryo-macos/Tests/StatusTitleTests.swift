import AppKit
import XCTest
@testable import Zanryo

final class StatusTitleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_774_171_200)

    func testFreshSnapshotFormatsPercentageAndResetDuration() {
        let title = StatusTitle.make(
            snapshot: makeSnapshot(remaining: 15, freshness: .fresh),
            now: now
        )

        XCTAssertEqual(title.attributed.string, "Zanryo 15% · 5d 3h")
    }

    func testStaleSnapshotAddsTrailingMarker() {
        let title = StatusTitle.make(
            snapshot: makeSnapshot(remaining: 15, freshness: .stale),
            now: now
        )

        XCTAssertEqual(title.attributed.string, "Zanryo 15% · 5d 3h ·")
    }

    func testMissingSnapshotUsesUnavailableCopy() {
        let title = StatusTitle.make(snapshot: nil, now: now)

        XCTAssertEqual(title.attributed.string, "Zanryo unavailable")
        XCTAssertEqual(title.accessibilityLabel, "Zanryo quota is unavailable.")
    }

    func testOnlyPercentageUsesWeeklyYellow() throws {
        let title = StatusTitle.make(
            snapshot: makeSnapshot(remaining: 15, freshness: .fresh),
            now: now
        )
        let percentageRange = (title.attributed.string as NSString).range(of: "15%")
        let percentageColor = try XCTUnwrap(
            title.attributed.attribute(
                .foregroundColor,
                at: percentageRange.location,
                effectiveRange: nil
            ) as? NSColor
        )
        let leadingColor = title.attributed.attribute(
            .foregroundColor,
            at: 0,
            effectiveRange: nil
        ) as? NSColor

        assertColor(percentageColor, red: 0xF2, green: 0xB6, blue: 0x32)
        XCTAssertNil(leadingColor)
    }

    func testAccessibilityDescribesRemainingQuotaAndReset() {
        let title = StatusTitle.make(
            snapshot: makeSnapshot(remaining: 15, freshness: .fresh),
            now: now
        )

        XCTAssertEqual(
            title.accessibilityLabel,
            "Zanryo has 15 percent of the weekly Codex limit remaining. Resets in 5 days and 3 hours."
        )
    }

    private func makeSnapshot(
        remaining: Double,
        freshness: Freshness
    ) -> DashboardSnapshot {
        let weekly = RateLimit(
            kind: .weekly,
            limitId: "codex",
            remainingPercent: remaining,
            resetsAt: now.addingTimeInterval((5 * 24 + 3) * 3_600),
            observedAt: now
        )
        return DashboardSnapshot(
            quota: QuotaSnapshot(
                weekly: weekly,
                spark: nil,
                other: [],
                freshness: freshness
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

    private func assertColor(
        _ color: NSColor,
        red: Int,
        green: Int,
        blue: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let converted = color.usingColorSpace(.deviceRGB) else {
            XCTFail("Color is not convertible to device RGB", file: file, line: line)
            return
        }
        XCTAssertEqual(converted.redComponent, CGFloat(red) / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(converted.greenComponent, CGFloat(green) / 255, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(converted.blueComponent, CGFloat(blue) / 255, accuracy: 0.001, file: file, line: line)
    }
}
