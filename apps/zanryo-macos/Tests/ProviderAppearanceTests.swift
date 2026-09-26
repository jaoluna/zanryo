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
                ProviderModule(provider: .openAI, remainingPercent: 26, reset: "≈5d23h", resetSpoken: "5 days 22 hours 55 minutes", isStale: false),
                ProviderModule(provider: .claude, remainingPercent: 100, reset: "3h55m", resetSpoken: "3 hours 55 minutes", isStale: false),
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
        for state in ["gpt-weekly-long", "estimated", "flat-history", "flat-projection", "projection", "collecting", "stale", "unavailable"] {
            let snapshot = state.hasPrefix("flat") ? ClaudeDashboardFixture.flatSnapshot(now: now) : state == "unavailable" ? nil : ClaudeDashboardFixture.snapshot(
                now: now, collecting: state == "collecting", stale: state == "stale")
            let registry = ProviderRegistry(discoverer: StyleDiscovery(), preferences: ProviderPreferences(defaults: defaults))
            await registry.discover()
            registry.select(state == "gpt-weekly-long" ? .openAI : .claude)
            registry.updateClaude(snapshot: snapshot, error: nil, isRefreshing: false)
            let store = ZanryoStore(provider: StyleDashboard(snapshot: state == "gpt-weekly-long" ? Self.longWeeklySnapshot(now: now) : nil))
            if state == "gpt-weekly-long" { await store.start() }
            let host = NSHostingView(rootView: PopoverView(store: store, registry: registry,
                initialClaudeChartMode: state.contains("projection") ? .projection : .history))
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
            attachment.name = "claude-dashboard-\(state)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(host.bounds.height, 590)
        }
    }

    private static func longWeeklySnapshot(now: Date) -> DashboardSnapshot {
        DashboardSnapshot(quota: .init(
            weekly: .init(kind: .weekly, limitId: "codex", remainingPercent: 74,
                          resetsAt: now.addingTimeInterval(518_100), observedAt: now),
            spark: .init(kind: .fiveHour, limitId: "spark", remainingPercent: 19,
                         resetsAt: now.addingTimeInterval(9_300), observedAt: now),
            other: [], freshness: .fresh),
            forecast: ClaudeDashboardFixture.snapshot(now: now).weeklyForecast!)
    }
}

private actor StyleDiscovery: ProviderDiscovering {
    func discoverProviders() async throws -> [ProviderInstallation] {
        [.init(provider: .openAI, executablePath: "/fixture/codex"),
         .init(provider: .claude, executablePath: "/fixture/claude")]
    }
}

private actor StyleDashboard: DashboardProviding {
    let snapshot: DashboardSnapshot?
    init(snapshot: DashboardSnapshot? = nil) { self.snapshot = snapshot }
    func cached() async throws -> DashboardSnapshot? { snapshot }
    func refresh() async throws -> DashboardSnapshot {
        if let snapshot { return snapshot }
        throw DisplayError(code: "fixture", message: "No live collection in visual tests")
    }
}
