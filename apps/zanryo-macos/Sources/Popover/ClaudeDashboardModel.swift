import Foundation

struct ClaudeDashboardModel {
    let series: [PopoverForecastPoint]
    let domain: ClosedRange<Date>?
    let pace: String
    let rows: [PopoverMetric]
    let explanation: String
    let isStale: Bool
    let hasProjection: Bool

    static func make(snapshot: ClaudeUsageSnapshot?, hasError: Bool, now: Date = Date()) -> Self {
        let stale = snapshot.map { $0.isStale(at: now) || hasError } ?? false
        guard let weekly = snapshot?.weekly else {
            return Self(series: [], domain: nil, pace: "Unavailable", rows: [],
                        explanation: "Weekly history will appear when Claude provides its weekly limit.",
                        isStale: stale, hasProjection: false)
        }
        let report = snapshot?.weeklyForecast
        // Older bridges can provide the current real reading without history.
        let observed = report?.chart.observed ?? [ChartPoint(at: weekly.observedAt, remainingPercent: weekly.remainingPercent)]
        let estimated = !stale && report?.status == .estimated
        var series = observed.map {
            PopoverForecastPoint(kind: .observed, at: $0.at, remainingPercent: $0.remainingPercent,
                                 lowUncertainty: nil, highUncertainty: nil)
        }
        if estimated, let chart = report?.chart {
            series += chart.forecast.map {
                PopoverForecastPoint(kind: .forecast, at: $0.at, remainingPercent: $0.remainingPercent,
                                     lowUncertainty: $0.uncertainty.low, highUncertainty: $0.uncertainty.high)
            }
            series += chart.sustainable.map {
                PopoverForecastPoint(kind: .sustainable, at: $0.at, remainingPercent: $0.remainingPercent,
                                     lowUncertainty: nil, highUncertainty: nil)
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
                ? "Orange: observed. Red: estimated. Gray: budget pace. Rates are percentage points per day, not the 5-hour limit."
                : "Observed readings only. Forecast needs at least 3 readings spanning 30 minutes in this weekly cycle."
        return Self(series: series, domain: weekly.resetsAt.addingTimeInterval(-7 * 86400)...weekly.resetsAt,
                    pace: pace, rows: rows, explanation: explanation, isStale: stale, hasProjection: estimated)
    }

    private static func rate(_ value: Double?) -> String {
        value.map { String(format: "%.1f pp/day", $0) } ?? "Unavailable"
    }
}
