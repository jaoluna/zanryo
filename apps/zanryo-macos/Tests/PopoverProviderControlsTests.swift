import Foundation
import XCTest
@testable import Zanryo

@MainActor
final class PopoverProviderControlsTests: XCTestCase {
    func testClaudeCanBeSelectedWithoutInventingQuotaData() async {
        let name = "PopoverProviderControlsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let registry = ProviderRegistry(
            discoverer: ClaudeOnlyDiscovery(),
            preferences: ProviderPreferences(defaults: defaults)
        )

        await registry.discover()
        registry.select(.claude)

        XCTAssertEqual(registry.selectedProvider, .claude)
        XCTAssertTrue(registry.isEnabled(.claude))
        XCTAssertEqual(registry.state(for: .claude).availability, .unavailable)
        XCTAssertTrue(registry.statusPresentation.dragonOnly)
        XCTAssertFalse(registry.shouldRefreshOpenAI)
    }
}

private actor ClaudeOnlyDiscovery: ProviderDiscovering {
    func discoverProviders() async throws -> [ProviderInstallation] {
        [ProviderInstallation(provider: .claude, executablePath: "/usr/local/bin/claude")]
    }
}
