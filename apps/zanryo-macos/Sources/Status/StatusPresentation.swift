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
        var label = "\(provider.displayName) has \(remainingPercent) percent remaining. Resets in \(resetSpoken)."
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
        isStaleOverride: Bool? = nil,
        now: Date = Date(),
        calendar _: Calendar = .autoupdatingCurrent
    ) -> StatusPresentation {
        guard openAIEnabled, let snapshot else {
            return StatusPresentation(modules: [])
        }

        let limit = snapshot.quota.currentFiveHour(now: now) ?? snapshot.quota.weekly
        let reset = ResetDuration(from: now, to: limit.resetsAt)
        return StatusPresentation(
            modules: [
                ProviderModule(
                    provider: .openAI,
                    remainingPercent: Int(limit.remainingPercent.rounded()),
                    reset: reset.menuBar,
                    resetSpoken: reset.spoken,
                    isStale: (isStaleOverride ?? false) || snapshot.quota.isStale(at: now)
                )
            ]
        )
    }

    static func claude(snapshot: ClaudeUsageSnapshot?, enabled: Bool, hasError: Bool, now: Date = Date()) -> StatusPresentation {
        guard enabled, let snapshot, let limit = snapshot.preferredLimit else { return StatusPresentation(modules: []) }
        let reset = ResetDuration(from: now, to: limit.resetsAt)
        return StatusPresentation(modules: [ProviderModule(provider: .claude,
            remainingPercent: Int(limit.remainingPercent.rounded()), reset: reset.menuBar,
            resetSpoken: reset.spoken, isStale: hasError || snapshot.isStale(at: now))])
    }
}
