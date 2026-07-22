import XCTest
@testable import Zanryo

final class StatusPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_774_171_200)

    func testWeeklySnapshotRendersOpenAIModuleWithoutProductName() {
        let presentation = StatusPresentation.make(
            snapshot: makeSnapshot(remaining: 15, freshness: .fresh),
            now: now
        )

        XCTAssertEqual(presentation.modules.count, 1)
        XCTAssertEqual(presentation.modules[0].provider, .openAI)
        XCTAssertEqual(presentation.modules[0].text, "15% · 5d 3h")
        XCTAssertFalse(presentation.dragonOnly)
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "OpenAI has 15 percent remaining. Resets in 5 days and 3 hours."
        )
    }

    func testRecognizedFiveHourOtherWindowTakesPriorityOverWeekly() {
        let presentation = StatusPresentation.make(
            snapshot: makeSnapshot(
                remaining: 15,
                freshness: .fresh,
                other: [
                    RateLimit(
                        kind: .other,
                        limitId: "five_hour",
                        remainingPercent: 61,
                        resetsAt: now.addingTimeInterval(3 * 3_600),
                        observedAt: now
                    )
                ]
            ),
            now: now
        )

        XCTAssertEqual(presentation.modules[0].text, "61% · 3h")
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "OpenAI has 61 percent remaining. Resets in 3 hours."
        )
    }

    func testStaleSnapshotAppendsMarkerAndVoiceOverWarning() {
        let presentation = StatusPresentation.make(
            snapshot: makeSnapshot(remaining: 15, freshness: .stale),
            now: now
        )

        XCTAssertEqual(presentation.modules[0].text, "15% · 5d 3h ·")
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "OpenAI has 15 percent remaining. Resets in 5 days and 3 hours. Data may be outdated."
        )
    }

    func testDisabledOrMissingDataRendersDragonOnlyInsteadOfFakeZero() {
        let disabled = StatusPresentation.make(
            snapshot: makeSnapshot(remaining: 15, freshness: .fresh),
            openAIEnabled: false,
            now: now
        )
        let missing = StatusPresentation.make(snapshot: nil, now: now)

        XCTAssertTrue(disabled.modules.isEmpty)
        XCTAssertTrue(disabled.dragonOnly)
        XCTAssertTrue(missing.modules.isEmpty)
        XCTAssertTrue(missing.dragonOnly)
        XCTAssertFalse(missing.accessibilityLabel.contains("0 percent"))
    }

    func testProviderModulesStayInOpenAIThenClaudeOrder() {
        let presentation = StatusPresentation(
            modules: [
                ProviderModule(provider: .claude, remainingPercent: 42, reset: "2h", resetSpoken: "2 hours", isStale: false),
                ProviderModule(provider: .openAI, remainingPercent: 75, reset: "4d", resetSpoken: "4 days", isStale: false)
            ]
        )

        XCTAssertEqual(presentation.modules.map(\.provider), [.openAI, .claude])
    }

    private func makeSnapshot(
        remaining: Double,
        freshness: Freshness,
        other: [RateLimit] = []
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
                other: other,
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
}
