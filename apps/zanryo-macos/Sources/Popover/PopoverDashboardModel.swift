import Foundation

enum ForecastSeriesKind: String, CaseIterable, Sendable {
    case observed
    case forecast
    case sustainable
}

struct PopoverForecastPoint: Equatable, Sendable {
    let kind: ForecastSeriesKind
    let at: Date
    let remainingPercent: Double
    let lowUncertainty: Double?
    let highUncertainty: Double?
}

struct PopoverMetric: Equatable, Sendable {
    let label: String
    let value: String
}

struct PopoverDashboardModel: Equatable, Sendable {
    struct QuotaDisplay: Equatable, Sendable {
        let percentage: Int
        let reset: String
        let resetSpoken: String
    }

    struct AccountDisplay: Equatable, Sendable {
        let plan: String
        let billingStatus: String
    }

    struct Snapshot: Equatable, Sendable {
        let weeklyPercent: Int
        let weeklyReset: String
        let weeklyResetSpoken: String
        let isFresh: Bool
        let sparkPercent: String?
    }

    let snapshot: Snapshot?
    let headerText: String
    let weekly: QuotaDisplay?
    let spark: QuotaDisplay?
    let account: AccountDisplay
    let forecastTitle: String
    let forecastConfidence: String
    let forecastMetrics: [PopoverMetric]
    let decisionRows: [PopoverMetric]
    let forecastSeries: [PopoverForecastPoint]
    let hasForecastProjection: Bool
    let apiSpendText: String
    let themeText: String
    let isLoading: Bool

    static func make(from dashboard: DashboardSnapshot?, now: Date = Date()) -> PopoverDashboardModel {
        guard let dashboard else {
            return PopoverDashboardModel(
                snapshot: nil,
                headerText: "Loading",
                weekly: nil,
                spark: nil,
                account: AccountDisplay(plan: "Unknown", billingStatus: "Status unavailable"),
                forecastTitle: "Loading",
                forecastConfidence: "Collecting",
                forecastMetrics: [],
                decisionRows: [],
                forecastSeries: [],
                hasForecastProjection: false,
                apiSpendText: "Not configured",
                themeText: "Coming soon",
                isLoading: true
            )
        }

        let weeklyReset = ResetDuration(formatFrom: now, to: dashboard.quota.weekly.resetsAt)
        let weekly = QuotaDisplay(
            percentage: Int(dashboard.quota.weekly.remainingPercent.rounded()),
            reset: weeklyReset.compact,
            resetSpoken: weeklyReset.spoken
        )
        let spark = dashboard.quota.spark.map { limit in
            let reset = ResetDuration(formatFrom: now, to: limit.resetsAt)
            return QuotaDisplay(
                percentage: Int(limit.remainingPercent.rounded()),
                reset: reset.compact,
                resetSpoken: reset.spoken
            )
        }
        let snapshot = Snapshot(
            weeklyPercent: weekly.percentage,
            weeklyReset: weekly.reset,
            weeklyResetSpoken: weekly.resetSpoken,
            isFresh: dashboard.quota.freshness == .fresh,
            sparkPercent: spark.map { "\($0.percentage)%" }
        )

        let hasForecastProjection = dashboard.forecast.status == .estimated
        let forecastTitle = dashboard.forecast.status == .collectingHistory
            ? "Collecting history"
            : "Estimated forecast"

        var metrics: [PopoverMetric] = []
        if hasForecastProjection {
            if let consumedPerDay = dashboard.forecast.consumedPerDay {
                metrics.append(
                    PopoverMetric(
                        label: "Observed pace",
                        value: "\(formatPercent(consumedPerDay))/day"
                    )
                )
            }

            if let sustainablePerDay = dashboard.forecast.sustainablePerDay {
                metrics.append(
                    PopoverMetric(
                        label: "Sustainable pace",
                        value: "\(formatPercent(sustainablePerDay))/day"
                    )
                )
            }

            if let paceDifference = dashboard.forecast.paceDifference {
                let sign = paceDifference >= 0 ? "+" : ""
                metrics.append(
                    PopoverMetric(
                        label: "Pace difference",
                        value: "\(sign)\(formatPercent(paceDifference))/day"
                    )
                )
            }

            if let depletion = dashboard.forecast.estimatedDepletionAt {
                metrics.append(
                    PopoverMetric(
                        label: "Estimated depletion",
                        value: formatAbsoluteDate(depletion)
                    )
                )
            }

            if let confidence = dashboard.forecast.rateRange {
                metrics.append(
                    PopoverMetric(
                        label: "Uncertainty",
                        value: "\(formatPercent(confidence.low))–\(formatPercent(confidence.high))/day"
                    )
                )
            }

            if metrics.isEmpty {
                metrics.append(PopoverMetric(label: "Forecast", value: "Estimating…"))
            }
        } else {
            metrics.append(PopoverMetric(label: "Observed", value: "Collecting history"))
        }

        let decisionRows = makeDecisionRows(
            forecast: dashboard.forecast,
            account: dashboard.account
        )
        let series = makeSeries(dashboard.forecast.chart)

        return PopoverDashboardModel(
            snapshot: snapshot,
            headerText: dashboard.quota.freshness == .fresh ? "Updated now" : "Cached data",
            weekly: weekly,
            spark: spark,
            account: makeAccountDisplay(dashboard.account),
            forecastTitle: forecastTitle,
            forecastConfidence: confidenceLabel(dashboard.forecast.confidence),
            forecastMetrics: metrics,
            decisionRows: decisionRows,
            forecastSeries: series,
            hasForecastProjection: hasForecastProjection,
            apiSpendText: "Not configured",
            themeText: "Coming soon",
            isLoading: false
        )
    }

