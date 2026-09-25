import AppKit
import SwiftUI
import XCTest
@testable import Zanryo

@MainActor
final class ProviderAppearanceTests: XCTestCase {
    func testProviderAccentsKeepCodexYellowAndClaudeTerracotta() throws {
        try assertRGB(ProviderAppearance.codexAccent, 0xF2, 0xB6, 0x32)
        try assertRGB(ProviderAppearance.claudeAccent, 0xD9, 0x77, 0x57)
        for (name, rgb) in [(NSAppearance.Name.darkAqua, [0xD9, 0x77, 0x57]),
                            (NSAppearance.Name.aqua, [0xA0, 0x44, 0x28])] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                do { try assertRGB(ProviderAppearance.claudeMenuAccent, rgb[0], rgb[1], rgb[2]) }
                catch { XCTFail("Unable to resolve provider color: \(error)") }
            }
        }
    }

    func testBothMenuModulesKeepValuesAndRenderInBothAppearances() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let view = StatusItemContentView(frame: .zero)
            view.appearance = NSAppearance(named: name)
            let presentation = StatusPresentation(modules: [
                ProviderModule(provider: .openAI, remainingPercent: 26, reset: "5d 3h", resetSpoken: "5 days 3 hours", isStale: false),
                ProviderModule(provider: .claude, remainingPercent: 100, reset: "3h", resetSpoken: "3 hours", isStale: false),
            ])
            view.update(presentation)
            view.frame.size = view.intrinsicContentSize
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.presentation, presentation)
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let attachment = XCTAttachment(image: NSImage(cgImage: try XCTUnwrap(bitmap.cgImage), size: view.bounds.size))
            attachment.name = "provider-menu-\(name.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func assertRGB(_ color: NSColor, _ red: Int, _ green: Int, _ blue: Int) throws {
        let rgb = try XCTUnwrap(color.usingColorSpace(.sRGB))
        XCTAssertEqual(rgb.redComponent, CGFloat(red) / 255, accuracy: 0.001)
        XCTAssertEqual(rgb.greenComponent, CGFloat(green) / 255, accuracy: 0.001)
        XCTAssertEqual(rgb.blueComponent, CGFloat(blue) / 255, accuracy: 0.001)
    }

    func testClaudePopoverRendersIndependentWindowsAndUnavailableState() async throws {
        let suite = "ProviderAppearanceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()
        let snapshot = ClaudeUsageSnapshot(provider: .claude,
            fiveHour: RateLimit(kind: .fiveHour, limitId: "claude_five_hour", remainingPercent: 100,
                               resetsAt: now.addingTimeInterval(10800), observedAt: now),
            weekly: RateLimit(kind: .weekly, limitId: "claude_weekly", remainingPercent: 97,
                             resetsAt: now.addingTimeInterval(432000), observedAt: now), freshness: .fresh)
        for hasData in [true, false] {
            let registry = ProviderRegistry(discoverer: StyleDiscovery(), preferences: ProviderPreferences(defaults: defaults))
            await registry.discover()
            registry.select(.claude)
            registry.updateClaude(snapshot: hasData ? snapshot : nil, error: nil, isRefreshing: false)
            let store = ZanryoStore(provider: StyleDashboard())
            let host = NSHostingView(rootView: PopoverView(store: store, registry: registry))
            host.frame = NSRect(x: 0, y: 0, width: 390, height: 590)
            host.appearance = NSAppearance(named: .darkAqua)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            // Give SwiftUI's scheduled update a turn before capturing an offscreen view.
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let colors = Set(stride(from: 0, to: bitmap.pixelsHigh, by: 8).flatMap { y in
                stride(from: 0, to: bitmap.pixelsWide, by: 8).compactMap { x in bitmap.colorAt(x: x, y: y)?.description }
            })
            XCTAssertGreaterThan(colors.count, 10, "A blank offscreen capture is not visual evidence.")
            // Freeze encoded pixels now; don't let a deferred NSImage draw outlive its host.
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = hasData ? "claude-style-fresh" : "claude-style-unavailable"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(host.bounds.height, 590)
        }
    }
}

private actor StyleDiscovery: ProviderDiscovering {
    func discoverProviders() async throws -> [ProviderInstallation] {
        [.init(provider: .openAI, executablePath: "/fixture/codex"),
         .init(provider: .claude, executablePath: "/fixture/claude")]
    }
}

private actor StyleDashboard: DashboardProviding {
    func cached() async throws -> DashboardSnapshot? { nil }
    func refresh() async throws -> DashboardSnapshot {
        throw DisplayError(code: "fixture", message: "No live collection in visual tests")
    }
}
