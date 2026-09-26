import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: ZanryoStore
    @ObservedObject var registry: ProviderRegistry

    private var model: PopoverDashboardModel {
        PopoverDashboardModel.make(
            from: store.snapshot,
            isRefreshing: store.isRefreshing
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            divider
            if registry.selectedProvider == .openAI {
                openAIDashboard
            } else if registry.selectedProvider == .claude {
                ClaudeUsageView(registry: registry)
            } else {
                unavailableProviderSurface
            }
        }
        .frame(width: 390, height: 590)
        .background(PopoverColor.background)
        .foregroundStyle(PopoverColor.foreground)
    }

    private var header: some View {
        HStack(spacing: 8) {
            wordmark
                .frame(width: 62, alignment: .leading)

            providerSelectors

            Spacer(minLength: 2)

            if let selectedProvider = registry.selectedProvider {
                Toggle("Show in menu bar", isOn: menuBarBinding(for: selectedProvider))
                    .tint(selectedProvider == .claude ? PopoverColor.claudeAccent : Color.accentColor)
                    .font(.system(size: 9.4, weight: .medium))
                    .fixedSize()
                    .accessibilityLabel("Show \(selectedProvider.displayName) in the menu bar")
            }

            Text(headerStatusText.uppercased())
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(PopoverColor.secondaryForeground)
                .accessibilityLabel(headerStatusAccessibilityText)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            if registry.selectedProvider == .claude ? registry.claudeIsRefreshing : store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .tint(PopoverColor.secondaryForeground)
                    .accessibilityLabel(model.headerAccessibilityText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var headerStatusText: String {
        if registry.selectedProvider == .claude {
            if registry.claudeIsRefreshing { return "Refreshing" }
            if let snapshot = registry.claudeSnapshot { return registry.claudeError != nil || snapshot.isStale() ? "Saved" : "Updated" }
        }
        guard registry.selectedProvider == .openAI else {
            return registry.selectedProvider == nil ? "No provider" : "Unavailable"
        }
        if !store.isRefreshing, store.lastError != nil || store.snapshot?.quota.isStale() == true { return "Saved" }
        return model.headerText
    }

    private var headerStatusAccessibilityText: String {
        guard let selectedProvider = registry.selectedProvider else {
            return "No supported provider is installed."
        }
        guard selectedProvider == .openAI else {
            return "\(selectedProvider.displayName). \(headerStatusText)."
        }
        if headerStatusText == "Saved" { return "Saved Codex quota. Refresh needed." }
        return model.headerAccessibilityText
    }

    @ViewBuilder
    private var wordmark: some View {
        if let wordmarkImage {
            Image(nsImage: wordmarkImage)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: 17)
                .foregroundStyle(PopoverColor.foreground)
                .accessibilityLabel(model.wordmarkAccessibilityLabel)
                .accessibilityAddTraits(.isHeader)
        } else {
            Text("ZANRYO")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(PopoverColor.foreground)
                .accessibilityLabel(model.wordmarkAccessibilityLabel)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var wordmarkImage: NSImage? {
        guard let url = Bundle.main.url(
            forResource: "zanryo-wordmark",
            withExtension: "png"
        ) else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    private var providerSelectors: some View {
        HStack(spacing: 4) {
            ForEach(registry.installedProviders, id: \.self) { provider in
                Button {
                    registry.select(provider)
                    if provider == .claude { Task { await registry.refreshClaude() } }
                } label: {
                    providerGlyph(for: provider)
                        .frame(width: 22, height: 22)
                        .background(
                            registry.selectedProvider == provider
                                ? PopoverColor.forecastSurface
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show \(provider.displayName) details")
                .accessibilityAddTraits(registry.selectedProvider == provider ? .isSelected : [])
            }
        }
    }

    private func menuBarBinding(for provider: ProviderId) -> Binding<Bool> {
        Binding(
            get: { registry.isEnabled(provider) },
            set: { registry.setEnabled($0, for: provider) }
        )
    }

    @ViewBuilder
    private func providerGlyph(for provider: ProviderId) -> some View {
        if let image = glyphImage(for: provider) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(provider == .claude ? PopoverColor.claudeAccent : PopoverColor.foreground)
                .padding(2.5)
        } else {
            Text(provider == .openAI ? "O" : "C")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(provider == .claude ? PopoverColor.claudeAccent : PopoverColor.foreground)
        }
    }

    private func glyphImage(for provider: ProviderId) -> NSImage? {
        guard let url = Bundle.main.url(forResource: provider.glyphResourceName, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private var openAIDashboard: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    QuotaStripView(provider: model.account.plan == "Unknown" ? "Codex" : "Codex · \(model.account.plan)",
                        windows: codexWindows, accent: PopoverColor.accent,
                        emptyText: store.isRefreshing ? "Reading Codex usage…" : "Codex usage unavailable")
                    divider
                    WeeklyChartView(timeline: .init(series: codexOutlook.series, reset: store.snapshot?.quota.weekly.resetsAt),
                        pace: codexOutlook.pace, accent: PopoverColor.accent, provider: "Codex")
                    divider
                    OutlookMetricsView(rows: codexOutlook.rows, explanation: codexOutlook.explanation)
                }
            }
            divider
            footer
        }
    }

    private var codexOutlook: WeeklyOutlookModel {
        let snapshot = store.snapshot
        return .make(weekly: snapshot?.quota.weekly, report: snapshot?.forecast,
                     isStale: store.lastError != nil || snapshot?.quota.isStale() == true)
    }

    private var codexWindows: [QuotaStripView.Window] {
        guard let quota = store.snapshot?.quota else { return [] }
        var result: [QuotaStripView.Window] = []
        if let five = quota.currentFiveHour(now: Date()) { result.append(.init(title: "5 hours", limit: five)) }
        result.append(.init(title: "Weekly", limit: quota.weekly))
        if let spark = quota.currentOptional(quota.spark, now: Date()) { result.append(.init(title: "Spark", limit: spark)) }
        return result
    }

    private var unavailableProviderSurface: some View {
        VStack(alignment: .leading, spacing: 10) {
            Spacer(minLength: 24)

            Text(unavailableProviderTitle)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(PopoverColor.secondaryForeground)

            Text(unavailableProviderDetail)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(PopoverColor.foreground)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(unavailableProviderTitle). \(unavailableProviderDetail)")
    }

    private var unavailableProviderTitle: String {
        guard let selectedProvider = registry.selectedProvider else {
            return "NO SUPPORTED PROVIDER FOUND"
        }
        return "\(selectedProvider.displayName.uppercased()) DATA UNAVAILABLE"
    }

    private var unavailableProviderDetail: String {
        guard registry.selectedProvider != nil else {
            return "Install Codex or Claude, then reopen Zanryo."
        }
        return "Quota collection is not available for this provider yet."
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if let error = store.lastError {
                    Text(error.message)
                        .foregroundStyle(PopoverColor.warning)
                        .accessibilityLabel(model.refreshErrorAccessibilityLabel(for: error.message))
                } else {
                    Text(store.snapshot?.quota.isStale() == true ? "Saved data · refresh needed" : model.footerText)
                        .foregroundStyle(PopoverColor.secondaryForeground)
                }
            }
            .font(.caption)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(model.footerActionTitle) {
                Task { await store.refresh() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.isRefreshing)
            .accessibilityLabel(model.footerActionTitle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private var divider: some View {
        Divider()
            .overlay(PopoverColor.divider)
    }
}

enum PopoverColor {
    static let claudeAccent = Color(nsColor: ProviderAppearance.claudeAccent)
    static let background = Color(red: 12 / 255, green: 14 / 255, blue: 16 / 255)
    static let forecastSurface = Color(red: 22 / 255, green: 25 / 255, blue: 29 / 255)
    static let foreground = Color(red: 248 / 255, green: 243 / 255, blue: 232 / 255)
    static let secondaryForeground = Color(red: 176 / 255, green: 182 / 255, blue: 193 / 255)
    static let chartMuted = Color(red: 121 / 255, green: 128 / 255, blue: 139 / 255)
    static let chartSol = Color(red: 242 / 255, green: 182 / 255, blue: 50 / 255)
    static let chartTerra = Color(red: 71 / 255, green: 143 / 255, blue: 255 / 255)
    static let chartLuna = Color(red: 148 / 255, green: 156 / 255, blue: 170 / 255)
    static let chartModel55 = Color(red: 78 / 255, green: 201 / 255, blue: 128 / 255)
    static let chartDepletion = Color(red: 255 / 255, green: 91 / 255, blue: 91 / 255)
    static let chartGrid = Color.white.opacity(0.10)
    static let chartSurface = Color.black.opacity(0.14)
    static let chartForecastFill = Color(red: 255 / 255, green: 91 / 255, blue: 91 / 255).opacity(0.13)
    static let accent = Color(nsColor: ProviderAppearance.codexAccent)
    static let divider = Color.white.opacity(0.12)
    static let warning = Color(red: 255 / 255, green: 163 / 255, blue: 163 / 255)
}
