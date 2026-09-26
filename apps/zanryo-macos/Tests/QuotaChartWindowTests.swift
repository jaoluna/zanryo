import AppKit
import SwiftUI
import XCTest
@testable import Zanryo

final class QuotaChartWindowTests: XCTestCase {
    func testFilterAvailabilityUsesActualWindowsAndFallsBack() {
        let s = fixture()
        XCTAssertEqual(QuotaChartWindow.available(fiveHour: s.fiveHour, weekly: s.weekly), [.fiveHour, .weekly])
        XCTAssertEqual(QuotaChartWindow.available(fiveHour: nil, weekly: s.weekly), [.weekly])
        XCTAssertEqual(QuotaChartWindow.available(fiveHour: s.fiveHour, weekly: nil), [.fiveHour])
        XCTAssertEqual(QuotaChartWindow.weekly.resolved(in: [.fiveHour]), .fiveHour)
        XCTAssertEqual(QuotaChartWindow.fiveHour.resolved(in: [.weekly]), .weekly)
    }

    func testFiveHourSelectionChangesDataDomainUnitsAndMetricsTogether() throws {
        let now = Date()
        let s = fixture(now: now)
        let five = WeeklyOutlookModel.make(snapshot: s, hasError: false, now: now, window: .fiveHour)
        let week = WeeklyOutlookModel.make(snapshot: s, hasError: false, now: now)
        XCTAssertEqual(five.domain, s.fiveHour!.resetsAt.addingTimeInterval(-18000)...s.fiveHour!.resetsAt)
        XCTAssertEqual(five.historySeries.map(\.remainingPercent), [80, 70, 60])
        XCTAssertEqual(five.pace, "20.0 pp/hour")
        XCTAssertEqual(five.rows.first { $0.label == "Available per hour" }?.value, "30.0 pp/hour")
        XCTAssertEqual(five.rows.first { $0.label == "At 5h reset" }?.value, "20.0% remaining")
        XCTAssertEqual(week.historySeries.map(\.remainingPercent), [86, 80, 74])
        XCTAssertFalse(five.rows.contains { $0.label.contains("weekly") || $0.label.contains("day") })
        let timeline = WeeklyChartTimeline(series: five.series, reset: s.fiveHour?.resetsAt, window: .fiveHour)
        XCTAssertEqual(timeline.domain, five.domain)
        XCTAssertTrue(timeline.accessibilityLabel(provider: "Claude").contains("five-hour remaining quota"))
        let chart = ForecastChartView(series: five.series, accessibilityLabel: "test", displayDomain: five.domain)
        XCTAssertEqual(chart.timelineAxisDates.count, 6)
        XCTAssertEqual(chart.timelineAxisDates.last, s.fiveHour?.resetsAt)
    }

    func testDepletionBeyondSelectedResetIsNotShownAsCurrentCycleExhaustion() throws {
        let now = Date()
        let s = fixture(now: now)
        let report = try XCTUnwrap(s.fiveHourForecast)
        let later = ForecastReport(status: report.status, confidence: report.confidence,
            consumedPerDay: report.consumedPerDay, sustainablePerDay: report.sustainablePerDay,
            paceDifference: report.paceDifference,
            estimatedDepletionAt: s.fiveHour!.resetsAt.addingTimeInterval(3600),
            rateRange: report.rateRange, chart: report.chart)
        let snapshot = ClaudeUsageSnapshot(provider: .claude, fiveHour: s.fiveHour, weekly: s.weekly,
            freshness: .fresh, weeklyForecast: s.weeklyForecast, fiveHourForecast: later)
        let model = WeeklyOutlookModel.make(snapshot: snapshot, hasError: false, now: now, window: .fiveHour)
        XCTAssertEqual(model.rows.first?.value, "Not before reset")
        XCTAssertTrue(model.hasProjection)
        let weeklyReport = try XCTUnwrap(s.weeklyForecast)
        let weeklyLater = ForecastReport(status: weeklyReport.status, confidence: weeklyReport.confidence,
            consumedPerDay: weeklyReport.consumedPerDay, sustainablePerDay: weeklyReport.sustainablePerDay,
            paceDifference: weeklyReport.paceDifference,
            estimatedDepletionAt: s.weekly!.resetsAt.addingTimeInterval(3600),
            rateRange: weeklyReport.rateRange, chart: weeklyReport.chart)
        let weeklySnapshot = ClaudeUsageSnapshot(provider: .claude, fiveHour: s.fiveHour, weekly: s.weekly,
            freshness: .fresh, weeklyForecast: weeklyLater, fiveHourForecast: s.fiveHourForecast)
        let weeklyModel = WeeklyOutlookModel.make(snapshot: weeklySnapshot, hasError: false, now: now)
        XCTAssertEqual(weeklyModel.rows.first?.value, "Not before reset")
        XCTAssertTrue(weeklyModel.hasProjection)
    }

