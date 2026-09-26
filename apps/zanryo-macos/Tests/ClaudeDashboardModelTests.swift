import XCTest
@testable import Zanryo

final class ClaudeDashboardModelTests: XCTestCase {
    func testShortFlatHistoryUsesActualTimeSpanAndKeepsProjectionSeparate() throws {
        let now = Date()
        let snapshot = ClaudeDashboardFixture.flatSnapshot(now: now)
        let model = ClaudeDashboardModel.make(snapshot: snapshot, hasError: false, now: now)
        XCTAssertEqual(model.historySeries.map(\.remainingPercent), [97, 97])
        XCTAssertEqual(model.historyDomain, now.addingTimeInterval(-3600)...now)
        XCTAssertEqual(model.projectionDomain, now...snapshot.weekly!.resetsAt)
        XCTAssertEqual(model.historyCaption, "1h recorded · no change observed")
        XCTAssertTrue(model.projectionSeries.allSatisfy { $0.kind != .observed })
        let budget = model.series.filter { $0.kind == .sustainable }
        XCTAssertEqual(budget.first?.at, snapshot.weekly!.resetsAt.addingTimeInterval(-7 * 86400))
        XCTAssertEqual(budget.first?.remainingPercent, 100)
        XCTAssertEqual(budget.last?.remainingPercent, 0)
        XCTAssertTrue(model.explanation.contains("Low confidence"))
    }

    func testSinglePointHasLegibleDomainWithoutFabricatingEarlierPoints() {
        let now = Date()
        let model = ClaudeDashboardModel.make(snapshot: ClaudeDashboardFixture.snapshot(now: now, collecting: true), hasError: false, now: now)
        XCTAssertEqual(model.historyDomain, now.addingTimeInterval(-3600)...now)
        XCTAssertEqual(model.historySeries.count, 1)
        XCTAssertNil(model.projectionDomain)
        XCTAssertTrue(model.projectionSeries.isEmpty)
    }

    func testEstimatedWeeklyHistoryAndMetricsRemainIndependentOfFiveHour() {
        let now = Date()
        let snapshot = ClaudeDashboardFixture.snapshot(now: now)
        let model = ClaudeDashboardModel.make(snapshot: snapshot, hasError: false, now: now)
        XCTAssertTrue(model.hasProjection)
        XCTAssertEqual(model.pace, "12.0 pp/day · 2.5 pp/5h")
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
            XCTAssertEqual(model.historySeries.count, 3)
            XCTAssertFalse(model.series.contains { $0.kind == .forecast })
            XCTAssertEqual(model.pace, "Refresh needed")
        }
    }

    func testCollectingShowsRealObservationsWithoutInventedCycleStart() {
        let now = Date()
        let model = ClaudeDashboardModel.make(snapshot: ClaudeDashboardFixture.snapshot(now: now, collecting: true), hasError: false, now: now)
        XCTAssertFalse(model.hasProjection)
        XCTAssertEqual(model.historySeries.count, 1)
        XCTAssertEqual(model.series.filter { $0.kind == .sustainable }.count, 2)
        XCTAssertEqual(model.series.first?.remainingPercent, 74)
        XCTAssertEqual(model.series.first?.at, now)
        XCTAssertEqual(model.pace, "Collecting history")
    }

    func testOlderBridgeAndFiveHourOnlyDoNotInventWeeklyData() {
        let now = Date()
        let original = ClaudeDashboardFixture.snapshot(now: now)
        let legacy = ClaudeUsageSnapshot(provider: .claude, fiveHour: original.fiveHour, weekly: original.weekly, freshness: .fresh)
        XCTAssertEqual(ClaudeDashboardModel.make(snapshot: legacy, hasError: false, now: now).historySeries.count, 1)
        let fiveOnly = ClaudeUsageSnapshot(provider: .claude, fiveHour: original.fiveHour, weekly: nil, freshness: .fresh)
        let model = ClaudeDashboardModel.make(snapshot: fiveOnly, hasError: false, now: now)
        XCTAssertTrue(model.series.isEmpty)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNil(model.domain)
        XCTAssertTrue(ClaudeDashboardModel.make(snapshot: nil, hasError: false, now: now).series.isEmpty)
    }

    func testIdealCycleGuideDoesNotMoveWithCurrentBalanceOrForecastAvailability() {
        let now = Date()
        let reset = now.addingTimeInterval(5 * 86400)
        var guides: [[PopoverForecastPoint]] = []
        for balance in [0.0, 21, 74, 97, 100] {
            let weekly = RateLimit(kind: .weekly, limitId: "weekly", remainingPercent: balance,
                                   resetsAt: reset, observedAt: now)
            for stale in [false, true] {
                let model = WeeklyOutlookModel.make(weekly: weekly, report: nil, isStale: stale)
                guides.append(model.series.filter { $0.kind == .sustainable })
                XCTAssertEqual(model.historySeries.map(\.remainingPercent), [balance])
                XCTAssertFalse(model.hasProjection)
                XCTAssertTrue(model.projectionSeries.isEmpty)
            }
        }
        XCTAssertTrue(guides.allSatisfy { $0 == guides[0] })
        XCTAssertEqual(guides[0].map(\.remainingPercent), [100, 0])
        XCTAssertEqual(guides[0].map(\.at), [reset.addingTimeInterval(-7 * 86400), reset])
    }
}

