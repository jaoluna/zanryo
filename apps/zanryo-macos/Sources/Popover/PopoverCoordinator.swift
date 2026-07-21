import AppKit
import SwiftUI

@MainActor
final class PopoverCoordinator: NSObject, NSPopoverDelegate {
    private let store: ZanryoStore
    private let popover: NSPopover
    var onVisibilityChanged: ((Bool) -> Void)?

    init(store: ZanryoStore) {
        self.store = store
        popover = NSPopover()
        super.init()

        popover.delegate = self
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 360, height: 410)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(store: store)
        )
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            close()
            return
        }

        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        onVisibilityChanged?(true)
        Task { await store.refresh() }
    }

    func close() {
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        onVisibilityChanged?(false)
    }
}
