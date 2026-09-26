import Foundation

typealias ClaudeDashboardModel = WeeklyOutlookModel

struct WeeklyOutlookModel {
    let series: [PopoverForecastPoint]
    let domain: ClosedRange<Date>?
    let pace: String
    let rows: [PopoverMetric]
    let explanation: String
    let isStale: Bool
    let hasProjection: Bool

    var historySeries: [PopoverForecastPoint] { series.filter { $0.kind == .observed } }

    var projectionSeries: [PopoverForecastPoint] {
        // The independent cycle guide is not a forecast.
        series.filter { $0.kind == .forecast }
    }

    var historyDomain: ClosedRange<Date>? {
        guard let first = historySeries.first?.at, let last = historySeries.last?.at else { return nil }
        return min(first, last.addingTimeInterval(-3600))...last
    }

    var projectionDomain: ClosedRange<Date>? {
        guard let start = projectionSeries.first?.at, let end = domain?.upperBound, start < end else { return nil }
        return start...end
    }

    var historyCaption: String {
        guard let first = historySeries.first, let last = historySeries.last else { return "No weekly readings yet." }
        if first.at == last.at { return "First reading. No earlier history is assumed." }
        let span = ResetDuration(from: first.at, to: last.at).compact
        let change = first.remainingPercent - last.remainingPercent
        if historySeries.allSatisfy({ abs($0.remainingPercent - first.remainingPercent) < 0.01 }) {
            return "\(span) recorded · no change observed"
        }
        return "\(span) recorded · \(String(format: "%.1f", abs(change))) pp \(change > 0 ? "decrease" : "increase")"
    }

    static func make(snapshot: ClaudeUsageSnapshot?, hasError: Bool, now: Date = Date(), window: QuotaChartWindow = .weekly) -> Self {
        let limit = window == .fiveHour ? snapshot?.fiveHour : snapshot?.weekly
        let report = window == .fiveHour ? snapshot?.fiveHourForecast : snapshot?.weeklyForecast
        let stale = hasError || snapshot?.freshness == .stale || limit.map {
            now.timeIntervalSince($0.observedAt) > 360 || $0.observedAt > now || $0.resetsAt <= now
        } == true
        return make(weekly: limit, report: report, isStale: stale, window: window)
    }

    static func make(weekly: RateLimit?, report: ForecastReport?, isStale stale: Bool, window: QuotaChartWindow = .weekly) -> Self {
        guard let weekly else {
            return Self(series: [], domain: nil, pace: "Unavailable", rows: [],
                        explanation: "\(window.title) history will appear when the provider supplies this limit.",
                        isStale: stale, hasProjection: false)
        }
        // Older bridges can provide the current real reading without history.
        let saved = report?.chart.observed ?? []
        let start = weekly.resetsAt.addingTimeInterval(-window.duration)
        let observed = (saved.isEmpty ? [ChartPoint(at: weekly.observedAt, remainingPercent: weekly.remainingPercent)] : saved)
            .filter { window == .weekly || ($0.at >= start && $0.at < weekly.resetsAt) }
            .sorted { $0.at < $1.at }
        let estimated = !stale && report?.status == .estimated && report?.chart.forecast.isEmpty == false
        var series = observed.map {
            PopoverForecastPoint(kind: .observed, at: $0.at, remainingPercent: $0.remainingPercent,
                                 lowUncertainty: nil, highUncertainty: nil)
        }
        if estimated, let chart = report?.chart {
            series += chart.forecast.map {
                PopoverForecastPoint(kind: .forecast, at: $0.at, remainingPercent: $0.remainingPercent,
                                     lowUncertainty: $0.uncertainty.low, highUncertainty: $0.uncertainty.high)
            }
        }
        // Fixed reference, NOT a reading or prediction. It never follows the
        // current balance and remains meaningful without sufficient history.
        series += [
            PopoverForecastPoint(kind: .sustainable, at: start,
                                 remainingPercent: 100, lowUncertainty: nil, highUncertainty: nil),
            PopoverForecastPoint(kind: .sustainable, at: weekly.resetsAt, remainingPercent: 0,
                                 lowUncertainty: nil, highUncertainty: nil),
        ]
        let pending = stale ? "Refresh needed" : "Collecting history"
        let pace = estimated ? currentPace(report?.consumedPerDay, window: window) : pending
        let depletion: String
        if estimated, let date = report?.estimatedDepletionAt {
            depletion = date <= weekly.resetsAt
                ? date.formatted(date: .abbreviated, time: .shortened)
                : "Not before reset"
        } else if estimated, report?.consumedPerDay == 0 {
            depletion = "No decline observed"
        } else {
            depletion = estimated ? "Not projected" : pending
        }
        let projected = estimated ? report?.chart.forecast.last?.remainingPercent : nil
        let confidence = estimated ? report?.confidence.rawValue.capitalized ?? "Unavailable" : pending
        let rows = [
            PopoverMetric(label: "Estimated depletion", value: depletion),
            PopoverMetric(label: window == .weekly ? "At weekly reset" : "At 5h reset", value: projected.map { String(format: "%.1f%% remaining", $0) } ?? pending),
            PopoverMetric(label: window == .weekly ? "Available per day" : "Available per hour", value: estimated ? rate(report?.sustainablePerDay, window: window) : pending),
            // The chart compresses flat stretches; chart points are not a sample count.
            PopoverMetric(label: "Confidence", value: confidence),
        ]
        let explanation = stale
            ? "Saved observations. Refresh to update the estimate."
            : estimated
                ? "Projection assumes the recorded pace continues. \(report?.confidence == .low ? "Low confidence: limited history." : "It is not a guaranteed balance.")"
                : "Forecast needs 3 readings spanning 30 minutes. The gray line is the ideal cycle, not recorded usage."
        return Self(series: series, domain: start...weekly.resetsAt,
                    pace: pace, rows: rows, explanation: explanation, isStale: stale, hasProjection: estimated)
    }

    private static func rate(_ value: Double?, window: QuotaChartWindow) -> String {
        value.map { window == .weekly ? String(format: "%.1f pp/day", $0) : String(format: "%.1f pp/hour", $0 / 24) } ?? "Unavailable"
    }

    private static func currentPace(_ value: Double?, window: QuotaChartWindow) -> String {
        guard let value else { return "Unavailable" }
        if window == .fiveHour { return String(format: "%.1f pp/hour", value / 24) }
        // Five-hour equivalent of the WEEKLY pace, never the separate 5h quota.
        return String(format: "%.1f pp/day · %.1f pp/5h", value, value * 5 / 24)
    }
}
