import AppKit

@MainActor
final class StatusItemContextMenu {
    private let onRefresh: () -> Void
    private let onQuit: () -> Void

    init(onRefresh: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onRefresh = onRefresh
        self.onQuit = onQuit
    }

    func show(for button: NSStatusBarButton, event: NSEvent?, isRefreshing: Bool) {
        guard let event else {
            return
        }

        let menu = Self.makeMenu(
            isRefreshing: isRefreshing,
            onRefresh: onRefresh,
            onQuit: onQuit
        )
        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    static func makeMenu(
        isRefreshing: Bool,
        onRefresh: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) -> NSMenu {
        let target = StatusItemContextMenuTarget(onRefresh: onRefresh, onQuit: onQuit)
        let menu = NSMenu()

        let refresh = NSMenuItem(
            title: "Refresh now",
            action: #selector(StatusItemContextMenuTarget.refresh(_:)),
            keyEquivalent: ""
        )
        refresh.target = target
        refresh.isEnabled = !isRefreshing
        refresh.representedObject = target
        menu.addItem(refresh)
        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit Zanryo",
            action: #selector(StatusItemContextMenuTarget.quit(_:)),
            keyEquivalent: "q"
        )
        quit.target = target
        quit.keyEquivalentModifierMask = [.command]
        quit.representedObject = target
        menu.addItem(quit)

        return menu
    }
}

@MainActor
private final class StatusItemContextMenuTarget: NSObject {
    private let onRefresh: () -> Void
    private let onQuit: () -> Void

    init(onRefresh: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onRefresh = onRefresh
        self.onQuit = onQuit
    }

    @objc
    func refresh(_ sender: Any?) {
        onRefresh()
    }

    @objc
    func quit(_ sender: Any?) {
        onQuit()
    }
}
