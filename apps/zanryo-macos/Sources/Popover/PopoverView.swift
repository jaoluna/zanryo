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
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                header
                divider
                quotaStrip
                divider
                forecastSurface
                divider
                decisionRows
                divider
                footer
            }
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .frame(width: 360, height: 500)
        .background(PopoverColor.background)
        .foregroundStyle(PopoverColor.foreground)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("zanryo-wordmark")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: 17)
                .accessibilityLabel(model.wordmarkAccessibilityLabel)
                .accessibilityAddTraits(.isHeader)

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
        .padding(.vertical, 14)
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
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quota.accessibilityDescription)
    }

    private func quotaValueFont(for quota: PopoverDashboardModel.QuotaDisplay) -> Font {
        .system(
            size: quota.isAvailable ? 30 : 16,
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
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.loadingWeeklyAccessibilityLabel)
    }

    private var forecastSurface: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("CURRENT CYCLE + FORECAST")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PopoverColor.accent)

                Spacer(minLength: 12)

                Text(model.forecastPaceText)
                    .font(.system(size: 11, weight: .medium))
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(PopoverColor.foreground)
                    .frame(maxWidth: 132, alignment: .trailing)
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
        .padding(.vertical, 13)
        .background(PopoverColor.forecastSurface)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.forecastSectionAccessibilityLabel)
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
                .padding(.vertical, 9)

                if index < model.decisionRows.count - 1 {
                    Divider()
                        .overlay(PopoverColor.divider)
                        .padding(.leading, 16)
                }
            }
        }
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
        .padding(.vertical, 11)
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
    static let accent = Color(red: 242 / 255, green: 182 / 255, blue: 50 / 255)
    static let divider = Color.white.opacity(0.12)
    static let warning = Color(red: 255 / 255, green: 163 / 255, blue: 163 / 255)
}
