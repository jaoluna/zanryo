import Foundation

struct ProviderPreferences {
    private static let key = "providerEnabledOverrides"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func isEnabled(_ provider: ProviderId, installed: Bool) -> Bool {
        guard installed else { return false }

        let overrides = defaults.dictionary(forKey: Self.key) as? [String: Bool] ?? [:]
        return overrides[provider.rawValue] ?? true
    }

    func setEnabled(_ enabled: Bool, for provider: ProviderId) {
        var overrides = defaults.dictionary(forKey: Self.key) as? [String: Bool] ?? [:]
        overrides[provider.rawValue] = enabled
        defaults.set(overrides, forKey: Self.key)
    }
}
