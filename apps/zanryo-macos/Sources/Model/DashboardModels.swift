import Foundation

enum LimitKind: String, Decodable, Sendable {
    case weekly
    case spark
    case other
}

enum Freshness: String, Decodable, Sendable {
    case fresh
    case stale
}

struct RateLimit: Decodable, Equatable, Sendable {
    let kind: LimitKind
    let limitId: String
    let remainingPercent: Double
    let resetsAt: Date
    let observedAt: Date
}

struct QuotaSnapshot: Decodable, Equatable, Sendable {
    let weekly: RateLimit
    let spark: RateLimit?
    let other: [RateLimit]
    let freshness: Freshness
}

enum ForecastStatus: String, Decodable, Sendable {
    case collectingHistory = "collecting_history"
    case estimated
}

enum ForecastConfidence: String, Decodable, Sendable {
    case collecting
    case low
    case medium
    case high
}

struct ForecastRange: Decodable, Equatable, Sendable {
    let low: Double
    let high: Double
}

struct ChartPoint: Decodable, Equatable, Sendable {
    let at: Date
    let remainingPercent: Double
}

struct ForecastPoint: Decodable, Equatable, Sendable {
    let at: Date
    let remainingPercent: Double
    let uncertainty: ForecastRange
}

struct ChartSeries: Decodable, Equatable, Sendable {
    let observed: [ChartPoint]
    let forecast: [ForecastPoint]
    let sustainable: [ChartPoint]
}

struct ForecastReport: Decodable, Equatable, Sendable {
    let status: ForecastStatus
    let confidence: ForecastConfidence
    let consumedPerDay: Double?
    let sustainablePerDay: Double?
    let paceDifference: Double?
    let estimatedDepletionAt: Date?
    let rateRange: ForecastRange?
    let chart: ChartSeries
}

struct DashboardSnapshot: Decodable, Equatable, Sendable {
    let quota: QuotaSnapshot
    let forecast: ForecastReport
}
