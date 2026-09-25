import Combine
import Foundation

struct ClaudeUsageSnapshot: Decodable, Equatable, Sendable {
    let provider: ProviderId
    let fiveHour: RateLimit?
    let weekly: RateLimit?
    let freshness: Freshness

    var preferredLimit: RateLimit? { fiveHour ?? weekly }
    var windows: [RateLimit] { [fiveHour, weekly].compactMap { $0 } }
    func isStale(at now: Date = Date()) -> Bool {
        freshness == .stale || windows.contains {
            now.timeIntervalSince($0.observedAt) > 360 || $0.observedAt > now || $0.resetsAt <= now
        }
    }
}

protocol ClaudeUsageProviding: Sendable {
    func cachedClaude() async throws -> ClaudeUsageSnapshot?
    func refreshClaude() async throws -> ClaudeUsageSnapshot
}

@MainActor
final class ClaudeUsageStore: ObservableObject {
    @Published private(set) var snapshot: ClaudeUsageSnapshot?
    @Published private(set) var lastError: DisplayError?
    @Published private(set) var isRefreshing = false
    private let source: any ClaudeUsageProviding
    private var task: Task<Void, Never>?
    private var lastAttempt: Date?

    init(source: any ClaudeUsageProviding) { self.source = source }

    func start() async {
        do { snapshot = try await source.cachedClaude() }
        catch { lastError = DisplayError(code: "claude_cache", message: error.localizedDescription) }
        await refresh()
    }

    func refresh(force: Bool = false, now: Date = Date()) async {
        if let task { await task.value; return }
        // Native CLI is heavier than app-server. Bound both background polling
        // and repeated failures; explicit refresh remains available.
        if !force, let lastAttempt, now.timeIntervalSince(lastAttempt) >= 0,
           now.timeIntervalSince(lastAttempt) < 300 { return }
        lastAttempt = now
        isRefreshing = true
        let source = source
        let task = Task { [weak self] in
            do {
                let result = try await source.refreshClaude()
                self?.snapshot = result
                self?.lastError = result.freshness == .stale
                    ? DisplayError(code: "claude_stale", message: "Refresh failed. Showing the last saved reading.") : nil
            } catch {
                self?.lastError = error as? DisplayError
                    ?? DisplayError(code: "claude_unavailable", message: error.localizedDescription)
            }
        }
        self.task = task
        await task.value
        self.task = nil
        isRefreshing = false
    }
}
