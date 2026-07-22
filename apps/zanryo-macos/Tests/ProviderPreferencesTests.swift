import Foundation
import XCTest
@testable import Zanryo

final class ProviderPreferencesTests: XCTestCase {
    func testInstalledProviderDefaultsOnUntilExplicitlyDisabled() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = ProviderPreferences(defaults: defaults)

        XCTAssertTrue(preferences.isEnabled(.claude, installed: true))
        XCTAssertNil(defaults.object(forKey: "providerEnabledOverrides"))
        preferences.setEnabled(false, for: .claude)
        let reloadedPreferences = ProviderPreferences(defaults: defaults)
        XCTAssertFalse(reloadedPreferences.isEnabled(.claude, installed: true))
        XCTAssertFalse(reloadedPreferences.isEnabled(.claude, installed: false))
    }

    func testAbsentProviderIsAlwaysDisabledWithoutPersistingAnOverride() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = ProviderPreferences(defaults: defaults)

        XCTAssertFalse(preferences.isEnabled(.openAI, installed: false))
        XCTAssertNil(defaults.object(forKey: "providerEnabledOverrides"))
    }

    func testExplicitOverrideSurvivesProviderDisappearanceAndReturn() {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        let preferences = ProviderPreferences(defaults: defaults)

        preferences.setEnabled(false, for: .claude)

        XCTAssertFalse(preferences.isEnabled(.claude, installed: false))
        XCTAssertFalse(preferences.isEnabled(.claude, installed: true))
    }
}
