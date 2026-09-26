import AppKit
import SwiftUI

struct ClaudeUsageView: View {
    @ObservedObject var registry: ProviderRegistry
    @State var chartWindow: QuotaChartWindow = .weekly
    private var chartWindows: [QuotaChartWindow] {
        QuotaChartWindow.available(fiveHour: registry.claudeSnapshot?.fiveHour, weekly: registry.claudeSnapshot?.weekly)
    }
    private var activeWindow: QuotaChartWindow { chartWindow.resolved(in: chartWindows) }
    private var chartLimit: RateLimit? {
        activeWindow == .fiveHour ? registry.claudeSnapshot?.fiveHour : registry.claudeSnapshot?.weekly
    }
    private var model: WeeklyOutlookModel {
        .make(snapshot: registry.claudeSnapshot, hasError: registry.claudeError != nil, window: activeWindow)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    QuotaStripView(provider: "Claude", windows: windows, accent: PopoverColor.claudeAccent,
                        emptyText: registry.claudeIsRefreshing ? "Reading Claude usage…" : "Claude usage unavailable")
                    divider
                    WeeklyChartView(timeline: .init(series: model.series, reset: chartLimit?.resetsAt, window: activeWindow),
                        pace: model.pace, accent: PopoverColor.claudeAccent, provider: "Claude",
                        availableWindows: chartWindows, selection: $chartWindow)
                    divider
                    OutlookMetricsView(rows: model.rows, explanation: model.explanation)
                    if let error = registry.claudeError {
                        Text(error.message).font(.system(size: 11)).foregroundStyle(PopoverColor.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 16).padding(.bottom, 8)
                    }
                }
            }
            divider
            footer
        }.tint(PopoverColor.claudeAccent)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var windows: [QuotaStripView.Window] {
        var result: [QuotaStripView.Window] = []
        if let limit = registry.claudeSnapshot?.fiveHour { result.append(.init(title: "5 hours", limit: limit)) }
        if let limit = registry.claudeSnapshot?.weekly { result.append(.init(title: "Weekly", limit: limit)) }
        return result
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Claude Code /usage · every 5 min")
                if let date = registry.claudeSnapshot?.preferredLimit?.observedAt {
                    Text("\(model.isStale ? "Saved" : "Read") \(date.formatted(date: .omitted, time: .standard))")
                }
            }.font(.system(size: 9.5)).foregroundStyle(PopoverColor.secondaryForeground)
            Spacer(minLength: 4)
            Button("Folder…", action: chooseFolder).help("Choose a folder already trusted in Claude Code. Login and trust stay in Claude Code.")
            Button("Refresh") { Task { await registry.refreshClaude(force: true) } }
                .disabled(!registry.shouldRefreshClaude || registry.claudeIsRefreshing)
        }.controlSize(.small).padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var divider: some View { Divider().overlay(PopoverColor.divider) }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder you have already trusted in Claude Code."
        if panel.runModal() == .OK, let path = panel.url?.path {
            UserDefaults.standard.set(path, forKey: "claudeProbeWorkingDirectory")
            Task { await registry.refreshClaude(force: true) }
        }
    }
}

struct OutlookMetricsView: View {
    let rows: [PopoverMetric]
    let explanation: String

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.label).foregroundStyle(PopoverColor.secondaryForeground)
                    Spacer(minLength: 4)
                    Text(row.value).multilineTextAlignment(.trailing)
                }.font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 16).padding(.vertical, 7)
                if index < rows.count - 1 { Divider().overlay(PopoverColor.divider).padding(.leading, 16) }
            }
            Text(explanation).font(.system(size: 10.2, weight: .medium))
                .foregroundStyle(PopoverColor.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.vertical, 9)
        }
    }
}
