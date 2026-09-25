import AppKit
import SwiftUI

struct ClaudeUsageView: View {
    @ObservedObject var registry: ProviderRegistry
    private var model: ClaudeDashboardModel {
        .make(snapshot: registry.claudeSnapshot, hasError: registry.claudeError != nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    quotaStrip
                    divider
                    chartSection
                    divider
                    metricRows
                    Text(model.explanation).font(.system(size: 10.2, weight: .medium))
                        .foregroundStyle(PopoverColor.secondaryForeground)
                        .padding(.horizontal, 16).padding(.vertical, 8)
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

    private var quotaStrip: some View {
        HStack(spacing: 0) {
            if let five = registry.claudeSnapshot?.fiveHour { window(five, title: "5 HOURS REMAINING") }
            if registry.claudeSnapshot?.fiveHour != nil && registry.claudeSnapshot?.weekly != nil {
                divider.padding(.vertical, 12)
            }
            if let weekly = registry.claudeSnapshot?.weekly { window(weekly, title: "WEEKLY REMAINING") }
            if registry.claudeSnapshot == nil {
                Text(registry.claudeIsRefreshing ? "Reading Claude usage…" : "Claude usage unavailable")
                    .font(.system(size: 16, weight: .medium)).padding(16)
            }
        }.fixedSize(horizontal: false, vertical: true)
    }

    private func window(_ limit: RateLimit, title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 9.4, weight: .semibold, design: .monospaced))
                .foregroundStyle(PopoverColor.secondaryForeground)
            Text("\(Int(limit.remainingPercent.rounded()))%")
                .font(.system(size: 28, weight: .semibold, design: .monospaced))
                .foregroundStyle(PopoverColor.claudeAccent)
            Text("Resets \(limit.resetsAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 9.4)).foregroundStyle(PopoverColor.secondaryForeground)
                .fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("WEEKLY HISTORY").font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PopoverColor.claudeAccent)
                Spacer(minLength: 4)
                Text(model.pace).font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(PopoverColor.secondaryForeground)
            }
            if model.series.isEmpty {
                Text("No weekly readings yet.").font(.caption)
                    .foregroundStyle(PopoverColor.secondaryForeground).padding(.vertical, 38)
            } else {
                ForecastChartView(series: model.series,
                    accessibilityLabel: "Claude weekly remaining quota. Orange is observed history; red is an estimate and gray is budget pace when available.",
                    observedColor: PopoverColor.claudeAccent, displayDomain: model.domain, onlyAvailableLegends: true)
            }
        }.padding(.horizontal, 16).padding(.vertical, 10)
            .background(PopoverColor.forecastSurface)
    }

    private var metricRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.label).foregroundStyle(PopoverColor.secondaryForeground)
                    Spacer(minLength: 4)
                    Text(row.value).multilineTextAlignment(.trailing)
                }.font(.system(size: 11.5, weight: .medium))
                    .padding(.horizontal, 16).padding(.vertical, 7)
                if index < model.rows.count - 1 { divider.padding(.leading, 16) }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Code /usage · every 5 min")
                    if let date = registry.claudeSnapshot?.preferredLimit?.observedAt {
                        Text("\(model.isStale ? "Saved" : "Read") \(date.formatted(date: .omitted, time: .standard))")
                    }
                }.font(.system(size: 9.5)).foregroundStyle(PopoverColor.secondaryForeground)
                Spacer(minLength: 4)
                Button("Folder…", action: chooseFolder).help("Choose a folder already trusted in Claude Code")
                Button("Refresh") { Task { await registry.refreshClaude(force: true) } }
                    .disabled(!registry.shouldRefreshClaude || registry.claudeIsRefreshing)
            }.controlSize(.small)
            Text("Login and folder trust stay in Claude Code.")
                .font(.system(size: 9)).foregroundStyle(PopoverColor.secondaryForeground)
        }.padding(.horizontal, 16).padding(.vertical, 9)
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
