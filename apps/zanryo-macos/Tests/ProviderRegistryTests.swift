import Foundation
import XCTest
@testable import Zanryo

@MainActor
final class ProviderRegistryTests: XCTestCase {
    func testDiscoveryOrdersProvidersAndOpenAIQuotaDrivesOnlyItsModule() async {
        let defaults = makeDefaults()
        let source = ProviderDiscoveryStub([
            ProviderInstallation(provider: .claude, executablePath: "/usr/local/bin/claude"),
            ProviderInstallation(provider: .openAI, executablePath: "/usr/local/bin/openai")
        ])
        let registry = ProviderRegistry(
            discoverer: source,
            preferences: ProviderPreferences(defaults: defaults)
        )

        await registry.discover()

        XCTAssertEqual(registry.installedProviders, [.openAI, .claude])
        XCTAssertEqual(registry.selectedProvider, .openAI)
        XCTAssertEqual(registry.state(for: .openAI).availability, .unavailable)
        XCTAssertEqual(registry.state(for: .claude).availability, .unavailable)

        registry.updateOpenAI(snapshot: makeSnapshot(), error: nil)

        XCTAssertEqual(registry.state(for: .openAI).availability, .available)
        XCTAssertEqual(registry.statusPresentation.modules.map(\.provider), [.openAI])

        registry.setEnabled(false, for: .openAI)

        XCTAssertFalse(registry.shouldRefreshOpenAI)
        XCTAssertTrue(registry.statusPresentation.dragonOnly)
        XCTAssertFalse(registry.isEnabled(.openAI))
    }

    func testSelectionFallsBackAndExplicitPreferenceSurvivesProviderDisappearance() async {
        let defaults = makeDefaults()
        let source = ProviderDiscoveryStub([
            ProviderInstallation(provider: .openAI, executablePath: "/usr/local/bin/openai"),
            ProviderInstallation(provider: .claude, executablePath: "/usr/local/bin/claude")
        ])
        let registry = ProviderRegistry(
            discoverer: source,
            preferences: ProviderPreferences(defaults: defaults)
        )

        await registry.discover()
        registry.select(.claude)
        registry.setEnabled(false, for: .claude)

        await source.setInstallations([
            ProviderInstallation(provider: .openAI, executablePath: "/usr/local/bin/openai")
        ])
        await registry.discover()

        XCTAssertEqual(registry.selectedProvider, .openAI)
        XCTAssertFalse(registry.state(for: .claude).isInstalled)

        await source.setInstallations([
            ProviderInstallation(provider: .claude, executablePath: "/usr/local/bin/claude")
        ])
        await registry.discover()

        XCTAssertEqual(registry.selectedProvider, .claude)
        XCTAssertFalse(registry.isEnabled(.claude))
    }

    func testRefreshFailureKeepsLastOpenAIQuotaAndMarksItStale() async {
        let source = ProviderDiscoveryStub([
            ProviderInstallation(provider: .openAI, executablePath: "/usr/local/bin/openai")
        ])
        let registry = ProviderRegistry(discoverer: source, preferences: ProviderPreferences(defaults: makeDefaults()))
        await registry.discover()
        registry.updateOpenAI(snapshot: makeSnapshot(), error: nil)

        registry.updateOpenAI(
            snapshot: makeSnapshot(),
            error: DisplayError(code: "network", message: "Offline")
        )

        XCTAssertEqual(registry.state(for: .openAI).availability, .error)
        XCTAssertEqual(registry.statusPresentation.modules.first?.remainingPercent, 40)
        XCTAssertTrue(registry.statusPresentation.modules.first?.isStale ?? false)
    }

    private func makeDefaults() -> UserDefaults {
        let name = "ProviderRegistryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeSnapshot() -> DashboardSnapshot {
        let now = Date(timeIntervalSince1970: 1_774_171_200)
        let weekly = RateLimit(
            kind: .weekly,
            limitId: "codex",
            remainingPercent: 40,
            resetsAt: now.addingTimeInterval(5 * 86_400),
            observedAt: now
        )
        return DashboardSnapshot(
            quota: QuotaSnapshot(weekly: weekly, spark: nil, other: [], freshness: .fresh),
            forecast: ForecastReport(
                status: .collectingHistory,
                confidence: .collecting,
                consumedPerDay: nil,
                sustainablePerDay: nil,
                paceDifference: nil,
                estimatedDepletionAt: nil,
                rateRange: nil,
                chart: ChartSeries(observed: [], forecast: [], sustainable: [])
            )
        )
    }
}

private actor ProviderDiscoveryStub: ProviderDiscovering {
    private var installations: [ProviderInstallation]

    init(_ installations: [ProviderInstallation]) {
        self.installations = installations
    }

    func discoverProviders() async throws -> [ProviderInstallation] {
        installations
    }

    func setInstallations(_ installations: [ProviderInstallation]) {
        self.installations = installations
    }
}
