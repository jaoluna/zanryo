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
        XCTAssertEqual(presentation.modules[0].text, "15% · 5d03:00")
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

        XCTAssertEqual(presentation.modules[0].text, "15% · 5d03:00 ·")
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
        XCTAssertEqual(presentation.modules.map(\.text), ["75% · 4d", "42% · 2h"])
        XCTAssertTrue(presentation.modules.allSatisfy { $0.accessibilityLabel.contains("percent remaining") })
    }

    func testRemainingScaleDescendsFromFullToExhaustedWithoutChangingSnapshot() {
        for remaining in [100.0, 75.0, 0.0] {
            let snapshot = makeSnapshot(remaining: remaining, freshness: .fresh)
            let presentation = StatusPresentation.make(snapshot: snapshot, now: now)
            XCTAssertEqual(presentation.modules.first?.text, "\(Int(remaining))% · 5d03:00")
            XCTAssertEqual(snapshot.quota.weekly.remainingPercent, remaining)
        }
    }

    func testClaudeExpiredFiveHourFallsBackToCurrentWeekly() throws {
        let five = RateLimit(kind: .fiveHour, limitId: "five", remainingPercent: 3,
            resetsAt: now, observedAt: now.addingTimeInterval(-60))
        let week = RateLimit(kind: .weekly, limitId: "week", remainingPercent: 90,
            resetsAt: now.addingTimeInterval(3 * 86400), observedAt: now)
        let snapshot = ClaudeUsageSnapshot(provider: .claude, fiveHour: five, weekly: week, freshness: .fresh)
        let result = StatusPresentation.claude(snapshot: snapshot, enabled: true, hasError: false, now: now)
        let module = try XCTUnwrap(result.modules.first)
        XCTAssertEqual(module.remainingPercent, 90)
        XCTAssertEqual(module.reset, "3d00:00")
        XCTAssertFalse(module.isStale)
        XCTAssertTrue(StatusPresentation.claude(snapshot: snapshot, enabled: true, hasError: true, now: now).modules[0].isStale)
        let stale = ClaudeUsageSnapshot(provider: .claude, fiveHour: five, weekly: week, freshness: .stale)
        XCTAssertTrue(StatusPresentation.claude(snapshot: stale, enabled: true, hasError: false, now: now).modules[0].isStale)
    }

    func testClaudeRetainsLastReadingAsStaleWhenNoCurrentWindowExists() throws {
        let five = RateLimit(kind: .fiveHour, limitId: "five", remainingPercent: 3,
            resetsAt: now, observedAt: now.addingTimeInterval(-60))
        let snapshot = ClaudeUsageSnapshot(provider: .claude, fiveHour: five, weekly: nil, freshness: .fresh)
        let result = StatusPresentation.claude(snapshot: snapshot, enabled: true, hasError: false, now: now)
        let module = try XCTUnwrap(result.modules.first)
        XCTAssertEqual(module.remainingPercent, 3)
        XCTAssertTrue(module.isStale)
    }

    func testClaudeDoesNotPreferOldOrFutureDatedFiveHourReading() throws {
        let week = RateLimit(kind: .weekly, limitId: "week", remainingPercent: 90,
            resetsAt: now.addingTimeInterval(86400), observedAt: now)
        for offset in [-361.0, 1.0] {
            let five = RateLimit(kind: .fiveHour, limitId: "five", remainingPercent: 50,
                resetsAt: now.addingTimeInterval(3600), observedAt: now.addingTimeInterval(offset))
            let snapshot = ClaudeUsageSnapshot(provider: .claude, fiveHour: five, weekly: week, freshness: .fresh)
            let result = StatusPresentation.claude(snapshot: snapshot, enabled: true, hasError: false, now: now)
            XCTAssertEqual(result.modules.first?.remainingPercent, 90)
            XCTAssertEqual(result.modules.first?.isStale, false)
        }
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
