import AppKit
import SwiftUI

@MainActor
final class PopoverCoordinator {
    private let store: ZanryoStore
    private let popover: NSPopover

    init(store: ZanryoStore) {
        self.store = store
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 360, height: 410)
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(store: store)
        )
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
            return
        }

        popover.show(
            relativeTo: button.bounds,
            of: button,
            preferredEdge: .minY
        )
        Task { await store.refresh() }
    }
}
