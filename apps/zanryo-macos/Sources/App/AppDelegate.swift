import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ZanryoStore?
    private var claudeStore: ClaudeUsageStore?
    private var registry: ProviderRegistry?
    private var statusItemController: StatusItemController?
    private var popoverCoordinator: PopoverCoordinator?
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    var hasStartedCollectors: Bool { store != nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // A hosted XCTest launch must not open/migrate the user's database or
        // start authenticated collectors. Tests construct their own fixtures.
        guard NSClassFromString("XCTestCase") == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        do {
            let bridge = try RustBridge()
            let store = ZanryoStore(provider: bridge)
            let registry = ProviderRegistry(discoverer: bridge)
            let claudeStore = ClaudeUsageStore(source: bridge)
            registry.onClaudeRefresh = { [weak claudeStore] force in await claudeStore?.refresh(force: force) }
            let popoverCoordinator = PopoverCoordinator(store: store, registry: registry)
            let contextMenu = StatusItemContextMenu(
                onRefresh: {
                    Task {
                        if registry.selectedProvider == .claude {
                            await registry.refreshClaude(force: true)
                        } else if registry.shouldRefreshOpenAI {
                            await store.refresh()
                        }
                    }
                },
                onQuit: { NSApp.terminate(nil) }
            )
            let statusItemController = StatusItemController { [weak popoverCoordinator] action, button, event in
                guard let popoverCoordinator else {
                    return
                }

                switch action {
                case .togglePopover:
                    popoverCoordinator.toggle(relativeTo: button)
                case .showContextMenu:
                    popoverCoordinator.close()
                    contextMenu.show(
                        for: button,
                        event: event,
                        isRefreshing: store.isRefreshing
                    )
                }
            }
            popoverCoordinator.onVisibilityChanged = { [weak statusItemController] isShown in
                statusItemController?.setHighlighted(isShown)
            }

            self.store = store
            self.claudeStore = claudeStore
            self.registry = registry
            self.popoverCoordinator = popoverCoordinator
            self.statusItemController = statusItemController

            observeStore(in: store, registry: registry)
            observeStatus(in: registry, statusItemController: statusItemController)
            observeRefreshEligibility(in: registry, store: store)
            claudeStore.$snapshot.combineLatest(claudeStore.$lastError, claudeStore.$isRefreshing)
                .sink { [weak registry] snapshot, error, refreshing in
                    registry?.updateClaude(snapshot: snapshot, error: error, isRefreshing: refreshing)
                }.store(in: &cancellables)
            registry.$shouldRefreshClaude.removeDuplicates().sink { [weak claudeStore] enabled in
                if enabled { Task { await claudeStore?.start() } }
            }.store(in: &cancellables)
            installRefreshTimer()
            Task { await registry.discover() }
        } catch {
            let statusItemController = StatusItemController(onAction: { _, _, _ in })
            statusItemController.update(StatusPresentation.make(snapshot: nil))
            self.statusItemController = statusItemController
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        statusItemController?.invalidate()
    }

    private func observeStore(in store: ZanryoStore, registry: ProviderRegistry) {
        store.$snapshot
            .combineLatest(store.$lastError)
            .sink { [weak registry] snapshot, error in
                registry?.updateOpenAI(snapshot: snapshot, error: error)
            }
            .store(in: &cancellables)
    }

    private func observeStatus(
        in registry: ProviderRegistry,
        statusItemController: StatusItemController
    ) {
        registry.$statusPresentation
            .sink { [weak statusItemController] presentation in
                statusItemController?.update(presentation)
            }
            .store(in: &cancellables)
    }

    private func observeRefreshEligibility(in registry: ProviderRegistry, store: ZanryoStore) {
        registry.$shouldRefreshOpenAI
            .removeDuplicates()
            .sink { shouldRefresh in
                guard shouldRefresh else {
                    return
                }
                Task { await store.start() }
            }
            .store(in: &cancellables)
    }

    private func installRefreshTimer() {
        let timer = Timer(
            timeInterval: 60,
            target: self,
            selector: #selector(refreshTimerFired),
            userInfo: nil,
            repeats: true
        )
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    @objc
    private func refreshTimerFired() {
        if registry?.shouldRefreshClaude == true { Task { await claudeStore?.refresh() } }
        guard let store, registry?.shouldRefreshOpenAI == true else {
            return
        }
        Task { await store.refresh() }
    }
}
