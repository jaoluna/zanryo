import AppKit

enum ProviderAppearance {
    static let claudeAccent = NSColor(srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1)
    static let codexAccent = NSColor(srgbRed: 0xF2 / 255, green: 0xB6 / 255, blue: 0x32 / 255, alpha: 1)

    // The popover is always dark. The system menu bar can be light or dark.
    static let claudeMenuAccent = NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            return NSColor(srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1)
        }
        return NSColor(srgbRed: 0xA0 / 255, green: 0x44 / 255, blue: 0x28 / 255, alpha: 1)
    }
}
