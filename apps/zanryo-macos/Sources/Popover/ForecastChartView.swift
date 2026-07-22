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

    private var currentPoint: PopoverForecastPoint? {
        forecast.first ?? observed.last ?? sustainable.first
    }

    private var timelineAxisDates: [Date] {
        guard let range = timelineRange else {
            return []
        }

        let calendar = Calendar.current
        let totalDays = max(
            1,
            Int(ceil(range.end.timeIntervalSince(range.start) / 86_400))
        )
        var dates: [Date] = []

        for offset in 0 ... totalDays {
            guard let date = calendar.date(byAdding: .day, value: offset, to: range.start) else {
                continue
            }

            dates.append(min(date, range.end))
        }

        if dates.last != range.end {
            dates.append(range.end)
        }

        return dates.deduplicated()
    }

    private var timelineRange: (start: Date, end: Date)? {
        let sustainableDates = sustainable.map(\.at)
        if let start = sustainableDates.min(),
           let end = sustainableDates.max(),
           start < end {
            return (start, end)
        }

        let dates = series.map(\.at)
        guard let start = dates.min(), let end = dates.max(), start < end else {
            return nil
        }

        return (start, end)
    }

    private var timelineDomain: ClosedRange<Date> {
        if let range = timelineRange {
            return range.start ... range.end
        }

        let fallbackStart = Date()
        return fallbackStart ... fallbackStart.addingTimeInterval(1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(sustainable, id: \.at) { point in
                    LineMark(
                        x: .value("Time", point.at),
                        y: .value("Remaining", point.remainingPercent)
                    )
                    .foregroundStyle(by: .value("Series", "Budget pace"))
                    .interpolationMethod(.linear)
                    .lineStyle(
                        StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round, dash: [4, 5])
                    )
                }

                if let currentPoint {
                    PointMark(
                        x: .value("Time", currentPoint.at),
                        y: .value("Remaining", currentPoint.remainingPercent)
                    )
                    .symbolSize(32)
                    .foregroundStyle(by: .value("Series", "Observed"))
                }

                ForEach(observed, id: \.at) { point in
                    LineMark(
                        x: .value("Time", point.at),
                        y: .value("Remaining", point.remainingPercent)
                    )
                    .foregroundStyle(by: .value("Series", "Observed"))
                    .interpolationMethod(.monotone)
                    .lineStyle(
                        StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                    )

                    if point.at == observed.last?.at {
                        PointMark(
                            x: .value("Time", point.at),
                            y: .value("Remaining", point.remainingPercent)
                        )
                        .symbolSize(26)
                        .foregroundStyle(by: .value("Series", "Observed"))
                    }
                }

                ForEach(forecast, id: \.at) { point in
                    LineMark(
                        x: .value("Time", point.at),
                        y: .value("Remaining", point.remainingPercent)
                    )
                    .foregroundStyle(by: .value("Series", "Depletion"))
                    .interpolationMethod(.linear)
                    .lineStyle(
                        StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round)
                    )
                }

                if let depletionPoint = forecast.last,
                   depletionPoint.remainingPercent <= 0.01 {
                    PointMark(
                        x: .value("Time", depletionPoint.at),
                        y: .value("Remaining", depletionPoint.remainingPercent)
                    )
                    .symbolSize(22)
                    .foregroundStyle(by: .value("Series", "Depletion"))
                }
            }
            .chartYScale(domain: 0 ... 100)
            .chartXScale(domain: timelineDomain)
            .chartForegroundStyleScale([
                "Observed": PopoverColor.chartSol,
                "Depletion": PopoverColor.chartDepletion,
                "Budget pace": PopoverColor.chartLuna
            ])
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: timelineAxisDates) { value in
                    if let date = value.as(Date.self) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.4))
                            .foregroundStyle(PopoverColor.chartGrid.opacity(0.6))
                        AxisValueLabel(
                            anchor: axisLabelAnchor(date),
                            collisionResolution: .disabled
                        ) {
                            Text(axisLabel(date))
                                .font(.system(size: 7.2, weight: isEndpointDate(date) ? .semibold : .medium, design: .monospaced))
                                .lineSpacing(1)
                                .fixedSize(horizontal: true, vertical: true)
                                .foregroundStyle(isEndpointDate(date) ? PopoverColor.foreground : PopoverColor.secondaryForeground)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(PopoverColor.chartGrid)
                    AxisValueLabel {
                        if let percent = value.as(Double.self) {
                            Text("\(Int(percent))%")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(PopoverColor.secondaryForeground)
                        }
                    }
                }
            }
            .frame(height: 154)
            .chartPlotStyle { plotArea in
                plotArea
                    .background(PopoverColor.chartSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(PopoverColor.divider, lineWidth: 0.8)
                    )
            }
            HStack(spacing: 12) {
                legendItem("Observed", color: PopoverColor.chartSol, dashed: false)
                legendItem("Depletion", color: PopoverColor.chartDepletion, dashed: false)
                legendItem("Budget pace", color: PopoverColor.chartLuna, dashed: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func legendItem(_ title: String, color: Color, dashed: Bool) -> some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(color.opacity(dashed ? 0.65 : 1))
                .frame(width: dashed ? 13 : 15, height: 2)
                .overlay {
                    if dashed {
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(PopoverColor.forecastSurface)
                                    .frame(width: 1.6)
                            }
                        }
                    }
                }

            Text(title.uppercased())
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundStyle(PopoverColor.secondaryForeground)
        }
    }

    private func axisLabel(_ date: Date) -> String {
        guard let range = timelineRange,
              range.end.timeIntervalSince(range.start) <= 48 * 3600
        else {
            let formatter = DateFormatter()
            formatter.locale = .current
            formatter.timeZone = .current
            formatter.dateFormat = isEndpointDate(date) ? "MMM d" : "d"

            return formatter.string(from: date).uppercased()
        }

        let dayFormatter = DateFormatter()
        dayFormatter.locale = .current
        dayFormatter.timeZone = .current
        dayFormatter.dateFormat = "MMM d"

        let timeFormatter = DateFormatter()
        timeFormatter.locale = .current
        timeFormatter.timeZone = .current
        timeFormatter.dateFormat = "HH:mm"

        return "\(dayFormatter.string(from: date).uppercased())\n\(timeFormatter.string(from: date))"
    }

    private func isEndpointDate(_ date: Date) -> Bool {
        guard let range = timelineRange else {
            return false
        }

        return abs(date.timeIntervalSince(range.start)) < 60
            || abs(date.timeIntervalSince(range.end)) < 60
    }

    private func axisLabelAnchor(_ date: Date) -> UnitPoint {
        guard let range = timelineRange else {
            return .top
        }

        if abs(date.timeIntervalSince(range.start)) < 60 {
            return .topLeading
        }

        if abs(date.timeIntervalSince(range.end)) < 60 {
            return .topTrailing
        }

        return .top
    }
}

private extension Array where Element == Date {
    func deduplicated() -> [Date] {
        var dates: [Date] = []

        for date in self {
            if dates.last.map({ abs($0.timeIntervalSince(date)) < 60 }) == true {
                dates[dates.count - 1] = date
            } else {
                dates.append(date)
            }
        }

        return dates
    }
}
