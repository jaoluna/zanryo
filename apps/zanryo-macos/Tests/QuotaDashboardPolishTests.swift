import XCTest
@testable import Zanryo

final class QuotaDashboardPolishTests: XCTestCase {
    func testMissingExpiredAndHistoricalSparkStayOutOfCurrentWindows() {
        let now = Date()
        let weekly = limit(.weekly, "codex", 21, now: now)
        let quota = QuotaSnapshot(weekly: weekly, spark: nil, other: [], freshness: .fresh)
        XCTAssertNil(quota.currentOptional(nil, now: now))
        XCTAssertNil(quota.currentOptional(limit(.spark, "spark", 100, now: now.addingTimeInterval(-8 * 86400)), now: now))
        // Even a future reset cannot make a previous collection current.
        let old = RateLimit(kind: .spark, limitId: "spark", remainingPercent: 100,
                            resetsAt: now.addingTimeInterval(86400), observedAt: now.addingTimeInterval(-3600))
        XCTAssertNil(quota.currentOptional(old, now: now))
        XCTAssertEqual(quota.currentOptional(limit(.spark, "spark", 32, now: now), now: now)?.remainingPercent, 32)
        XCTAssertEqual(quota.weekly.remainingPercent, 21)
    }

    func testFiveHourFieldDecodesAndDrivesMenuWithoutSumming() throws {
        let now = Date()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .secondsSince1970
        let stamp = now.timeIntervalSince1970
        let data = Data("""
        {"weekly":{"kind":"weekly","limit_id":"codex","remaining_percent":21,"resets_at":\(stamp + 86400),"observed_at":\(stamp)},
        "five_hour":{"kind":"five_hour","limit_id":"codex_primary","remaining_percent":43,"resets_at":\(stamp + 10800),"observed_at":\(stamp)},
        "spark":null,"other":[],"freshness":"fresh"}
        """.utf8)
        let quota = try decoder.decode(QuotaSnapshot.self, from: data)
        XCTAssertEqual(quota.currentFiveHour(now: now)?.remainingPercent, 43)
        let snapshot = DashboardSnapshot(quota: quota, forecast: ClaudeDashboardFixture.snapshot(now: now).weeklyForecast!)
        XCTAssertEqual(StatusPresentation.make(snapshot: snapshot, now: now).modules.first?.remainingPercent, 43)
        XCTAssertEqual(quota.weekly.remainingPercent, 21)
    }

    func testSingleTimelineIncludesHistoryAndForecastWithoutInvented100() throws {
        let now = Date()
        let snapshot = ClaudeDashboardFixture.flatSnapshot(now: now)
        let model = WeeklyOutlookModel.make(snapshot: snapshot, hasError: false, now: now)
        let timeline = WeeklyChartTimeline(series: model.series, reset: snapshot.weekly?.resetsAt)
        XCTAssertEqual(timeline.domain, now.addingTimeInterval(-3600)...snapshot.weekly!.resetsAt)
        XCTAssertEqual(Set(timeline.series.map(\.kind)), [.observed, .forecast, .sustainable])
        XCTAssertFalse(timeline.observed.isEmpty)
        XCTAssertTrue(timeline.observed.allSatisfy { $0.remainingPercent == 97 })
        XCTAssertEqual(timeline.boundary, now)
        XCTAssertEqual(timeline.historyCaption, "1h recorded · no change observed")
    }

    func testCodexAndClaudeHaveIdenticalOutlookRulesWithoutSharingQuota() {
        let now = Date()
        let snapshot = ClaudeDashboardFixture.snapshot(now: now)
        let claude = WeeklyOutlookModel.make(snapshot: snapshot, hasError: false, now: now)
        let codex = WeeklyOutlookModel.make(weekly: snapshot.weekly, report: snapshot.weeklyForecast, isStale: false)
        XCTAssertEqual(codex.series, claude.series)
        XCTAssertEqual(codex.rows, claude.rows)
        let stale = WeeklyOutlookModel.make(weekly: snapshot.weekly, report: snapshot.weeklyForecast, isStale: true)
        XCTAssertFalse(stale.hasProjection)
        XCTAssertTrue(stale.series.allSatisfy { $0.kind == .observed })
    }

    func testOpenAIAgeExpiryAndClockSkewCannotRemainFreshInMenu() {
        let now = Date()
        for date in [now.addingTimeInterval(-361), now.addingTimeInterval(1), now.addingTimeInterval(-90000)] {
            let quota = QuotaSnapshot(weekly: limit(.weekly, "codex", 21, now: date), spark: nil, other: [], freshness: .fresh)
            XCTAssertTrue(quota.isStale(at: now))
            let snapshot = DashboardSnapshot(quota: quota, forecast: ClaudeDashboardFixture.snapshot(now: now).weeklyForecast!)
            XCTAssertEqual(StatusPresentation.make(snapshot: snapshot, now: now).modules.first?.isStale, true)
        }
    }

    func testSingleChartAccessibilityDescribesOnlyAvailableSeries() {
        let now = Date()
        let snapshot = ClaudeDashboardFixture.flatSnapshot(now: now)
        let model = WeeklyOutlookModel.make(snapshot: snapshot, hasError: false, now: now)
        let timeline = WeeklyChartTimeline(series: model.series, reset: snapshot.weekly?.resetsAt)
        for provider in ["Claude", "Codex"] {
            let label = timeline.accessibilityLabel(provider: provider)
            XCTAssertTrue(label.contains("\(provider) weekly remaining quota."))
            XCTAssertTrue(label.contains("Solid line: observed."))
            XCTAssertTrue(label.contains("estimated, not guaranteed"))
            XCTAssertTrue(label.contains("allowed pace"))
            let saved = WeeklyChartTimeline(series: timeline.observed, reset: snapshot.weekly?.resetsAt)
            let savedLabel = saved.accessibilityLabel(provider: provider)
            XCTAssertTrue(savedLabel.contains("observed"))
            XCTAssertFalse(savedLabel.contains("estimated"))
            XCTAssertFalse(savedLabel.contains("allowed pace"))
            XCTAssertNil(saved.boundary)
            XCTAssertEqual(saved.domain, now.addingTimeInterval(-3600)...now)
        }
    }

    func testEmptyTimelineHasNoFakeDomainOrForecast() {
        let timeline = WeeklyChartTimeline(series: [], reset: Date().addingTimeInterval(86400))
        XCTAssertNil(timeline.domain)
        XCTAssertNil(timeline.boundary)
        XCTAssertFalse(timeline.hasProjection)
        XCTAssertEqual(timeline.historyCaption, "No weekly readings yet.")
        XCTAssertEqual(timeline.accessibilityLabel(provider: "Codex"), "Codex weekly remaining quota. No data available.")
    }

    private func limit(_ kind: LimitKind, _ id: String, _ percent: Double, now: Date) -> RateLimit {
        .init(kind: kind, limitId: id, remainingPercent: percent, resetsAt: now.addingTimeInterval(86400), observedAt: now)
    }
}
