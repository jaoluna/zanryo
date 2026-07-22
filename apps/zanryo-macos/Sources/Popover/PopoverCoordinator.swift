import AppKit
import SwiftUI

typealias OutsideClickHandler = @MainActor () -> Void

@MainActor
final class PopoverCoordinator: NSObject, NSPopoverDelegate {
    private let store: ZanryoStore
    private let registry: ProviderRegistry
    private let popover: NSPopover
    private let showPopover: @MainActor (NSPopover, NSStatusBarButton) -> Void
    private let startOutsideClickMonitoring: @MainActor (@escaping OutsideClickHandler) -> Any?
    private let stopOutsideClickMonitoring: @MainActor (Any) -> Void
    private let closePopover: @MainActor (NSPopover) -> Void
    private var outsideClickMonitor: Any?
    var onVisibilityChanged: ((Bool) -> Void)?

    init(
        store: ZanryoStore,
        registry: ProviderRegistry,
        showPopover: @escaping @MainActor (NSPopover, NSStatusBarButton) -> Void = PopoverCoordinator.showAnchoredPopover,
        startOutsideClickMonitoring: @escaping @MainActor (@escaping OutsideClickHandler) -> Any? = PopoverCoordinator.startGlobalOutsideClickMonitor,
        stopOutsideClickMonitoring: @escaping @MainActor (Any) -> Void = { NSEvent.removeMonitor($0) },
        closePopover: @escaping @MainActor (NSPopover) -> Void = { $0.performClose(nil) }
    ) {
        self.store = store
        self.registry = registry
        self.showPopover = showPopover
        self.startOutsideClickMonitoring = startOutsideClickMonitoring
        self.stopOutsideClickMonitoring = stopOutsideClickMonitoring
        self.closePopover = closePopover
        popover = NSPopover()
        super.init()

        popover.delegate = self
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentSize = NSSize(width: 390, height: 590)
        let hostingController = NSHostingController(
            rootView: PopoverView(store: store, registry: registry)
        )
        hostingController.view.frame = NSRect(origin: .zero, size: popover.contentSize)
        popover.contentViewController = hostingController
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            close()
            return
        }

        showPopover(popover, button)
        startOutsideClickMonitor()
        onVisibilityChanged?(true)
        Task {
            guard registry.shouldRefreshOpenAI else {
                return
            }
            await store.refreshAfterOpening()
        }
    }

    func close() {
        stopOutsideClickMonitor()
        closePopover(popover)
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitor()
        onVisibilityChanged?(false)
    }

    private func startOutsideClickMonitor() {
        guard outsideClickMonitor == nil else {
            return
        }

        outsideClickMonitor = startOutsideClickMonitoring { [weak self] in
            self?.close()
        }
    }

    private func stopOutsideClickMonitor() {
        guard let outsideClickMonitor else {
            return
        }

        stopOutsideClickMonitoring(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }

    private static func showAnchoredPopover(
        _ popover: NSPopover,
        relativeTo button: NSStatusBarButton
    ) {
        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
    }

    private static func startGlobalOutsideClickMonitor(
        handler: @escaping OutsideClickHandler
    ) -> Any? {
        NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { _ in
            Task { @MainActor in
                handler()
            }
        }
    }
}
