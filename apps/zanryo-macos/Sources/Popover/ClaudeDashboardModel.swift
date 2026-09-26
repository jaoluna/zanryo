import Foundation

enum ClaudeChartMode: String, CaseIterable {
    case history = "History"
    case projection = "Projection"
}

struct ClaudeDashboardModel {
    let series: [PopoverForecastPoint]
    let domain: ClosedRange<Date>?
    let pace: String
    let rows: [PopoverMetric]
    let explanation: String
    let isStale: Bool
    let hasProjection: Bool

    var historySeries: [PopoverForecastPoint] { series.filter { $0.kind == .observed } }

    var projectionSeries: [PopoverForecastPoint] {
        // Don't carry a week of past observations into a forward-looking chart.
        series.filter { $0.kind != .observed }
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

    static func make(snapshot: ClaudeUsageSnapshot?, hasError: Bool, now: Date = Date()) -> Self {
        let stale = snapshot.map { $0.isStale(at: now) || hasError } ?? false
        guard let weekly = snapshot?.weekly else {
            return Self(series: [], domain: nil, pace: "Unavailable", rows: [],
                        explanation: "Weekly history will appear when Claude provides its weekly limit.",
                        isStale: stale, hasProjection: false)
        }
        let report = snapshot?.weeklyForecast
        // Older bridges can provide the current real reading without history.
        let saved = report?.chart.observed ?? []
        let observed = (saved.isEmpty ? [ChartPoint(at: weekly.observedAt, remainingPercent: weekly.remainingPercent)] : saved)
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
            // Allowed pace is a budget from the current estimate, not an invented
            // 100% balance at the start of a partially observed cycle.
            if let current = chart.forecast.first, current.at < weekly.resetsAt {
                series += [
                    PopoverForecastPoint(kind: .sustainable, at: current.at, remainingPercent: current.remainingPercent,
                                         lowUncertainty: nil, highUncertainty: nil),
                    PopoverForecastPoint(kind: .sustainable, at: weekly.resetsAt, remainingPercent: 0,
                                         lowUncertainty: nil, highUncertainty: nil),
                ]
            }
        }
        let pending = stale ? "Refresh needed" : "Collecting history"
        let pace = estimated ? rate(report?.consumedPerDay) : pending
        let depletion: String
        if estimated, let date = report?.estimatedDepletionAt {
            depletion = date.formatted(date: .abbreviated, time: .shortened)
        } else if estimated, report?.consumedPerDay == 0 {
            depletion = "No decline observed"
        } else {
            depletion = estimated ? "Not projected" : pending
        }
        let projected = estimated ? report?.chart.forecast.last?.remainingPercent : nil
        let confidence = estimated ? report?.confidence.rawValue.capitalized ?? "Unavailable" : pending
        let rows = [
            PopoverMetric(label: "Estimated depletion", value: depletion),
            PopoverMetric(label: "At weekly reset", value: projected.map { String(format: "%.1f%% remaining", $0) } ?? pending),
            PopoverMetric(label: "Allowed pace", value: estimated ? rate(report?.sustainablePerDay) : pending),
            // The chart compresses flat stretches; chart points are not a sample count.
            PopoverMetric(label: "Confidence", value: confidence),
        ]
        let explanation = stale
            ? "Saved observations. Refresh to update the estimate."
            : estimated
                ? "Projection assumes the recorded pace continues. \(report?.confidence == .low ? "Low confidence: limited history." : "It is not a guaranteed balance.")"
                : "Observed readings only. Forecast needs at least 3 readings spanning 30 minutes in this weekly cycle."
        return Self(series: series, domain: weekly.resetsAt.addingTimeInterval(-7 * 86400)...weekly.resetsAt,
                    pace: pace, rows: rows, explanation: explanation, isStale: stale, hasProjection: estimated)
    }

    private static func rate(_ value: Double?) -> String {
        value.map { String(format: "%.1f pp/day", $0) } ?? "Unavailable"
    }
}
