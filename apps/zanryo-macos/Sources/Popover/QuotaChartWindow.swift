import Foundation

enum QuotaChartWindow: String, CaseIterable {
    case fiveHour
    case weekly

    var title: String { self == .fiveHour ? "5h" : "Weekly" }
    var spokenTitle: String { self == .fiveHour ? "five-hour" : "weekly" }
    var duration: TimeInterval { self == .fiveHour ? 5 * 3600 : 7 * 86400 }
    var forecastTitle: String { self == .fiveHour ? "5-HOUR FORECAST" : "WEEKLY FORECAST" }

    static func available(fiveHour: RateLimit?, weekly: RateLimit?) -> [Self] {
        var result: [Self] = []
        if fiveHour != nil { result.append(.fiveHour) }
        if weekly != nil { result.append(.weekly) }
        return result
    }

    func resolved(in available: [Self]) -> Self {
        available.contains(self) ? self : available.contains(.weekly) ? .weekly : available.first ?? .weekly
    }
}
