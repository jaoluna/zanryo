import Combine
import Foundation

enum ProviderAvailability: Equatable, Sendable {
    case notInstalled
    case available
    case unavailable
    case error
}

struct ProviderState: Equatable, Sendable {
    let provider: ProviderId
    let executablePath: String?
    let isEnabled: Bool
    let availability: ProviderAvailability

    var isInstalled: Bool {
        executablePath != nil
    }
}

@MainActor
final class ProviderRegistry: ObservableObject {
    @Published private(set) var installedProviders: [ProviderId] = []
    @Published private(set) var selectedProvider: ProviderId?
    @Published private(set) var statusPresentation = StatusPresentation(modules: [])
    @Published private(set) var shouldRefreshOpenAI = false

    private let discoverer: any ProviderDiscovering
    private let preferences: ProviderPreferences
    private var installations: [ProviderId: ProviderInstallation] = [:]
    private var openAISnapshot: DashboardSnapshot?
    private var openAIError: DisplayError?

    init(
        discoverer: any ProviderDiscovering,
        preferences: ProviderPreferences = ProviderPreferences()
    ) {
        self.discoverer = discoverer
        self.preferences = preferences
    }

    func discover() async {
        do {
            let discovered = try await discoverer.discoverProviders()
            installations = Dictionary(
                uniqueKeysWithValues: discovered.map { ($0.provider, $0) }
            )
            reconcile()
        } catch {
            // Keep the last known installation set so a transient discovery failure
            // cannot erase an explicit user preference or fake an unavailable quota.
            reconcile()
        }
    }

    func select(_ provider: ProviderId) {
        guard installations[provider] != nil else {
            return
        }
        selectedProvider = provider
    }

    func isEnabled(_ provider: ProviderId) -> Bool {
        preferences.isEnabled(provider, installed: installations[provider] != nil)
    }

    func setEnabled(_ enabled: Bool, for provider: ProviderId) {
        guard installations[provider] != nil else {
            return
        }
        preferences.setEnabled(enabled, for: provider)
        reconcile()
    }

    func state(for provider: ProviderId) -> ProviderState {
        let installation = installations[provider]
        let installed = installation != nil
        let enabled = preferences.isEnabled(provider, installed: installed)

        guard installed else {
            return ProviderState(
                provider: provider,
                executablePath: nil,
                isEnabled: false,
                availability: .notInstalled
            )
        }

        switch provider {
        case .openAI:
            let availability: ProviderAvailability
            if !enabled {
                availability = .unavailable
            } else if openAIError != nil {
                availability = .error
            } else if openAISnapshot != nil {
                availability = .available
            } else {
                availability = .unavailable
            }
            return ProviderState(
                provider: provider,
                executablePath: installation?.executablePath,
                isEnabled: enabled,
                availability: availability
            )
        case .claude:
            return ProviderState(
                provider: provider,
                executablePath: installation?.executablePath,
                isEnabled: enabled,
                availability: .unavailable
            )
        }
    }

    func updateOpenAI(snapshot: DashboardSnapshot?, error: DisplayError?) {
        if let snapshot {
            openAISnapshot = snapshot
        }
        openAIError = error
        reconcile()
    }

    private func reconcile() {
        installedProviders = ProviderId.allCases.filter { installations[$0] != nil }

        if let selectedProvider, installations[selectedProvider] == nil {
            self.selectedProvider = installedProviders.first
        } else if selectedProvider == nil {
            selectedProvider = installedProviders.first
        }

        shouldRefreshOpenAI = isEnabled(.openAI)
        statusPresentation = StatusPresentation.make(
            snapshot: openAISnapshot,
            openAIEnabled: shouldRefreshOpenAI,
            isStaleOverride: openAIError == nil ? nil : true
        )
    }
}
