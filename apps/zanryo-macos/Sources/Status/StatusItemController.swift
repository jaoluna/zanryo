import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusBar: NSStatusBar
    private let statusItem: NSStatusItem
    private let onToggle: (NSStatusBarButton) -> Void
    private var isInvalidated = false

    var button: NSStatusBarButton? {
        statusItem.button
    }

    init(
        statusBar: NSStatusBar = .system,
        onToggle: @escaping (NSStatusBarButton) -> Void
    ) {
        self.statusBar = statusBar
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        self.onToggle = onToggle
        super.init()

        button?.target = self
        button?.action = #selector(togglePopover)
        button?.sendAction(on: [.leftMouseUp])
        button?.toolTip = "Zanryo Codex quota"
        update(StatusTitle.make(snapshot: nil))
    }

    func invalidate() {
        guard !isInvalidated else {
            return
        }
        isInvalidated = true
        statusBar.removeStatusItem(statusItem)
    }

    func update(_ title: StatusTitle) {
        button?.attributedTitle = title.attributed
        button?.setAccessibilityLabel(title.accessibilityLabel)
    }

    @objc
    private func togglePopover() {
        guard let button else {
            return
        }
        onToggle(button)
    }
}
