import XCTest
@testable import Zanryo

final class PopoverDashboardModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_774_171_200)

    func testCollectingHistorySnapshotShowsForecastStatusAndObservedOnlyCopy() {
        let model = PopoverDashboardModel.make(
            from: makeForecastSnapshot(status: .collectingHistory),
            now: now
        )

        XCTAssertEqual(model.forecastTitle, "Collecting history")
        XCTAssertEqual(model.forecastConfidence, "Collecting")
        XCTAssertFalse(model.hasForecastProjection)
        XCTAssertEqual(model.forecastMetrics, [PopoverMetric(label: "Observed", value: "Collecting history")])
        XCTAssertTrue(
            model.forecastSeries.allSatisfy { $0.kind == .observed || $0.kind == .forecast || $0.kind == .sustainable }
        )
    }

    func testEstimatedForecastExposesObservedForecastAndSustainableSeries() {
        let model = PopoverDashboardModel.make(
            from: makeForecastSnapshot(
                status: .estimated,
                consumed: 12.5,
                sustainable: 10.2,
                paceDiff: 2.3,
                depletionHours: 36,
                observedPoint: 84,
                forecastPoint: 72,
                sustainablePoint: 70
            ),
            now: now
        )

        XCTAssertEqual(model.forecastTitle, "Estimated forecast")
        XCTAssertEqual(model.forecastConfidence, "Low")
        XCTAssertEqual(model.forecastMetrics.first?.label, "Observed pace")
        XCTAssertEqual(model.forecastMetrics.first?.value, "12.5/day")
        XCTAssertEqual(model.forecastMetrics[safe: 1]?.label, "Sustainable pace")
        XCTAssertEqual(model.forecastMetrics[safe: 1]?.value, "10.2/day")
        XCTAssertTrue(model.hasForecastProjection)
        XCTAssertTrue(model.forecastSeries.contains(where: { $0.kind == .observed }))
        XCTAssertTrue(model.forecastSeries.contains(where: { $0.kind == .forecast }))
        XCTAssertTrue(model.forecastSeries.contains(where: { $0.kind == .sustainable }))
    }

    func testApiSpendAndThemeHaveExpectedDefaults() {
        let model = PopoverDashboardModel.make(from: makeForecastSnapshot(status: .estimated), now: now)
        XCTAssertEqual(model.apiSpendText, "Not configured")
        XCTAssertEqual(model.themeText, "Coming soon")
    }

    func testWeeklyResetAndSparkShowExpectedCopies() {
        let model = PopoverDashboardModel.make(from: makeForecastSnapshot(status: .estimated), now: now)
        XCTAssertEqual(model.snapshot?.weeklyPercent, 15)
        XCTAssertEqual(model.snapshot?.weeklyReset, "5d 3h")
        XCTAssertEqual(model.snapshot?.sparkPercent, "88%")
    }

    private func makeForecastSnapshot(
        status: ForecastStatus = .estimated,
        consumed: Double? = 15,
        sustainable: Double? = 4,
        paceDiff: Double? = nil,
        depletionHours: Int = 27,
        observedPoint: Double = 15,
        forecastPoint: Double = 10,
        sustainablePoint: Double = 12
    ) -> DashboardSnapshot {
        let weekly = RateLimit(
            kind: .weekly,
            limitId: "codex",
            remainingPercent: 15,
            resetsAt: now.addingTimeInterval((5 * 24 + 3) * 3600),
            observedAt: now
        )

        let spark = RateLimit(
            kind: .spark,
            limitId: "codex_bengalfox",
            remainingPercent: 88,
            resetsAt: now.addingTimeInterval((5 * 24 + 3) * 3600),
            observedAt: now
        )

        let chart = ChartSeries(
            observed: [ChartPoint(at: now, remainingPercent: observedPoint)],
            forecast: [
                ForecastPoint(
                    at: now.addingTimeInterval(6 * 3600),
                    remainingPercent: forecastPoint,
                    uncertainty: ForecastRange(low: forecastPoint - 2, high: forecastPoint + 2)
                )
            ],
            sustainable: [ChartPoint(at: now.addingTimeInterval(9 * 3600), remainingPercent: sustainablePoint)]
        )

        return DashboardSnapshot(
            quota: QuotaSnapshot(
                weekly: weekly,
                spark: spark,
                other: [],
                freshness: .stale
            ),
            forecast: ForecastReport(
                status: status,
                confidence: status == .collectingHistory ? .collecting : .low,
                consumedPerDay: consumed,
                sustainablePerDay: sustainable,
                paceDifference: paceDiff,
                estimatedDepletionAt: now.addingTimeInterval(TimeInterval(depletionHours * 3600)),
                rateRange: ForecastRange(low: 10, high: 14),
                chart: chart
            )
        )
    }
}

private extension Array where Element == PopoverMetric {
    subscript(safe index: Int) -> PopoverMetric? {
        indices.contains(index) ? self[index] : nil
    }
}
