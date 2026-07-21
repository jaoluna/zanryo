import Charts
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: ZanryoStore

    private var model: PopoverDashboardModel {
        PopoverDashboardModel.make(from: store.snapshot)
    }

    var body: some View {
        VStack(spacing: 0) {
            scrollBody
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
        }
        .frame(width: 360)
        .background(PopoverColor.background)
        .foregroundStyle(PopoverColor.foreground)
    }

    @ViewBuilder
    private var scrollBody: some View {
        if model.snapshot == nil {
            loadingState
        } else {
            contentBody
        }
    }

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
                .overlay(PopoverColor.divider)
            Text("Loading Codex quota…")
                .foregroundStyle(PopoverColor.secondaryForeground)
                .font(.system(.body))
            footer
        }
        .padding(16)
    }

    private var contentBody: some View {
        VStack(spacing: 12) {
            header
            Divider()
                .overlay(PopoverColor.divider)
            quotaCard
            forecastCard
            controlsCard
            footer
        }
        .padding(16)
    }

    private var header: some View {
        HStack {
            HStack(spacing: 10) {
                Image("zanryo-wordmark")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: 18)
                    .accessibilityHidden(true)
                Text("Zanryo")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(PopoverColor.accent)
                    .accessibilityHidden(true)
            }
            Spacer()
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .tint(PopoverColor.accent)
            }
        }
    }

    private var quotaCard: some View {
        let snapshot = model.snapshot

        return card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Weekly")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PopoverColor.secondaryForeground)
                    Spacer()
                    if let reset = snapshot?.weeklyResetSpoken {
                        Text("Reset in \(reset)")
                            .font(.caption)
                            .foregroundStyle(PopoverColor.secondaryForeground)
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    Text("\(snapshot?.weeklyPercent ?? 0)%")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(PopoverColor.accent)
                    Text("%")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(PopoverColor.accent)
                    Spacer()
                }

                HStack {
                    Text("Spark")
                        .foregroundStyle(PopoverColor.secondaryForeground)
                    Spacer()
                    Text(snapshot?.sparkPercent ?? "--")
                        .foregroundStyle(PopoverColor.foreground)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }

                if let isFresh = snapshot?.isFresh, !isFresh {
                    Text("Data may be outdated.")
                        .font(.caption)
                        .foregroundStyle(PopoverColor.secondaryForeground)
                }
            }
        }
    }

    private var forecastCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(model.forecastTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PopoverColor.secondaryForeground)
                    Spacer()
                    Text("Confidence: \(model.forecastConfidence)")
                        .font(.caption)
                        .foregroundStyle(PopoverColor.secondaryForeground)
                }

                if model.hasForecastProjection {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.forecastMetrics.indices, id: \.self) { index in
                            let metric = model.forecastMetrics[index]
                            HStack {
                                Text(metric.label)
                                    .foregroundStyle(PopoverColor.secondaryForeground)
                                Spacer()
                                Text(metric.value)
                                    .font(.system(size: 14, weight: .medium, design: .rounded))
                                    .foregroundStyle(PopoverColor.foreground)
                            }
                            .font(.system(size: 12.5))
                        }
                    }
                } else {
                    if let metric = model.forecastMetrics.first {
                        Text(metric.value)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(PopoverColor.secondaryForeground)
                    }
                }

                if !model.forecastSeries.isEmpty {
                    forecastChart
                }
            }
        }
    }

    private var forecastChart: some View {
        Chart {
            let observed = model.forecastSeries.filter { $0.kind == .observed }
            if !observed.isEmpty {
                ForEach(Array(observed.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Time", point.at),
                        y: .value("Remaining", point.remainingPercent)
                    )
                    .foregroundStyle(PopoverColor.foreground)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("Time", point.at),
                        y: .value("Remaining", point.remainingPercent)
                    )
                    .symbolSize(18)
                    .foregroundStyle(PopoverColor.foreground)
                }
            }

            let forecast = model.forecastSeries.filter { $0.kind == .forecast }
            if !forecast.isEmpty {
                ForEach(Array(forecast.enumerated()), id: \.offset) { _, point in
                    AreaMark(
                        x: .value("Time", point.at),
                        yStart: .value("Low", point.lowUncertainty ?? point.remainingPercent),
                        yEnd: .value("High", point.highUncertainty ?? point.remainingPercent)
                    )
                    .foregroundStyle(PopoverColor.accent.opacity(0.15))

                    LineMark(
                        x: .value("Time", point.at),
                        y: .value("Remaining", point.remainingPercent)
                    )
                    .foregroundStyle(PopoverColor.accent)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("Time", point.at),
                        y: .value("Remaining", point.remainingPercent)
                    )
                    .symbolSize(18)
                    .foregroundStyle(PopoverColor.accent)
                }
            }

            let sustainable = model.forecastSeries.filter { $0.kind == .sustainable }
            if !sustainable.isEmpty {
                ForEach(Array(sustainable.enumerated()), id: \.offset) { _, point in
                    LineMark(
                        x: .value("Time", point.at),
                        y: .value("Remaining", point.remainingPercent)
                    )
                    .foregroundStyle(PopoverColor.softWhite)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    PointMark(
                        x: .value("Time", point.at),
                        y: .value("Remaining", point.remainingPercent)
                    )
                    .symbolSize(18)
                    .foregroundStyle(PopoverColor.softWhite)
                }
            }
        }
        .chartYScale(domain: 0...100)
        .frame(height: 140)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3))
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                AxisGridLine()
                AxisValueLabel()
            }
        }
    }

    private var controlsCard: some View {
        card {
            VStack(spacing: 10) {
                HStack {
                    Text("API spend")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PopoverColor.secondaryForeground)
                    Spacer()
                    Text(model.apiSpendText)
                        .foregroundStyle(PopoverColor.secondaryForeground)
                        .font(.system(size: 16, weight: .medium))
                }

                HStack {
                    Text("Theme")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PopoverColor.secondaryForeground)
                    Spacer()
                    Text(model.themeText)
                        .foregroundStyle(PopoverColor.secondaryForeground)
                }

                Button("Settings") {}
                    .buttonStyle(.borderedProminent)
                    .disabled(true)
                    .controlSize(.mini)
            }
        }
    }

    private var footer: some View {
        HStack {
            if let error = store.lastError {
                Text(error.message)
                    .font(.caption)
                    .foregroundStyle(PopoverColor.warning)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Manual refresh only.")
                    .font(.caption)
                    .foregroundStyle(PopoverColor.secondaryForeground)
            }

            Spacer()

            Button("Refresh") {
                Task { await store.refresh() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(store.isRefreshing)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(PopoverColor.card)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(PopoverColor.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }

}

enum PopoverColor {
    static let background = Color(red: 12 / 255, green: 14 / 255, blue: 16 / 255)
    static let card = Color(red: 22 / 255, green: 25 / 255, blue: 29 / 255)
    static let foreground = Color(red: 248 / 255, green: 243 / 255, blue: 232 / 255)
    static let softWhite = Color(red: 244 / 255, green: 248 / 255, blue: 255 / 255)
    static let accent = Color(red: 242 / 255, green: 182 / 255, blue: 50 / 255)
    static let secondaryForeground = Color(red: 176 / 255, green: 182 / 255, blue: 193 / 255)
    static let divider = Color.white.opacity(0.12)
    static let border = Color.white.opacity(0.06)
    static let warning = Color(red: 255 / 255, green: 163 / 255, blue: 163 / 255)
}
