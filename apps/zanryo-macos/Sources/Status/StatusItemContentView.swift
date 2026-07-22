import AppKit

@MainActor
final class StatusItemContentView: NSView {
    struct TailLayout: Equatable {
        let headWidth: CGFloat
        let middleWidth: CGFloat
        let tipWidth: CGFloat

        var totalWidth: CGFloat {
            headWidth + middleWidth + tipWidth
        }
    }

    private enum Metrics {
        static let height: CGFloat = 20
        static let headWidth: CGFloat = 34
        static let tipWidth: CGFloat = 13
        static let sourceTailWidth: CGFloat = 103
        static let glyphSize: CGFloat = 16
    }

    private let bodyImage = StatusItemContentView.tailImage(named: "zanryo-status-body")
    private let tipImage = StatusItemContentView.tailImage(named: "zanryo-status-tip")
    private let moduleStack = NSStackView()
    private var moduleSize = NSSize.zero
    private(set) var presentation = StatusPresentation(modules: [])

    var tailLayout: TailLayout {
        TailLayout(
            headWidth: Metrics.headWidth,
            middleWidth: ceil(moduleSize.width),
            tipWidth: Metrics.tipWidth
        )
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true
        setAccessibilityElement(true)

        moduleStack.orientation = .horizontal
        moduleStack.alignment = .centerY
        moduleStack.spacing = 8
        moduleStack.translatesAutoresizingMaskIntoConstraints = false
        moduleStack.setAccessibilityElement(false)
        addSubview(moduleStack)

        update(StatusPresentation(modules: []))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(tailLayout.totalWidth), height: Metrics.height)
    }

    override func layout() {
        super.layout()
        let bounds = self.bounds
        moduleStack.frame = NSRect(
            x: tailLayout.headWidth,
            y: floor((bounds.height - moduleSize.height) / 2),
            width: moduleSize.width,
            height: moduleSize.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let layout = tailLayout
        let originY = floor((bounds.height - Metrics.height) / 2)
        let tailFrame = NSRect(x: 0, y: originY, width: layout.totalWidth, height: Metrics.height)

        drawTailLayer(bodyImage, in: tailFrame, layout: layout, tint: .labelColor)
        drawTailLayer(tipImage, in: tailFrame, layout: layout, tint: nil)
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
        moduleSize = moduleStack.fittingSize

        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    private func moduleView(for module: ProviderModule) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 3
        stack.setAccessibilityElement(false)

        let glyph = NSImageView()
        glyph.image = Self.glyphImage(named: module.provider.statusGlyph)
        glyph.contentTintColor = .labelColor
        glyph.imageScaling = .scaleProportionallyDown
        glyph.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            glyph.widthAnchor.constraint(equalToConstant: Metrics.glyphSize),
            glyph.heightAnchor.constraint(equalToConstant: Metrics.glyphSize),
        ])
        glyph.setAccessibilityElement(false)
        stack.addArrangedSubview(glyph)

        let label = NSTextField(labelWithString: module.text)
        label.font = .monospacedDigitSystemFont(ofSize: 12.25, weight: .semibold)
        label.textColor = module.provider == .openAI
            ? NSColor(srgbRed: 0xF2 / 255, green: 0xB6 / 255, blue: 0x32 / 255, alpha: 1)
            : .labelColor
        label.lineBreakMode = .byClipping
        label.setAccessibilityElement(false)
        stack.addArrangedSubview(label)

        return stack
    }

    private func drawTailLayer(
        _ image: NSImage?,
        in tailFrame: NSRect,
        layout: TailLayout,
        tint: NSColor?
    ) {
        guard let image else { return }
        let sourceHead = NSRect(x: 0, y: 0, width: layout.headWidth, height: Metrics.height)
        let sourceMiddle = NSRect(
            x: layout.headWidth,
            y: 0,
            width: Metrics.sourceTailWidth - layout.headWidth - layout.tipWidth,
            height: Metrics.height
        )
        let sourceTip = NSRect(
            x: Metrics.sourceTailWidth - layout.tipWidth,
            y: 0,
            width: layout.tipWidth,
            height: Metrics.height
        )
        let destinationHead = NSRect(
            x: tailFrame.minX,
            y: tailFrame.minY,
            width: layout.headWidth,
            height: Metrics.height
        )
        let destinationMiddle = NSRect(
            x: destinationHead.maxX,
            y: tailFrame.minY,
            width: layout.middleWidth,
            height: Metrics.height
        )
        let destinationTip = NSRect(
            x: destinationMiddle.maxX,
            y: tailFrame.minY,
            width: layout.tipWidth,
            height: Metrics.height
        )

        drawTailSegment(image, source: sourceHead, destination: destinationHead, tint: tint)
        if layout.middleWidth > 0 {
            drawTailSegment(image, source: sourceMiddle, destination: destinationMiddle, tint: tint)
        }
        drawTailSegment(image, source: sourceTip, destination: destinationTip, tint: tint)
    }

    private func drawTailSegment(
        _ image: NSImage,
        source: NSRect,
        destination: NSRect,
        tint: NSColor?
    ) {
        image.draw(
            in: destination,
            from: source,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: nil
        )
        guard let tint else { return }

        NSGraphicsContext.saveGraphicsState()
        tint.setFill()
        destination.fill(using: .sourceIn)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func tailImage(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.size = NSSize(width: Metrics.sourceTailWidth, height: Metrics.height)
        return image
    }

    private static func glyphImage(named name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.isTemplate = true
        image.size = NSSize(width: Metrics.glyphSize, height: Metrics.glyphSize)
        return image
    }
}

private extension ProviderId {
    var statusGlyph: String {
        glyphResourceName
    }

    var statusName: String {
        displayName
    }
}