    private static func makeSeries(_ chart: ChartSeries) -> [PopoverForecastPoint] {
        var points: [PopoverForecastPoint] = []

        points.reserveCapacity(chart.observed.count + chart.forecast.count + chart.sustainable.count)
        points.append(
            contentsOf: chart.observed.sorted { $0.at < $1.at }.map {
                PopoverForecastPoint(
                    kind: .observed,
                    at: $0.at,
                    remainingPercent: clampPercent($0.remainingPercent),
                    lowUncertainty: nil,
                    highUncertainty: nil
                )
            }
        )
        points.append(
            contentsOf: chart.forecast.sorted { $0.at < $1.at }.map {
                PopoverForecastPoint(
                    kind: .forecast,
                    at: $0.at,
                    remainingPercent: clampPercent($0.remainingPercent),
                    lowUncertainty: clampOptional($0.uncertainty.low),
                    highUncertainty: clampOptional($0.uncertainty.high)
                )
            }
        )
        points.append(
            contentsOf: chart.sustainable.sorted { $0.at < $1.at }.map {
                PopoverForecastPoint(
                    kind: .sustainable,
                    at: $0.at,
                    remainingPercent: clampPercent($0.remainingPercent),
                    lowUncertainty: nil,
                    highUncertainty: nil
                )
            }
        )

        return points
    }

    private static func makeAccountDisplay(_ account: AccountContext?) -> AccountDisplay {
        AccountDisplay(
            plan: planLabel(account?.planType ?? .unknown),
            billingStatus: "Status unavailable"
        )
    }

    private static func makeDecisionRows(
        forecast: ForecastReport,
        account: AccountContext?
    ) -> [PopoverMetric] {
        var rows: [PopoverMetric] = []

        if forecast.status == .estimated {
            if let depletion = forecast.estimatedDepletionAt {
                rows.append(
                    PopoverMetric(
                        label: "Estimated depletion",
                        value: formatAbsoluteDate(depletion)
                    )
                )
            }

            if let paceDifference = forecast.paceDifference {
                rows.append(
                    PopoverMetric(
                        label: "Pace vs. budget",
                        value: paceDescription(paceDifference)
                    )
                )
            }
        }

        let account = makeAccountDisplay(account)
        rows.append(PopoverMetric(label: "Plan", value: account.plan))
        rows.append(PopoverMetric(label: "Billing status", value: account.billingStatus))
        return rows
    }

    private static func planLabel(_ planType: PlanType) -> String {
        switch planType {
        case .free:
            "Free"
        case .go:
            "Go"
        case .plus:
            "Plus"
        case .pro:
            "Pro"
        case .proLite:
            "Pro Lite"
        case .team:
            "Team"
        case .business:
            "Business"
        case .enterprise:
            "Enterprise"
        case .edu:
            "Education"
        case .unknown:
            "Unknown"
        }
    }

    private static func formatAbsoluteDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "EEE, MMM d, h:mm a"
        return formatter.string(from: date)
    }

    private static func paceDescription(_ paceDifference: Double) -> String {
        let direction = paceDifference >= 0 ? "over budget" : "under budget"
        return "\(formatPercent(abs(paceDifference)))%/day \(direction)"
    }

    private static func confidenceLabel(_ confidence: ForecastConfidence) -> String {
        switch confidence {
        case .collecting:
            "Collecting"
        case .low:
            "Low"
        case .medium:
            "Medium"
        case .high:
            "High"
        }
    }

    private static func formatPercent(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return String(format: "%.1f", rounded)
    }

    private static func clampPercent(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }

    private static func clampOptional(_ value: Double) -> Double {
        clampPercent(value)
    }
}

private struct ResetDuration {
    let days: Int
    let hours: Int

    init(formatFrom start: Date, to end: Date) {
        guard end > start else {
            days = 0
            hours = 0
            return
        }

        let components = Calendar.current.dateComponents([.day, .hour], from: start, to: end)
        days = max(0, components.day ?? 0)
        hours = max(0, components.hour ?? 0)
    }

    var compact: String {
        if days == 0 {
            return "\(hours)h"
        }

        return "\(days)d \(hours)h"
    }

    var spoken: String {
        if days == 0 {
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }

        let dayUnit = days == 1 ? "day" : "days"
        let hourUnit = hours == 1 ? "hour" : "hours"
        return "\(days) \(dayUnit) and \(hours) \(hourUnit)"
    }
}
