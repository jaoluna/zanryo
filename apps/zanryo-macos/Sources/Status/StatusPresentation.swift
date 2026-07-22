import Foundation

struct ProviderModule: Equatable, Sendable {
    let provider: ProviderId
    let remainingPercent: Int
    let reset: String
    let resetSpoken: String
    let isStale: Bool

    var text: String {
        "\(remainingPercent)% · \(reset)\(isStale ? " ·" : "")"
    }

    var accessibilityLabel: String {
        var label = "\(provider.accessibilityName) has \(remainingPercent) percent remaining. Resets in \(resetSpoken)."
        if isStale {
            label += " Data may be outdated."
        }
        return label
    }
}

struct StatusPresentation: Equatable, Sendable {
    let modules: [ProviderModule]

    init(modules: [ProviderModule]) {
        self.modules = modules.sorted { $0.provider.statusOrder < $1.provider.statusOrder }
    }

    var dragonOnly: Bool {
        modules.isEmpty
    }

    var accessibilityLabel: String {
        guard !modules.isEmpty else {
            return "Zanryo. No enabled provider quota is available."
        }
        return modules.map(\.accessibilityLabel).joined(separator: " ")
    }

    static func make(
        snapshot: DashboardSnapshot?,
        openAIEnabled: Bool = true,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> StatusPresentation {
        guard openAIEnabled, let snapshot else {
            return StatusPresentation(modules: [])
        }

        let limit = fiveHourLimit(in: snapshot.quota.other) ?? snapshot.quota.weekly
        let reset = StatusResetDuration(from: now, to: limit.resetsAt, calendar: calendar)
        return StatusPresentation(
            modules: [
                ProviderModule(
                    provider: .openAI,
                    remainingPercent: Int(limit.remainingPercent.rounded()),
                    reset: reset.compact,
                    resetSpoken: reset.spoken,
                    isStale: snapshot.quota.freshness == .stale
                )
            ]
        )
    }

    private static func fiveHourLimit(in other: [RateLimit]) -> RateLimit? {
        other.first { limit in
            let identifier = limit.limitId.lowercased()
            return identifier.contains("five_hour")
                || identifier.contains("five-hour")
                || identifier.contains("fivehour")
                || identifier.contains("5-hour")
                || identifier.contains("5h")
        }
    }
}

private extension ProviderId {
    var statusOrder: Int {
        switch self {
        case .openAI:
            0
        case .claude:
            1
        }
    }

    var accessibilityName: String {
        switch self {
        case .openAI:
            "OpenAI"
        case .claude:
            "Claude"
        }
    }
}

private struct StatusResetDuration {
    let days: Int
    let hours: Int

    init(from start: Date, to end: Date, calendar: Calendar) {
        guard end > start else {
            days = 0
            hours = 0
            return
        }

        let components = calendar.dateComponents([.day, .hour], from: start, to: end)
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
