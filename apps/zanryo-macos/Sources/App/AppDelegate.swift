import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ZanryoStore?
    private var registry: ProviderRegistry?
    private var statusItemController: StatusItemController?
    private var popoverCoordinator: PopoverCoordinator?
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            let bridge = try RustBridge()
            let store = ZanryoStore(provider: bridge)
            let registry = ProviderRegistry(discoverer: bridge)
            let popoverCoordinator = PopoverCoordinator(store: store, registry: registry)
            let contextMenu = StatusItemContextMenu(
                onRefresh: {
                    Task {
                        guard registry.shouldRefreshOpenAI else {
                            return
                        }
                        await store.refresh()
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
            self.registry = registry
            self.popoverCoordinator = popoverCoordinator
            self.statusItemController = statusItemController

            observeStore(in: store, registry: registry)
            observeStatus(in: registry, statusItemController: statusItemController)
            observeRefreshEligibility(in: registry, store: store)
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
        guard let store, registry?.shouldRefreshOpenAI == true else {
            return
        }
        Task { await store.refresh() }
    }
}
