import Combine
import Foundation

struct DisplayError: Error, Equatable, Sendable {
    let code: String
    let message: String
}

@MainActor
final class ZanryoStore: ObservableObject {
    @Published private(set) var snapshot: DashboardSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: DisplayError?
    @Published private(set) var lastSuccessfulUpdate: Date?

    private let provider: any DashboardProviding
    private var refreshTask: Task<Void, Never>?

    init(provider: any DashboardProviding) {
        self.provider = provider
    }

    func start() async {
        do {
            snapshot = try await provider.cached()
        } catch {
            lastError = Self.displayError(from: error)
        }

        await refresh()
    }

    func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }

        isRefreshing = true
        let provider = provider
        let task = Task { [weak self] in
            do {
                let snapshot = try await provider.refresh()
                guard let self else {
                    return
                }
                self.snapshot = snapshot
                self.lastError = nil
                self.lastSuccessfulUpdate = Date()
            } catch {
                self?.lastError = Self.displayError(from: error)
            }
        }
        refreshTask = task

        await task.value
        refreshTask = nil
        isRefreshing = false
    }

    private static func displayError(from error: Error) -> DisplayError {
        if let displayError = error as? DisplayError {
            return displayError
        }
        if case let BridgeDecodeError.remote(code, message) = error {
            return DisplayError(code: code, message: message)
        }
        return DisplayError(code: "unknown_error", message: error.localizedDescription)
    }
}
