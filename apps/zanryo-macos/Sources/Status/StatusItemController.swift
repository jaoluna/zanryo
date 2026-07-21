import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusBar: NSStatusBar
    private let statusItem: NSStatusItem
    private let onAction: (StatusItemAction, NSStatusBarButton, NSEvent?) -> Void
    private var isInvalidated = false

    var button: NSStatusBarButton? {
        statusItem.button
    }

    init(
        statusBar: NSStatusBar = .system,
        onAction: @escaping (StatusItemAction, NSStatusBarButton, NSEvent?) -> Void
    ) {
        self.statusBar = statusBar
        statusItem = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        self.onAction = onAction
        super.init()

        button?.target = self
        button?.action = #selector(performAction)
        button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button?.toolTip = "Zanryo Codex quota"
        statusItem.menu = nil
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

    func setHighlighted(_ isHighlighted: Bool) {
        button?.highlight(isHighlighted)
    }

    @objc
    private func performAction() {
        guard let button else {
            return
        }
        let event = NSApp.currentEvent
        let action = StatusItemAction.resolve(
            eventType: event?.type,
            modifierFlags: event?.modifierFlags ?? []
        )
        onAction(action, button, event)
    }
}
