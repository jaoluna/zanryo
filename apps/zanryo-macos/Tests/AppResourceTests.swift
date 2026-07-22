import AppKit
import CoreGraphics
import ImageIO
import XCTest

final class AppResourceTests: XCTestCase {
    func testWordmarkResourceIsBundledWithTransparentAlpha() throws {
        let appBundle = try applicationBundle()

        let wordmark = appBundle.url(
            forResource: "zanryo-wordmark",
            withExtension: "png"
        )
        let wordmarkURL = try XCTUnwrap(
            wordmark,
            "The popover header loads the dragonized Zanryo wordmark from the app bundle."
        )
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(wordmarkURL as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

        XCTAssertTrue(
            image.alphaInfo != .none
                && image.alphaInfo != .noneSkipFirst
                && image.alphaInfo != .noneSkipLast,
            "The wordmark must keep transparency so the popover header does not render a solid block."
        )
    }

    func testStatusTailLayersAreBundledAtMenuBarHeight() throws {
        let appBundle = try applicationBundle()

        for resource in ["zanryo-status-body", "zanryo-status-tip"] {
            let imageURL = try XCTUnwrap(
                appBundle.url(forResource: resource, withExtension: "png"),
                "The \(resource) layer must be present in the application bundle."
            )
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(imageURL as CFURL, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

            XCTAssertTrue(hasAlpha(image), "The \(resource) layer must preserve alpha.")
            XCTAssertGreaterThan(image.width, image.height)
            XCTAssertLessThanOrEqual(image.height, 54, "3x art must be compact enough for an 18pt status ornament.")
        }
    }

    func testStatusTailBodyIsTemplateCompatibleAndTipContainsZanryoYellow() throws {
        let appBundle = try applicationBundle()
        let body = try image(named: "zanryo-status-body", in: appBundle)
        let tip = try image(named: "zanryo-status-tip", in: appBundle)

        XCTAssertTrue(isMonochromeMask(body), "The body layer must be tintable as a template image.")
        XCTAssertTrue(
            containsZanryoYellow(tip),
            "The separate tail-tip layer must retain Zanryo yellow instead of becoming a white mask."
        )
    }

    func testRecognizableProviderGlyphsAreBundledAsTransparentMonochromeMarks() throws {
        let appBundle = try applicationBundle()

        for resource in ["openai-provider-glyph", "claude-provider-glyph"] {
            let glyph = try image(named: resource, in: appBundle)
            XCTAssertTrue(hasAlpha(glyph), "The \(resource) mark must preserve transparency.")
            XCTAssertTrue(isMonochromeMask(glyph), "The \(resource) mark must remain tintable in both status-bar appearances.")
            XCTAssertEqual(glyph.width, glyph.height)
            XCTAssertTrue(
                hasTransparentBackgroundAndVisibleMark(glyph),
                "The \(resource) mark must not turn its full square canvas into a template block."
            )
        }
    }

    func testApplicationIconIsRegisteredAndUsesApprovedDragonArt() throws {
        let appBundle = try applicationBundle()
        XCTAssertEqual(appBundle.object(forInfoDictionaryKey: "CFBundleIconName") as? String, "AppIcon")

        let assetCatalog = try XCTUnwrap(appBundle.url(forResource: "Assets", withExtension: "car"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: assetCatalog.path))

        let icon = NSWorkspace.shared.icon(forFile: appBundle.bundlePath)
        var proposedRect = NSRect(origin: .zero, size: icon.size)
        let iconImage = try XCTUnwrap(
            icon.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
        )
        XCTAssertTrue(
            containsZanryoYellow(iconImage),
            "The registered application icon must resolve to the approved dragon-Z rather than the generic app icon."
        )
    }

    private func applicationBundle() throws -> Bundle {
        let testBundle = Bundle(for: Self.self)
        let appBundleURL = testBundle.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try XCTUnwrap(Bundle(url: appBundleURL))
    }

    private func image(named name: String, in bundle: Bundle) throws -> CGImage {
        let imageURL = try XCTUnwrap(bundle.url(forResource: name, withExtension: "png"))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(imageURL as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func hasAlpha(_ image: CGImage) -> Bool {
        image.alphaInfo != .none
            && image.alphaInfo != .noneSkipFirst
            && image.alphaInfo != .noneSkipLast
    }

    private func isMonochromeMask(_ image: CGImage) -> Bool {
        guard let bytes = normalizedRGBABytes(for: image) else { return false }
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let red = bytes[offset]
            let green = bytes[offset + 1]
            let blue = bytes[offset + 2]
            if red != green || green != blue {
                return false
            }
        }
        return true
    }

    private func containsZanryoYellow(_ image: CGImage) -> Bool {
        guard let bytes = normalizedRGBABytes(for: image) else { return false }
        return stride(from: 0, to: bytes.count, by: 4).contains { offset in
            let red = Int(bytes[offset])
            let green = Int(bytes[offset + 1])
            let blue = Int(bytes[offset + 2])
            return red > 180 && green > 120 && green < 220 && blue < 90
        }
    }

    private func hasTransparentBackgroundAndVisibleMark(_ image: CGImage) -> Bool {
        guard let bytes = normalizedRGBABytes(for: image) else { return false }
        let alphaValues = stride(from: 3, to: bytes.count, by: 4).map { bytes[$0] }
        guard let maximumAlpha = alphaValues.max(), maximumAlpha > 200 else { return false }

        let cornerOffsets = [
            3,
            (image.width - 1) * 4 + 3,
            (image.height - 1) * image.width * 4 + 3,
            ((image.height * image.width) - 1) * 4 + 3,
        ]
        return cornerOffsets.allSatisfy { bytes[$0] < 8 }
    }

    private func normalizedRGBABytes(for image: CGImage) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: &bytes,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }
}
