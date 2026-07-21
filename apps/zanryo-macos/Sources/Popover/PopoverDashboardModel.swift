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
        let label: String
        let isAvailable: Bool
        let valueText: String
        let percentage: Int
        let reset: String
        let resetSpoken: String
        let accessibilityDescription: String
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
    let wordmarkAccessibilityLabel: String
    let headerText: String
    let headerAccessibilityText: String
    let weekly: QuotaDisplay?
    let spark: QuotaDisplay
    let account: AccountDisplay
    let forecastTitle: String
    let forecastPaceText: String
    let forecastConfidence: String
    let forecastMetrics: [PopoverMetric]
    let decisionRows: [PopoverMetric]
    let forecastSeries: [PopoverForecastPoint]
    let hasForecastProjection: Bool
    let footerText: String
    let footerActionTitle: String
    let isLoading: Bool

    static func make(
        from dashboard: DashboardSnapshot?,
        now: Date = Date(),
        isRefreshing: Bool = false
    ) -> PopoverDashboardModel {
        guard let dashboard else {
            let updateState = makeLoadingState(isRefreshing: isRefreshing)

            return PopoverDashboardModel(
                snapshot: nil,
                wordmarkAccessibilityLabel: "Zanryo",
                headerText: updateState.text,
                headerAccessibilityText: updateState.accessibilityText,
                weekly: nil,
                spark: unavailableSparkDisplay(),
                account: AccountDisplay(plan: "Unknown", billingStatus: "Status unavailable"),
                forecastTitle: "Loading",
                forecastPaceText: "Forecast will appear after quota data loads",
                forecastConfidence: "Collecting",
                forecastMetrics: [],
                decisionRows: loadingDecisionRows(),
                forecastSeries: [],
                hasForecastProjection: false,
                footerText: updateState.footerText,
                footerActionTitle: "Refresh",
                isLoading: true
            )
        }

        let weeklyReset = ResetDuration(formatFrom: now, to: dashboard.quota.weekly.resetsAt)
        let weekly = QuotaDisplay(
            label: "Weekly",
            isAvailable: true,
            valueText: "\(Int(dashboard.quota.weekly.remainingPercent.rounded()))%",
            percentage: Int(dashboard.quota.weekly.remainingPercent.rounded()),
            reset: weeklyReset.compact,
            resetSpoken: weeklyReset.spoken,
            accessibilityDescription: quotaAccessibilityDescription(
                label: "Weekly",
                percentage: Int(dashboard.quota.weekly.remainingPercent.rounded()),
                reset: weeklyReset.spoken
            )
        )
        let spark = dashboard.quota.spark.map { limit in
            let reset = ResetDuration(formatFrom: now, to: limit.resetsAt)
            return QuotaDisplay(
                label: "Spark",
                isAvailable: true,
                valueText: "\(Int(limit.remainingPercent.rounded()))%",
                percentage: Int(limit.remainingPercent.rounded()),
                reset: reset.compact,
                resetSpoken: reset.spoken,
                accessibilityDescription: quotaAccessibilityDescription(
                    label: "Spark",
                    percentage: Int(limit.remainingPercent.rounded()),
                    reset: reset.spoken
                )
            )
        } ?? unavailableSparkDisplay()
        let snapshot = Snapshot(
            weeklyPercent: weekly.percentage,
            weeklyReset: weekly.reset,
            weeklyResetSpoken: weekly.resetSpoken,
            isFresh: dashboard.quota.freshness == .fresh,
            sparkPercent: spark.isAvailable ? spark.valueText : nil
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
        let updateState = makeUpdateState(
            freshness: dashboard.quota.freshness,
            isRefreshing: isRefreshing
        )

        return PopoverDashboardModel(
            snapshot: snapshot,
            wordmarkAccessibilityLabel: "Zanryo",
            headerText: updateState.text,
            headerAccessibilityText: updateState.accessibilityText,
            weekly: weekly,
            spark: spark,
            account: makeAccountDisplay(dashboard.account),
            forecastTitle: forecastTitle,
            forecastPaceText: forecastPaceText(for: dashboard.forecast),
            forecastConfidence: confidenceLabel(dashboard.forecast.confidence),
            forecastMetrics: metrics,
            decisionRows: decisionRows,
            forecastSeries: series,
            hasForecastProjection: hasForecastProjection,
            footerText: updateState.footerText,
            footerActionTitle: "Refresh",
            isLoading: false
        )
    }

    private static func makeLoadingState(isRefreshing: Bool) -> UpdateState {
        if isRefreshing {
            return UpdateState(
                text: "Updating",
                accessibilityText: "Updating Codex quota data",
                footerText: "Updating Codex quota data"
            )
        }

        return UpdateState(
            text: "Loading",
            accessibilityText: "Loading Codex quota data",
            footerText: "Loading Codex quota data"
        )
    }

    private static func loadingDecisionRows() -> [PopoverMetric] {
        [
            PopoverMetric(label: "Estimated depletion", value: "Loading"),
            PopoverMetric(label: "Pace vs. budget", value: "Loading"),
            PopoverMetric(label: "Plan", value: "Loading"),
            PopoverMetric(label: "Billing status", value: "Status unavailable")
        ]
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
        let forecastUnavailableText = forecast.status == .collectingHistory
            ? "Collecting history"
            : "Estimating…"
        let depletion = forecast.status == .estimated
            ? forecast.estimatedDepletionAt.map(formatAbsoluteDate) ?? forecastUnavailableText
            : forecastUnavailableText
        let pace = forecast.status == .estimated
            ? forecast.paceDifference.map(paceDescription) ?? forecastUnavailableText
            : forecastUnavailableText

        let account = makeAccountDisplay(account)
        return [
            PopoverMetric(label: "Estimated depletion", value: depletion),
            PopoverMetric(label: "Pace vs. budget", value: pace),
            PopoverMetric(label: "Plan", value: account.plan),
            PopoverMetric(label: "Billing status", value: account.billingStatus)
        ]
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

    private static func forecastPaceText(for forecast: ForecastReport) -> String {
        guard forecast.status == .estimated else {
            return "Collecting history"
        }

        guard let consumedPerDay = forecast.consumedPerDay else {
            return "Estimating observed pace"
        }

        return "Observed pace: \(formatPercent(consumedPerDay))%/day"
    }

    private static func unavailableSparkDisplay() -> QuotaDisplay {
        QuotaDisplay(
            label: "Spark",
            isAvailable: false,
            valueText: "Unavailable",
            percentage: 0,
            reset: "Unavailable",
            resetSpoken: "unavailable",
            accessibilityDescription: "Spark quota unavailable. Reset time unavailable."
        )
    }

    private static func makeUpdateState(
        freshness: Freshness,
        isRefreshing: Bool
    ) -> UpdateState {
        if isRefreshing {
            return UpdateState(
                text: "Updating",
                accessibilityText: "Updating Codex quota data",
                footerText: "Updating Codex quota data"
            )
        }

        switch freshness {
        case .fresh:
            return UpdateState(
                text: "Updated now",
                accessibilityText: "Codex quota data updated now",
                footerText: "Updated now"
            )
        case .stale:
            return UpdateState(
                text: "Cached data",
                accessibilityText: "Cached Codex quota data may be out of date",
                footerText: "Cached data — may be out of date"
            )
        }
    }

    private static func quotaAccessibilityDescription(
        label: String,
        percentage: Int,
        reset: String
    ) -> String {
        "\(label) quota: \(percentage) percent remaining. Resets in \(reset)."
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

    private struct UpdateState: Equatable, Sendable {
        let text: String
        let accessibilityText: String
        let footerText: String
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
