import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: ZanryoStore

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
            quotaStrip
            divider
            forecastSurface
            divider
            decisionRows
            metricExplanation
            divider
            footer
        }
        .frame(width: 390, height: 590)
        .background(PopoverColor.background)
        .foregroundStyle(PopoverColor.foreground)
    }

    private var header: some View {
        HStack(spacing: 12) {
            wordmark

            Spacer()

            Text(model.headerText.uppercased())
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(PopoverColor.secondaryForeground)
                .accessibilityLabel(model.headerAccessibilityText)

            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .tint(PopoverColor.secondaryForeground)
                    .accessibilityLabel(model.headerAccessibilityText)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
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

    private var quotaStrip: some View {
        HStack(spacing: 0) {
            if let weekly = model.weekly {
                quotaCell(weekly, valueColor: PopoverColor.accent)
            } else {
                loadingQuotaCell
            }

            Divider()
                .overlay(PopoverColor.divider)
                .padding(.vertical, 12)

            quotaCell(model.spark, valueColor: PopoverColor.foreground)
        }
        .padding(.vertical, 4)
    }

    private func quotaCell(
        _ quota: PopoverDashboardModel.QuotaDisplay,
        valueColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(quota.label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(PopoverColor.secondaryForeground)

            Text(quota.valueText)
                .font(quotaValueFont(for: quota))
                .foregroundStyle(valueColor)
                .lineLimit(1)

            Text("RESET \(quota.reset.uppercased())")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(PopoverColor.secondaryForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quota.accessibilityDescription)
    }

    private func quotaValueFont(for quota: PopoverDashboardModel.QuotaDisplay) -> Font {
        .system(
            size: quota.isAvailable ? 28 : 16,
            weight: quota.isAvailable ? .semibold : .medium,
            design: .monospaced
        )
    }

    private var loadingQuotaCell: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("WEEKLY")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(PopoverColor.secondaryForeground)

            Text("Loading")
                .font(.system(size: 18, weight: .medium, design: .monospaced))
                .foregroundStyle(PopoverColor.secondaryForeground)

            Text("RESET PENDING")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(PopoverColor.secondaryForeground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.loadingWeeklyAccessibilityLabel)
    }

    private var forecastSurface: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("WEEKLY FORECAST")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PopoverColor.accent)

                Spacer(minLength: 12)

                forecastPaceHeader
            }

            if !model.hasForecastProjection {
                Text("Forecast will appear after more history.")
                    .font(.caption)
                    .foregroundStyle(PopoverColor.secondaryForeground)
            }

            if model.forecastSeries.isEmpty {
                Text("Forecast data will appear after quota history is collected.")
                    .font(.caption)
                    .foregroundStyle(PopoverColor.secondaryForeground)
                    .padding(.vertical, 22)
            } else {
                ForecastChartView(
                    series: model.forecastSeries,
                    accessibilityLabel: model.chartAccessibilityLabel
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(PopoverColor.forecastSurface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.forecastSectionAccessibilityLabel)
    }

    private var forecastPaceHeader: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(forecastPaceHeaderTitle.uppercased())
                .font(.system(size: 8.6, weight: .semibold, design: .monospaced))
                .foregroundStyle(PopoverColor.secondaryForeground)

            Text(forecastPaceHeaderValue)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(PopoverColor.foreground)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: 178, alignment: .trailing)
        .accessibilityLabel(model.forecastPaceText.replacingOccurrences(of: "\n", with: ", "))
    }

    private var forecastPaceHeaderTitle: String {
        forecastPaceTextParts.title
    }

    private var forecastPaceHeaderValue: String {
        forecastPaceTextParts.value
    }

    private var forecastPaceTextParts: (title: String, value: String) {
        let parts = model.forecastPaceText
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)

        if parts.count == 2 {
            return (parts[0], parts[1])
        }

        return ("Forecast", model.forecastPaceText)
    }

    private var decisionRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(model.decisionRows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(row.label)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(PopoverColor.secondaryForeground)

                    Spacer(minLength: 12)

                    Text(row.value)
                        .font(.system(size: 12.5, weight: .medium))
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(PopoverColor.foreground)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 7)

                if index < model.decisionRows.count - 1 {
                    Divider()
                        .overlay(PopoverColor.divider)
                        .padding(.leading, 16)
                }
            }
        }
    }

    private var metricExplanation: some View {
        Text("Yellow is observed remaining. Red is the current-pace forecast. Gray is the weekly 100% to 0% budget pace.")
            .font(.system(size: 10.2, weight: .medium))
            .foregroundStyle(PopoverColor.secondaryForeground)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(PopoverColor.forecastSurface.opacity(0.55))
            .accessibilityLabel("Yellow is observed remaining. Red is the current-pace forecast. Gray is the weekly one hundred percent to zero percent budget pace.")
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            Group {
                if let error = store.lastError {
                    Text(error.message)
                        .foregroundStyle(PopoverColor.warning)
                        .accessibilityLabel(model.refreshErrorAccessibilityLabel(for: error.message))
                } else {
                    Text(model.footerText)
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
    static let accent = Color(red: 242 / 255, green: 182 / 255, blue: 50 / 255)
    static let divider = Color.white.opacity(0.12)
    static let warning = Color(red: 255 / 255, green: 163 / 255, blue: 163 / 255)
}
