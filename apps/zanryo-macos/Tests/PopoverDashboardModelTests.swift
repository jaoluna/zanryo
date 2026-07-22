import XCTest
@testable import Zanryo

final class PopoverDashboardModelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_774_171_200)

    func testCollectingHistorySnapshotShowsForecastStatusAndObservedOnlyCopy() {
        let model = PopoverDashboardModel.make(
            from: makeForecastSnapshot(status: .collectingHistory),
            now: now
        )

        XCTAssertEqual(model.headerText, "Cached data")
        XCTAssertEqual(model.forecastPaceText, "Collecting history")
        XCTAssertEqual(model.forecastTitle, "Collecting history")
        XCTAssertEqual(model.forecastConfidence, "Collecting")
        XCTAssertFalse(model.hasForecastProjection)
        XCTAssertEqual(model.forecastMetrics, [PopoverMetric(label: "Observed", value: "Collecting history")])
        XCTAssertEqual(
            model.decisionRows,
            [
                PopoverMetric(label: "Estimated depletion", value: "Collecting history"),
                PopoverMetric(label: "Projected at reset", value: "Collecting history"),
                PopoverMetric(label: "Allowed pace", value: "Collecting history"),
                PopoverMetric(label: "Forecast confidence", value: "Collecting")
            ]
        )
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
        XCTAssertEqual(model.forecastMetrics.first?.label, "Current pace")
        XCTAssertEqual(model.forecastMetrics.first?.value, "12.5%/day · 2.6%/5h")
        XCTAssertEqual(model.forecastMetrics[safe: 1]?.label, "Allowed pace")
        XCTAssertEqual(model.forecastMetrics[safe: 1]?.value, "10.2%/day · 2.1%/5h")
        XCTAssertTrue(model.hasForecastProjection)
        XCTAssertTrue(model.forecastSeries.contains(where: { $0.kind == .observed }))
        XCTAssertTrue(model.forecastSeries.contains(where: { $0.kind == .forecast }))
        XCTAssertTrue(model.forecastSeries.contains(where: { $0.kind == .sustainable }))
    }

    func testFinalPanelModelExposesQuotaForecastDecisionRowsAndSingleRefreshAction() {
        let model = PopoverDashboardModel.make(
            from: makeForecastSnapshot(status: .estimated, consumed: 12.5, paceDiff: 2.3),
            now: now
        )

        XCTAssertEqual(model.weekly?.percentage, 15)
        XCTAssertEqual(model.spark.percentage, 88)
        XCTAssertEqual(model.forecastTitle, "Estimated forecast")
        XCTAssertEqual(model.forecastPaceText, "Current pace\n12.5%/day · 2.6%/5h")
        XCTAssertEqual(model.decisionRows.map(\.label), [
            "Estimated depletion", "Projected at reset", "Allowed pace", "Forecast confidence"
        ])
        XCTAssertEqual(model.footerActionTitle, "Refresh")
        XCTAssertFalse(model.footerText.contains("Manual refresh"))
    }

    func testPresentationModelProvidesVoiceOverDescriptionsAndTextualStates() {
        let stale = PopoverDashboardModel.make(
            from: makeForecastSnapshot(status: .estimated, freshness: .stale, sparkResetHours: 2),
            now: now
        )
        let loading = PopoverDashboardModel.make(from: nil, now: now)

        XCTAssertEqual(stale.wordmarkAccessibilityLabel, "Zanryo")
        XCTAssertEqual(
            stale.weekly?.accessibilityDescription,
            "Weekly quota: 15 percent remaining. Resets in 5 days and 3 hours."
        )
        XCTAssertEqual(
            stale.spark.accessibilityDescription,
            "Spark quota: 88 percent remaining. Resets in 2 hours."
        )
        XCTAssertEqual(stale.footerText, "Cached data — may be out of date")
        XCTAssertEqual(loading.footerText, "Loading Codex quota data")
    }

    func testPresentationModelCentralizesForecastAndChartAccessibilityLabels() {
        let model = PopoverDashboardModel.make(
            from: makeForecastSnapshot(status: .estimated),
            now: now
        )

        XCTAssertEqual(model.forecastSectionAccessibilityLabel, "Weekly forecast.")
        XCTAssertEqual(
            model.chartAccessibilityLabel,
            "Quota chart. Yellow is observed remaining quota, red is the current-pace forecast, and gray is the weekly one hundred percent to zero percent budget pace."
        )
        XCTAssertEqual(model.loadingWeeklyAccessibilityLabel, "Weekly quota is loading")
    }

    func testPresentationModelPreservesRefreshErrorAccessibilitySemantics() {
        let model = PopoverDashboardModel.make(
            from: makeForecastSnapshot(status: .estimated),
            now: now
        )

        XCTAssertEqual(
            model.refreshErrorAccessibilityLabel(for: "Bridge is unavailable"),
            "Refresh error: Bridge is unavailable"
        )
    }

    func testFreshDashboardUsesQuotaDisplaysAndSparkOwnReset() {
        let model = PopoverDashboardModel.make(
            from: makeForecastSnapshot(status: .estimated, freshness: .fresh, sparkResetHours: 2),
            now: now
        )

        XCTAssertEqual(model.headerText, "Updated now")
        XCTAssertEqual(model.weekly?.percentage, 15)
        XCTAssertEqual(model.weekly?.reset, "5d 3h")
        XCTAssertEqual(model.weekly?.resetSpoken, "5 days and 3 hours")
        XCTAssertEqual(model.spark.percentage, 88)
        XCTAssertEqual(model.spark.reset, "2h")
        XCTAssertEqual(model.spark.resetSpoken, "2 hours")
    }

    func testUnavailableSparkRetainsAQuotaColumnWithResetFallback() {
        let model = PopoverDashboardModel.make(
            from: makeForecastSnapshot(status: .estimated, includeSpark: false),
            now: now
        )

        XCTAssertFalse(model.spark.isAvailable)
        XCTAssertEqual(model.spark.valueText, "Unavailable")
        XCTAssertEqual(model.spark.reset, "Unavailable")
        XCTAssertEqual(
            model.spark.accessibilityDescription,
            "Spark quota unavailable. Reset time unavailable."
        )
    }

    func testRefreshingDashboardUsesModelUpdatingStateAndAccessibilityText() {
        let model = PopoverDashboardModel.make(
            from: makeForecastSnapshot(status: .estimated, freshness: .stale),
            now: now,
            isRefreshing: true
        )

        XCTAssertEqual(model.headerText, "Updating")
        XCTAssertEqual(model.headerAccessibilityText, "Updating Codex quota data")
        XCTAssertEqual(model.footerText, "Updating Codex quota data")
    }

    func testRefreshingEmptyDashboardUsesUpdatingPresentation() {
        let model = PopoverDashboardModel.make(
            from: nil,
            now: now,
            isRefreshing: true
        )

        XCTAssertEqual(model.headerText, "Updating")
        XCTAssertEqual(model.headerAccessibilityText, "Updating Codex quota data")
        XCTAssertEqual(model.footerText, "Updating Codex quota data")
    }

    func testLoadingDashboardRetainsAllDecisionRowsWithClearValues() {
        let model = PopoverDashboardModel.make(from: nil, now: now)

        XCTAssertEqual(
            model.decisionRows,
            [
                PopoverMetric(label: "Estimated depletion", value: "Loading"),
                PopoverMetric(label: "Projected at reset", value: "Loading"),
                PopoverMetric(label: "Allowed pace", value: "Loading"),
                PopoverMetric(label: "Forecast confidence", value: "Loading")
            ]
        )
        XCTAssertEqual(model.account.billingStatus, "Status unavailable")
    }

    func testDashboardUsesPlanAndBillingPresentationBoundary() {
        let model = PopoverDashboardModel.make(
            from: makeForecastSnapshot(status: .estimated, planType: .plus),
            now: now
        )

        XCTAssertEqual(model.account.plan, "Plus")
        XCTAssertEqual(model.account.billingStatus, "Status unavailable")
    }

    func testAccountPresentationMapsProLiteAndUnknownSafely() {
        let proLite = PopoverDashboardModel.make(
            from: makeForecastSnapshot(status: .estimated, planType: .proLite),
            now: now
        )
        let unknown = PopoverDashboardModel.make(
            from: makeForecastSnapshot(status: .estimated, planType: .unknown),
            now: now
        )

        XCTAssertEqual(proLite.account.plan, "Pro Lite")
        XCTAssertEqual(unknown.account.plan, "Unknown")
    }

    func testEstimatedDepletionUsesAnAbsoluteLocalDateAndPositivePaceWording() {
        let depletion = now.addingTimeInterval(36 * 3_600)
        let model = PopoverDashboardModel.make(
            from: makeForecastSnapshot(
                status: .estimated,
                paceDiff: 2.3,
                depletionAt: depletion
            ),
            now: now
        )

        XCTAssertEqual(
            model.decisionRows,
            [
                PopoverMetric(label: "Estimated depletion", value: localAbbreviatedDate(depletion)),
                PopoverMetric(label: "Projected at reset", value: "10% left"),
                PopoverMetric(label: "Allowed pace", value: "4%/day · 0.8%/5h"),
                PopoverMetric(label: "Forecast confidence", value: "Low")
            ]
        )
    }

    func testEveryEstimatedDepletionPresentationUsesAnAbsoluteLocalDate() {
        let depletion = now.addingTimeInterval(48 * 3_600)
        let model = PopoverDashboardModel.make(
            from: makeForecastSnapshot(status: .estimated, depletionAt: depletion),
            now: now
        )

        let metric = model.forecastMetrics.first { $0.label == "Estimated depletion" }
        let decision = model.decisionRows.first { $0.label == "Estimated depletion" }

        XCTAssertEqual(metric?.value, localAbbreviatedDate(depletion))
        XCTAssertEqual(decision?.value, localAbbreviatedDate(depletion))
        XCTAssertNotEqual(metric?.value, "2d")
        XCTAssertNotEqual(decision?.value, "2d")
    }

    func testDecisionRowsShowSafePaceTargetInsteadOfGapWording() {
        let model = PopoverDashboardModel.make(
            from: makeForecastSnapshot(status: .estimated, sustainable: 8.4, paceDiff: -1.2),
            now: now
        )

        XCTAssertEqual(
            model.decisionRows.first(where: { $0.label == "Allowed pace" })?.value,
            "8.4%/day · 1.8%/5h"
        )
    }

    func testObservedPaceAlsoShowsEquivalentFiveHourPaceWithoutClaimingAWindow() {
        let model = PopoverDashboardModel.make(
            from: makeForecastSnapshot(status: .estimated, consumed: 24, sustainable: 12),
            now: now
        )

        XCTAssertEqual(model.forecastPaceText, "Current pace\n24%/day · 5%/5h")
        XCTAssertEqual(model.forecastMetrics.first?.value, "24%/day · 5%/5h")
        XCTAssertEqual(model.forecastMetrics[safe: 1]?.value, "12%/day · 2.5%/5h")
    }

    private func makeForecastSnapshot(
        status: ForecastStatus = .estimated,
        consumed: Double? = 15,
        sustainable: Double? = 4,
        paceDiff: Double? = nil,
        depletionHours: Int = 27,
        depletionAt: Date? = nil,
        observedPoint: Double = 15,
        forecastPoint: Double = 10,
        sustainablePoint: Double = 12,
        freshness: Freshness = .stale,
        includeSpark: Bool = true,
        sparkResetHours: Int = 5 * 24 + 3,
        planType: PlanType? = nil
    ) -> DashboardSnapshot {
        let weekly = RateLimit(
            kind: .weekly,
            limitId: "codex",
            remainingPercent: 15,
            resetsAt: now.addingTimeInterval((5 * 24 + 3) * 3600),
            observedAt: now
        )

        let spark = includeSpark
            ? RateLimit(
                kind: .spark,
                limitId: "codex_bengalfox",
                remainingPercent: 88,
                resetsAt: now.addingTimeInterval(TimeInterval(sparkResetHours * 3_600)),
                observedAt: now
            )
            : nil

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
                freshness: freshness
            ),
            forecast: ForecastReport(
                status: status,
                confidence: status == .collectingHistory ? .collecting : .low,
                consumedPerDay: consumed,
                sustainablePerDay: sustainable,
                paceDifference: paceDiff,
                estimatedDepletionAt: depletionAt ?? now.addingTimeInterval(TimeInterval(depletionHours * 3600)),
                rateRange: ForecastRange(low: 10, high: 14),
                chart: chart
            ),
            account: planType.map { AccountContext(planType: $0, observedAt: now) }
        )
    }

    private func localAbbreviatedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "EEE, MMM d, h:mm a"
        return formatter.string(from: date)
    }
}

private extension Array where Element == PopoverMetric {
    subscript(safe index: Int) -> PopoverMetric? {
        indices.contains(index) ? self[index] : nil
    }
}
