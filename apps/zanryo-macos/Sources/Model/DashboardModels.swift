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

enum PlanType: Equatable, Sendable, Decodable {
    case free
    case go
    case plus
    case pro
    case proLite
    case team
    case business
    case enterprise
    case edu
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self.fromBridge(raw)
    }

    static func fromBridge(_ raw: String) -> PlanType {
        switch raw {
        case "free":
            .free
        case "go":
            .go
        case "plus":
            .plus
        case "pro":
            .pro
        case "pro_lite":
            .proLite
        case "team":
            .team
        case "business":
            .business
        case "enterprise":
            .enterprise
        case "edu":
            .edu
        default:
            .unknown
        }
    }
}

struct AccountContext: Decodable, Equatable, Sendable {
    let planType: PlanType
    let observedAt: Date?
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
    let account: AccountContext?

    init(
        quota: QuotaSnapshot,
        forecast: ForecastReport,
        account: AccountContext? = nil
    ) {
        self.quota = quota
        self.forecast = forecast
        self.account = account
    }
}
