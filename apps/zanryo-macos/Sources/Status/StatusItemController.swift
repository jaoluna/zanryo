import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusBar: NSStatusBar
    private let statusItem: NSStatusItem
    private let onAction: (StatusItemAction, NSStatusBarButton, NSEvent?) -> Void
    private let contentView = StatusItemContentView(frame: .zero)
    private var isInvalidated = false

    private(set) var presentation = StatusPresentation(modules: [])

    var contentSize: NSSize {
        contentView.intrinsicContentSize
    }

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
        button?.title = ""
        button?.attributedTitle = NSAttributedString(string: "")
        if let button {
            contentView.frame = button.bounds
            contentView.autoresizingMask = [.width, .height]
            button.addSubview(contentView)
        }
        statusItem.menu = nil
        update(StatusPresentation(modules: []))
    }

    func invalidate() {
        guard !isInvalidated else {
            return
        }
        isInvalidated = true
        statusBar.removeStatusItem(statusItem)
    }

    func update(_ presentation: StatusPresentation) {
        self.presentation = presentation
        contentView.update(presentation)
        statusItem.length = contentView.intrinsicContentSize.width
        button?.setAccessibilityLabel(presentation.accessibilityLabel)
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
