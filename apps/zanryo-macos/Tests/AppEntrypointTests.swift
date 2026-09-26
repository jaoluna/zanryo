import AppKit
import XCTest
@testable import Zanryo

final class AppEntrypointTests: XCTestCase {
    @MainActor
    func testHostedLaunchDoesNotStartCollectorsOrOpenDefaultDatabase() {
        let delegate = AppDelegate()
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        XCTAssertFalse(delegate.hasStartedCollectors)
    }

    func testAppUsesExplicitAppKitEntrypoint() throws {
        let macOSAppDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let mainEntrypoint = macOSAppDirectory.appendingPathComponent("Sources/App/main.swift")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: mainEntrypoint.path),
            "Zanryo should keep an explicit AppKit main.swift so the menu-bar delegate is installed before the app run loop starts."
        )

        let appDelegate = macOSAppDirectory.appendingPathComponent("Sources/App/AppDelegate.swift")
        let appDelegateSource = try String(contentsOf: appDelegate, encoding: .utf8)
        XCTAssertFalse(
            appDelegateSource.contains("@main"),
            "AppDelegate should be retained by the explicit AppKit entrypoint, not used as the process entrypoint."
        )
    }
}
