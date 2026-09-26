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
                ProviderModule(provider: .openAI, remainingPercent: 26, reset: "5d22:55", resetSpoken: "5 days 22 hours 55 minutes", isStale: false),
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
        for state in ["gpt-weekly-only", "gpt-weekly-long", "gpt-three-windows", "gpt-expired-spark", "gpt-stale", "estimated", "flat", "collecting", "stale", "unavailable"] {
            let snapshot = state.hasPrefix("flat") ? ClaudeDashboardFixture.flatSnapshot(now: now) : state == "unavailable" ? nil : ClaudeDashboardFixture.snapshot(
                now: now, collecting: state == "collecting", stale: state == "stale")
            let registry = ProviderRegistry(discoverer: StyleDiscovery(), preferences: ProviderPreferences(defaults: defaults))
            await registry.discover()
            registry.select(state.hasPrefix("gpt") ? .openAI : .claude)
            registry.updateClaude(snapshot: snapshot, error: nil, isRefreshing: false)
            let store = ZanryoStore(provider: StyleDashboard(snapshot: state.hasPrefix("gpt") ? Self.longWeeklySnapshot(now: now, state: state) : nil))
            if state.hasPrefix("gpt") { await store.start() }
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
            attachment.name = "claude-dashboard-\(state)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertEqual(host.bounds.height, 590)
        }
    }

    private static func longWeeklySnapshot(now: Date, state: String) -> DashboardSnapshot {
        let sparkDate = state == "gpt-expired-spark" ? now.addingTimeInterval(-8 * 86400) : now
        return DashboardSnapshot(quota: .init(
            weekly: .init(kind: .weekly, limitId: "codex", remainingPercent: 74,
                          resetsAt: now.addingTimeInterval(518_100), observedAt: now),
            spark: state == "gpt-weekly-only" || state == "gpt-stale" ? nil : .init(kind: .spark, limitId: "spark", remainingPercent: 19,
                         resetsAt: sparkDate.addingTimeInterval(9_300), observedAt: sparkDate),
            other: [], freshness: state == "gpt-stale" ? .stale : .fresh,
            fiveHour: state == "gpt-three-windows" ? .init(kind: .fiveHour, limitId: "codex_primary", remainingPercent: 43,
                resetsAt: now.addingTimeInterval(9_300), observedAt: now) : nil),
            forecast: ClaudeDashboardFixture.snapshot(now: now, resetAfter: 518_100).weeklyForecast!,
            account: .init(planType: .pro, observedAt: now))
    }

    /// Design fixtures only: no account lookup, collection, persistence or plan
    /// inference. A named plan never creates a limit in the production dashboard.
    func testPersonalPlanDesignPreviews() async throws {
        let now = Date(timeIntervalSince1970: 1_790_424_000)
        for plan in PlanDesignPreview.Plan.allCases {
            let host = NSHostingView(rootView: PlanDesignPreview(plan: plan, now: now))
            host.frame = NSRect(x: 0, y: 0, width: 390, height: 640)
            host.appearance = NSAppearance(named: .darkAqua)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(png.count, 10_000, "A blank preview is not evidence")
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = "plan-demo-\(plan.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}

/// Only compiled in the test target. Illustrative balances are never connected
/// to the collector. Plans describe labels/slots, not guaranteed entitlements.
private struct PlanDesignPreview: View {
    enum Plan: String, CaseIterable {
        case free = "codex-free", go = "codex-go", plus = "codex-plus"
        case pro5 = "codex-pro-5x", pro20 = "codex-pro-20x"
        case claudePro = "claude-pro", max5 = "claude-max-5x", max20 = "claude-max-20x"
        var claude: Bool { [Self.claudePro, .max5, .max20].contains(self) }
        var max: Bool { self == .max5 || self == .max20 }
        var name: String {
            switch self {
            case .free: "Free"
            case .go: "Go"
            case .plus: "Plus"
            case .pro5: "Pro 5x"
            case .pro20: "Pro 20x"
            case .claudePro: "Pro"
            case .max5: "Max 5x"
            case .max20: "Max 20x"
            }
        }
    }
    let plan: Plan
    let now: Date
    private var accent: Color { plan.claude ? PopoverColor.claudeAccent : PopoverColor.accent }
    private var provider: String { plan.claude ? "Claude" : "Codex" }
    private var fixture: ClaudeUsageSnapshot { ClaudeDashboardFixture.snapshot(now: now) }
    private var model: WeeklyOutlookModel { .make(snapshot: fixture, hasError: false, now: now) }
    private var windows: [QuotaStripView.Window] {
        // Pro illustrates the weekly-only payload seen locally; other cases
        // illustrate two supplied windows. Production always follows the source.
        if plan == .pro5 || plan == .pro20 { return [.init(title: "Weekly", limit: fixture.weekly!)] }
        return [.init(title: "5 hours", limit: fixture.fiveHour!), .init(title: "Weekly", limit: fixture.weekly!)]
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ZANRYO").font(.system(size: 13, weight: .bold, design: .monospaced)).tracking(2)
                Spacer()
                Text("DESIGN PREVIEW").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(accent)
            }.padding(.horizontal, 16).padding(.vertical, 12)
            Divider()
            QuotaStripView(provider: "\(provider) · \(plan.name)", windows: windows, accent: accent, now: now)
            if plan.claude {
                HStack {
                    Text("Fable").fontWeight(.medium)
                    Spacer()
                    if plan.max {
                        Text("60% of Fable cap left").foregroundStyle(accent)
                    } else {
                        Text("Usage credits").foregroundStyle(PopoverColor.secondaryForeground)
                    }
                }.font(.system(size: 11)).padding(.horizontal, 16)
                Text(plan.max ? "Shares the weekly allowance. Not additional quota." : "Separate paid usage. Not deducted from included limits.")
                    .font(.system(size: 9)).foregroundStyle(PopoverColor.secondaryForeground)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 12)
            }
            Divider()
            WeeklyChartView(timeline: .init(series: model.series, reset: fixture.weekly!.resetsAt),
                pace: model.pace, accent: accent, provider: provider, confidence: "Medium")
            Divider()
            OutlookMetricsView(rows: Array(model.rows.prefix(3)), explanation: "Projection assumes the recorded pace continues.")
            HStack {
                Text("API-equivalent · this month")
                Spacer()
                Text("Not measured").foregroundStyle(PopoverColor.secondaryForeground)
            }.font(.system(size: 10)).padding(.horizontal, 16).padding(.vertical, 10)
            Spacer(minLength: 0)
            Divider()
            Text("DEMO DATA · NOT YOUR ACCOUNT")
                .font(.system(size: 9)).foregroundStyle(PopoverColor.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
        }.frame(width: 390, height: 640)
            .background(PopoverColor.background).foregroundStyle(PopoverColor.foreground)
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
