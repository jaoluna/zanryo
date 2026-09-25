import AppKit
import SwiftUI

struct ClaudeUsageView: View {
    @ObservedObject var registry: ProviderRegistry

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 24) {
                if let fiveHour = registry.claudeSnapshot?.fiveHour { window(fiveHour, title: "5 HOURS") }
                if let weekly = registry.claudeSnapshot?.weekly { window(weekly, title: "WEEKLY") }
            }
            if registry.claudeSnapshot == nil {
                Text(registry.claudeIsRefreshing ? "Reading Claude usage…" : "Claude usage unavailable")
                    .font(.system(size: 17, weight: .medium))
            }
            if let error = registry.claudeError {
                Text(error.message).font(.system(size: 12)).foregroundStyle(PopoverColor.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let date = registry.claudeSnapshot?.preferredLimit?.observedAt {
                if registry.claudeSnapshot?.isStale() == true || registry.claudeError != nil {
                    Text("Saved reading · may be outdated")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(PopoverColor.warning)
                }
                Text("Read \(date.formatted(date: .abbreviated, time: .standard))")
                    .font(.system(size: 11)).foregroundStyle(PopoverColor.secondaryForeground)
            }
            Divider().overlay(PopoverColor.divider)
            Text("Independent subscription limits. Each window resets separately.")
                .font(.system(size: 12)).foregroundStyle(PopoverColor.secondaryForeground)
            Text("Source: Claude Code /usage. Background refresh every 5 minutes; no model request.")
                .font(.system(size: 11)).foregroundStyle(PopoverColor.secondaryForeground)
            Spacer(minLength: 0)
            HStack {
                Button("Refresh now") { Task { await registry.refreshClaude(force: true) } }
                    .disabled(!registry.shouldRefreshClaude || registry.claudeIsRefreshing)
                Spacer()
                Button("Trusted folder…", action: chooseFolder)
            }
            Text("Login and folder trust stay in Claude Code. Zanryo never approves them for you.")
                .font(.system(size: 10)).foregroundStyle(PopoverColor.secondaryForeground)
        }
        .padding(18)
        .tint(PopoverColor.claudeAccent)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func window(_ limit: RateLimit, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(PopoverColor.secondaryForeground)
            Text("\(Int(limit.remainingPercent.rounded()))%")
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .foregroundStyle(PopoverColor.claudeAccent)
            Text("remaining").font(.system(size: 12)).foregroundStyle(PopoverColor.secondaryForeground)
            Text("Resets \(limit.resetsAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 11)).foregroundStyle(PopoverColor.secondaryForeground)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

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