enum ClaudeDashboardFixture {
    /// Matches the early live shape: one hour of unchanged, already-used quota.
    static func flatSnapshot(now: Date) -> ClaudeUsageSnapshot {
        let reset = now.addingTimeInterval(5 * 86400)
        return ClaudeUsageSnapshot(provider: .claude,
            fiveHour: .init(kind: .fiveHour, limitId: "claude_five_hour", remainingPercent: 99,
                            resetsAt: now.addingTimeInterval(14_100), observedAt: now),
            weekly: .init(kind: .weekly, limitId: "claude_weekly", remainingPercent: 97,
                          resetsAt: reset, observedAt: now), freshness: .fresh,
            weeklyForecast: .init(status: .estimated, confidence: .low, consumedPerDay: 0,
                sustainablePerDay: 19.4, paceDifference: -19.4, estimatedDepletionAt: nil, rateRange: nil,
                chart: .init(observed: [
                    .init(at: now.addingTimeInterval(-3600), remainingPercent: 97),
                    .init(at: now, remainingPercent: 97)],
                    forecast: [.init(at: now, remainingPercent: 97, uncertainty: .init(low: 97, high: 97)),
                               .init(at: reset, remainingPercent: 97, uncertainty: .init(low: 97, high: 97))],
                    sustainable: [.init(at: reset.addingTimeInterval(-7 * 86400), remainingPercent: 100),
                                  .init(at: reset, remainingPercent: 0)])))
    }

    static func snapshot(now: Date, collecting: Bool = false, stale: Bool = false,
                         resetAfter: TimeInterval = 5 * 86400) -> ClaudeUsageSnapshot {
        let reset = now.addingTimeInterval(resetAfter)
        let dailyBudget = 74 / (resetAfter / 86400)
        let projected = max(0, 74 - 12 * resetAfter / 86400)
        let observed = collecting ? [ChartPoint(at: now, remainingPercent: 74)] : [
            ChartPoint(at: now.addingTimeInterval(-86400), remainingPercent: 86),
            ChartPoint(at: now.addingTimeInterval(-43200), remainingPercent: 80),
            ChartPoint(at: now, remainingPercent: 74),
        ]
        let report = ForecastReport(status: collecting ? .collectingHistory : .estimated,
            confidence: collecting ? .collecting : .medium,
            consumedPerDay: collecting ? nil : 12, sustainablePerDay: collecting ? nil : dailyBudget,
            paceDifference: collecting ? nil : 12 - dailyBudget, estimatedDepletionAt: nil, rateRange: nil,
            chart: ChartSeries(observed: observed,
                forecast: collecting ? [] : [
                    ForecastPoint(at: now, remainingPercent: 74, uncertainty: .init(low: 74, high: 74)),
                    ForecastPoint(at: reset, remainingPercent: projected, uncertainty: .init(low: max(0, projected - 10), high: projected + 10)),
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
