import AppKit

enum StatusItemAction: Equatable {
    case togglePopover
    case showContextMenu

    static func resolve(
        eventType: NSEvent.EventType?,
        modifierFlags: NSEvent.ModifierFlags
    ) -> Self {
        if eventType == .rightMouseUp || modifierFlags.contains(.control) {
            return .showContextMenu
        }
        return .togglePopover
    }
}
