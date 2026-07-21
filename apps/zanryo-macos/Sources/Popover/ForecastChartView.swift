import Charts
import SwiftUI

struct ForecastChartView: View {
    let series: [PopoverForecastPoint]
    let accessibilityLabel: String

    private var observed: [PopoverForecastPoint] {
        series.filter { $0.kind == .observed }
    }

    private var forecast: [PopoverForecastPoint] {
        series.filter { $0.kind == .forecast }
    }

    private var sustainable: [PopoverForecastPoint] {
        series.filter { $0.kind == .sustainable }
    }

    var body: some View {
        VStack(spacing: 6) {
            Chart {
                ForEach(observed, id: \.at) { point in
                    LineMark(
                        x: .value("Time", point.at),
                        y: .value("Remaining", point.remainingPercent)
                    )
                    .foregroundStyle(PopoverColor.foreground)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(
                        StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )
                }

                ForEach(forecast, id: \.at) { point in
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
                    .lineStyle(
                        StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [5, 4])
                    )
                }

                ForEach(sustainable, id: \.at) { point in
                    LineMark(
                        x: .value("Time", point.at),
                        y: .value("Remaining", point.remainingPercent)
                    )
                    .foregroundStyle(PopoverColor.chartMuted)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(
                        StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round, dash: [3, 4])
                    )
                }
            }
            .chartYScale(domain: 0 ... 100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 50, 100]) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(PopoverColor.divider)
                }
            }
            .frame(height: 96)

            HStack {
                Text("START")
                Spacer()
                Text("TODAY")
                Spacer()
                Text("RESET")
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(PopoverColor.secondaryForeground)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}