    func testExpiredFiveHourDoesNotPoisonFreshWeeklyForecast() {
        let now = Date()
        let original = fixture(now: now)
        let expired = RateLimit(kind: .fiveHour, limitId: "primary", remainingPercent: 0,
                                resetsAt: now, observedAt: now.addingTimeInterval(-300))
        let s = ClaudeUsageSnapshot(provider: .claude, fiveHour: expired, weekly: original.weekly,
            freshness: .fresh, weeklyForecast: original.weeklyForecast, fiveHourForecast: original.fiveHourForecast)
        XCTAssertTrue(WeeklyOutlookModel.make(snapshot: s, hasError: false, now: now).hasProjection)
        let five = WeeklyOutlookModel.make(snapshot: s, hasError: false, now: now, window: .fiveHour)
        XCTAssertFalse(five.hasProjection)
        XCTAssertTrue(five.isStale)
        XCTAssertEqual(five.pace, "Refresh needed")
    }

    func testStaleAndMissingReportsNeverReuseWeeklyHistoryForFiveHour() {
        let now = Date()
        let s = fixture(now: now)
        let legacy = ClaudeUsageSnapshot(provider: .claude, fiveHour: s.fiveHour, weekly: s.weekly,
            freshness: .fresh, weeklyForecast: s.weeklyForecast)
        let first = WeeklyOutlookModel.make(snapshot: legacy, hasError: false, now: now, window: .fiveHour)
        XCTAssertEqual(first.historySeries.map(\.remainingPercent), [60])
        XCTAssertFalse(first.hasProjection)
        let stale = WeeklyOutlookModel.make(snapshot: s, hasError: true, now: now, window: .fiveHour)
        XCTAssertFalse(stale.hasProjection)
        XCTAssertEqual(stale.historySeries.map(\.remainingPercent), [80, 70, 60])
        XCTAssertEqual(stale.series.filter { $0.kind == .sustainable }.map(\.remainingPercent), [100, 0])
    }

    @MainActor
    func testBothFilterPositionsRenderNativelyForBothProviders() async throws {
        let now = Date()
        let s = fixture(now: now)
        for provider in ["Claude", "Codex"] {
            for selected in QuotaChartWindow.allCases {
                let model = WeeklyOutlookModel.make(snapshot: s, hasError: false, now: now, window: selected)
                let limit = selected == .fiveHour ? s.fiveHour : s.weekly
                let view = VStack(spacing: 0) {
                    WeeklyChartView(timeline: .init(series: model.series, reset: limit?.resetsAt, window: selected),
                        pace: model.pace, accent: provider == "Claude" ? PopoverColor.claudeAccent : PopoverColor.accent,
                        provider: provider, availableWindows: [.fiveHour, .weekly], selection: .constant(selected))
                    OutlookMetricsView(rows: model.rows, explanation: model.explanation)
                }.frame(width: 390).background(PopoverColor.background).foregroundStyle(PopoverColor.foreground)
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(x: 0, y: 0, width: 390, height: 465)
                host.appearance = NSAppearance(named: .darkAqua)
                let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.contentView = host
                try await Task.sleep(for: .milliseconds(50))
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let attachment = XCTAttachment(data: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])), uniformTypeIdentifier: "public.png")
                attachment.name = "window-filter-\(provider)-\(selected.rawValue)"
                attachment.lifetime = .keepAlways
                add(attachment)
                window.contentView = nil
            }
        }
    }

    private func fixture(now: Date = Date()) -> ClaudeUsageSnapshot {
        let week = ClaudeDashboardFixture.snapshot(now: now)
        let reset = now.addingTimeInterval(7200)
        return .init(provider: .claude,
            fiveHour: .init(kind: .fiveHour, limitId: "primary", remainingPercent: 60, resetsAt: reset, observedAt: now),
            weekly: week.weekly, freshness: .fresh, weeklyForecast: week.weeklyForecast,
            fiveHourForecast: .init(status: .estimated, confidence: .low, consumedPerDay: 480,
                sustainablePerDay: 720, paceDifference: -240, estimatedDepletionAt: nil, rateRange: nil,
                chart: .init(observed: [.init(at: now.addingTimeInterval(-3600), remainingPercent: 80),
                                       .init(at: now.addingTimeInterval(-1800), remainingPercent: 70),
                                       .init(at: now, remainingPercent: 60)],
                    forecast: [.init(at: now, remainingPercent: 60, uncertainty: .init(low: 60, high: 60)),
                               .init(at: reset, remainingPercent: 20, uncertainty: .init(low: 10, high: 30))],
                    sustainable: [])))
    }
}
