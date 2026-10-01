import Foundation

enum QuotaChartWindow: String, CaseIterable {
    case fiveHour
    case weekly
    case fable

    var title: String { self == .fiveHour ? "5h" : self == .fable ? "Fable" : "Weekly" }
    var spokenTitle: String { self == .fiveHour ? "five-hour" : self == .fable ? "Fable weekly" : "weekly" }
    var duration: TimeInterval { self == .fiveHour ? 5 * 3600 : 7 * 86400 }
    var forecastTitle: String { self == .fiveHour ? "5-HOUR FORECAST" : self == .fable ? "FABLE WEEKLY FORECAST" : "WEEKLY FORECAST" }

    static func available(fiveHour: RateLimit?, weekly: RateLimit?, fable: RateLimit? = nil) -> [Self] {
        var result: [Self] = []
        if fiveHour != nil { result.append(.fiveHour) }
        if weekly != nil { result.append(.weekly) }
        if fable != nil { result.append(.fable) }
        return result
    }

    func resolved(in available: [Self]) -> Self {
        available.contains(self) ? self : available.contains(.weekly) ? .weekly : available.first ?? .weekly
    }
}
