import XCTest
@testable import Zanryo

@MainActor
final class ZanryoStoreTests: XCTestCase {
    func testStartPublishesCacheBeforeRefreshCompletes() async {
        let cached = makeSnapshot(remaining: 40)
        let fresh = makeSnapshot(remaining: 39)
        let provider = TestDashboardProvider(cached: cached, refresh: .success(fresh))
        let store = ZanryoStore(provider: provider)

        let start = Task { await store.start() }
        await provider.waitUntilRefreshStarts()

        XCTAssertEqual(store.snapshot, cached)
        XCTAssertTrue(store.isRefreshing)

        await provider.releaseRefresh()
        await start.value
    }

    func testSuccessfulRefreshAtomicallyReplacesSnapshot() async {
        let cached = makeSnapshot(remaining: 40)
        let fresh = makeSnapshot(remaining: 39)
        let provider = TestDashboardProvider(cached: cached, refresh: .success(fresh))
        let store = ZanryoStore(provider: provider)

        let start = Task { await store.start() }
        await provider.waitUntilRefreshStarts()
        await provider.releaseRefresh()
        await start.value

        XCTAssertEqual(store.snapshot, fresh)
        XCTAssertNil(store.lastError)
        XCTAssertNotNil(store.lastSuccessfulUpdate)
    }

    func testFailedRefreshPreservesCacheAndRecordsError() async {
        let cached = makeSnapshot(remaining: 40)
        let expectedError = DisplayError(code: "codex_unavailable", message: "Codex is unavailable")
        let provider = TestDashboardProvider(cached: cached, refresh: .failure(expectedError))
        let store = ZanryoStore(provider: provider)

        let start = Task { await store.start() }
        await provider.waitUntilRefreshStarts()
        await provider.releaseRefresh()
        await start.value

        XCTAssertEqual(store.snapshot, cached)
        XCTAssertEqual(store.lastError, expectedError)
        XCTAssertNil(store.lastSuccessfulUpdate)
    }

    func testSimultaneousRefreshCallsAreCoalesced() async {
        let provider = TestDashboardProvider(
            cached: nil,
            refresh: .success(makeSnapshot(remaining: 39))
        )
        let store = ZanryoStore(provider: provider)

        let first = Task { await store.refresh() }
        await provider.waitUntilRefreshStarts()
        let second = Task { await store.refresh() }
        await Task.yield()
        await provider.releaseRefresh()
        await first.value
        await second.value

        let refreshCallCount = await provider.refreshCallCount()
        XCTAssertEqual(refreshCallCount, 1)
    }
}

private actor TestDashboardProvider: DashboardProviding {
    enum Outcome: Sendable {
        case success(DashboardSnapshot)
        case failure(DisplayError)
    }

    private let cachedSnapshot: DashboardSnapshot?
    private let outcome: Outcome
    private var refreshCalls = 0
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [CheckedContinuation<Void, Never>] = []

    init(cached: DashboardSnapshot?, refresh: Outcome) {
        cachedSnapshot = cached
        outcome = refresh
    }

    func cached() async throws -> DashboardSnapshot? {
        cachedSnapshot
    }

    func refresh() async throws -> DashboardSnapshot {
        refreshCalls += 1
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { refreshWaiters.append($0) }

        switch outcome {
        case let .success(snapshot):
            return snapshot
        case let .failure(error):
            throw error
        }
    }

    func waitUntilRefreshStarts() async {
        guard refreshCalls == 0 else {
            return
        }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func releaseRefresh() {
        refreshWaiters.forEach { $0.resume() }
        refreshWaiters.removeAll()
    }

    func refreshCallCount() -> Int {
        refreshCalls
    }
}

private func makeSnapshot(remaining: Double) -> DashboardSnapshot {
    let now = Date(timeIntervalSince1970: 1_774_171_200)
    let weekly = RateLimit(
        kind: .weekly,
        limitId: "codex",
        remainingPercent: remaining,
        resetsAt: now.addingTimeInterval(5 * 86_400),
        observedAt: now
    )

    return DashboardSnapshot(
        quota: QuotaSnapshot(
            weekly: weekly,
            spark: nil,
            other: [],
            freshness: .fresh
        ),
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
