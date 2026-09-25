import XCTest
@testable import Zanryo

final class ClaudeDashboardModelTests: XCTestCase {
    func testEstimatedWeeklyHistoryAndMetricsRemainIndependentOfFiveHour() {
        let now = Date()
        let snapshot = ClaudeDashboardFixture.snapshot(now: now)
        let model = ClaudeDashboardModel.make(snapshot: snapshot, hasError: false, now: now)
        XCTAssertTrue(model.hasProjection)
        XCTAssertEqual(model.pace, "12.0 pp/day")
        XCTAssertEqual(model.series.filter { $0.kind == .observed }.map(\.remainingPercent), [86, 80, 74])
        XCTAssertEqual(model.rows.first { $0.label == "At weekly reset" }?.value, "14.0% remaining")
        XCTAssertEqual(model.domain?.upperBound, snapshot.weekly?.resetsAt)
        XCTAssertEqual(snapshot.fiveHour?.remainingPercent, 42)
    }

    func testCachedErrorExpiredAndAgedReadingsKeepObservationsWithoutProjection() {
        let now = Date()
        for (snapshot, error) in [
            (ClaudeDashboardFixture.snapshot(now: now, stale: true), false),
            (ClaudeDashboardFixture.snapshot(now: now), true),
            (ClaudeDashboardFixture.snapshot(now: now.addingTimeInterval(-400)), false),
            (ClaudeDashboardFixture.snapshot(now: now.addingTimeInterval(-6 * 86400)), false),
        ] {
            let model = ClaudeDashboardModel.make(snapshot: snapshot, hasError: error, now: now)
            XCTAssertTrue(model.isStale)
            XCTAssertFalse(model.hasProjection)
            XCTAssertEqual(model.series.count, 3)
            XCTAssertTrue(model.series.allSatisfy { $0.kind == .observed })
            XCTAssertEqual(model.pace, "Refresh needed")
        }
    }

    func testCollectingShowsRealObservationsWithoutInventedCycleStart() {
        let now = Date()
        let model = ClaudeDashboardModel.make(snapshot: ClaudeDashboardFixture.snapshot(now: now, collecting: true), hasError: false, now: now)
        XCTAssertFalse(model.hasProjection)
        XCTAssertEqual(model.series.count, 1)
        XCTAssertEqual(model.series.first?.remainingPercent, 74)
        XCTAssertEqual(model.series.first?.at, now)
        XCTAssertEqual(model.pace, "Collecting history")
    }

    func testOlderBridgeAndFiveHourOnlyDoNotInventWeeklyData() {
        let now = Date()
        let original = ClaudeDashboardFixture.snapshot(now: now)
        let legacy = ClaudeUsageSnapshot(provider: .claude, fiveHour: original.fiveHour, weekly: original.weekly, freshness: .fresh)
        XCTAssertEqual(ClaudeDashboardModel.make(snapshot: legacy, hasError: false, now: now).series.count, 1)
        let fiveOnly = ClaudeUsageSnapshot(provider: .claude, fiveHour: original.fiveHour, weekly: nil, freshness: .fresh)
        let model = ClaudeDashboardModel.make(snapshot: fiveOnly, hasError: false, now: now)
        XCTAssertTrue(model.series.isEmpty)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNil(model.domain)
        XCTAssertTrue(ClaudeDashboardModel.make(snapshot: nil, hasError: false, now: now).series.isEmpty)
    }
}

enum ClaudeDashboardFixture {
    static func snapshot(now: Date, collecting: Bool = false, stale: Bool = false) -> ClaudeUsageSnapshot {
        let reset = now.addingTimeInterval(5 * 86400)
        let observed = collecting ? [ChartPoint(at: now, remainingPercent: 74)] : [
            ChartPoint(at: now.addingTimeInterval(-86400), remainingPercent: 86),
            ChartPoint(at: now.addingTimeInterval(-43200), remainingPercent: 80),
            ChartPoint(at: now, remainingPercent: 74),
        ]
        let report = ForecastReport(status: collecting ? .collectingHistory : .estimated,
            confidence: collecting ? .collecting : .medium,
            consumedPerDay: collecting ? nil : 12, sustainablePerDay: collecting ? nil : 14.8,
            paceDifference: collecting ? nil : -2.8, estimatedDepletionAt: nil, rateRange: nil,
            chart: ChartSeries(observed: observed,
                forecast: collecting ? [] : [
                    ForecastPoint(at: now, remainingPercent: 74, uncertainty: .init(low: 74, high: 74)),
                    ForecastPoint(at: reset, remainingPercent: 14, uncertainty: .init(low: 4, high: 24)),
                ], sustainable: collecting ? [] : [
                    ChartPoint(at: now, remainingPercent: 74), ChartPoint(at: reset, remainingPercent: 0),
                ]))
        return ClaudeUsageSnapshot(provider: .claude,
            fiveHour: RateLimit(kind: .fiveHour, limitId: "claude_five_hour", remainingPercent: 42,
                               resetsAt: now.addingTimeInterval(10800), observedAt: now),
            weekly: RateLimit(kind: .weekly, limitId: "claude_weekly", remainingPercent: 74,
                             resetsAt: reset, observedAt: now),
            freshness: stale ? .stale : .fresh, weeklyForecast: report)
    }
}
