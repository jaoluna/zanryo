import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: ZanryoStore?
    private var statusItemController: StatusItemController?
    private var popoverCoordinator: PopoverCoordinator?
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        do {
            let bridge = try RustBridge()
            let store = ZanryoStore(provider: bridge)
            let popoverCoordinator = PopoverCoordinator(store: store)
            let contextMenu = StatusItemContextMenu(
                onRefresh: { Task { await store.refresh() } },
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
            self.popoverCoordinator = popoverCoordinator
            self.statusItemController = statusItemController

            observeSnapshot(in: store)
            installRefreshTimer()
            Task { await store.start() }
        } catch {
            let statusItemController = StatusItemController(onAction: { _, _, _ in })
            statusItemController.update(StatusTitle.make(snapshot: nil))
            self.statusItemController = statusItemController
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        statusItemController?.invalidate()
    }

    private func observeSnapshot(in store: ZanryoStore) {
        store.$snapshot
            .sink { [weak statusItemController] snapshot in
                statusItemController?.update(StatusTitle.make(snapshot: snapshot))
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
        guard let store else {
            return
        }
        Task { await store.refresh() }
    }
}
