import CoreGraphics
import ImageIO
import XCTest

final class AppResourceTests: XCTestCase {
    func testWordmarkResourceIsBundledWithTransparentAlpha() throws {
        let testBundle = Bundle(for: Self.self)
        let appBundleURL = testBundle.bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appBundle = try XCTUnwrap(Bundle(url: appBundleURL))

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
}
