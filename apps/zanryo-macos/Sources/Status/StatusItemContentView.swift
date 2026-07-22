import AppKit

@MainActor
final class StatusItemContentView: NSView {
    private enum Metrics {
        static let height: CGFloat = 18
        static let tailWidth: CGFloat = 93
        static let moduleLeading: CGFloat = 21
        static let trailingPadding: CGFloat = 4
    }

    private let bodyImageView = NSImageView()
    private let tipImageView = NSImageView()
    private let moduleStack = NSStackView()
    private(set) var presentation = StatusPresentation(modules: [])

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true
        setAccessibilityElement(true)

        bodyImageView.image = Self.image(named: "zanryo-status-body@2x", isTemplate: true)
        bodyImageView.imageScaling = .scaleAxesIndependently
        bodyImageView.setAccessibilityElement(false)
        addSubview(bodyImageView)

        tipImageView.image = Self.image(named: "zanryo-status-tip@2x", isTemplate: false)
        tipImageView.imageScaling = .scaleAxesIndependently
        tipImageView.setAccessibilityElement(false)
        addSubview(tipImageView)

        moduleStack.orientation = .horizontal
        moduleStack.alignment = .centerY
        moduleStack.spacing = 8
        moduleStack.setAccessibilityElement(false)
        addSubview(moduleStack)

        update(StatusPresentation(modules: []))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        let moduleWidth = moduleStack.fittingSize.width
        let width = max(Metrics.tailWidth, Metrics.moduleLeading + moduleWidth + Metrics.trailingPadding)
        return NSSize(width: ceil(width), height: Metrics.height)
    }

    override func layout() {
        super.layout()
        let bounds = self.bounds
        let tailFrame = NSRect(x: 0, y: 0, width: Metrics.tailWidth, height: Metrics.height)
        bodyImageView.frame = tailFrame
        tipImageView.frame = tailFrame

        let moduleSize = moduleStack.fittingSize
        moduleStack.frame = NSRect(
            x: Metrics.moduleLeading,
            y: floor((bounds.height - moduleSize.height) / 2),
            width: moduleSize.width,
            height: moduleSize.height
        )
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(_ presentation: StatusPresentation) {
        self.presentation = presentation
        setAccessibilityLabel(presentation.accessibilityLabel)

        for view in moduleStack.arrangedSubviews {
            moduleStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for module in presentation.modules {
            moduleStack.addArrangedSubview(moduleView(for: module))
        }

        invalidateIntrinsicContentSize()
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func moduleView(for module: ProviderModule) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 3
        stack.setAccessibilityElement(false)

        let glyph = NSImageView()
        glyph.image = NSImage(
            systemSymbolName: module.provider.statusGlyph,
            accessibilityDescription: module.provider.statusName
        )
        glyph.contentTintColor = .labelColor
        glyph.imageScaling = .scaleProportionallyDown
        glyph.frame.size = NSSize(width: 11, height: 11)
        glyph.setAccessibilityElement(false)
        stack.addArrangedSubview(glyph)

        let label = NSTextField(labelWithString: module.text)
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = module.provider == .openAI
            ? NSColor(srgbRed: 0xF2 / 255, green: 0xB6 / 255, blue: 0x32 / 255, alpha: 1)
            : .labelColor
        label.lineBreakMode = .byClipping
        label.setAccessibilityElement(false)
        stack.addArrangedSubview(label)

        return stack
    }

    private static func image(named name: String, isTemplate: Bool) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.isTemplate = isTemplate
        return image
    }
}

private extension ProviderId {
    var statusGlyph: String {
        switch self {
        case .openAI:
            "circle.hexagongrid"
        case .claude:
            "circle"
        }
    }

    var statusName: String {
        switch self {
        case .openAI:
            "OpenAI"
        case .claude:
            "Claude"
        }
    }
}
