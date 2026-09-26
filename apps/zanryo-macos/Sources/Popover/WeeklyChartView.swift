import SwiftUI

struct WeeklyChartTimeline {
    let series: [PopoverForecastPoint]
    let reset: Date?

    var observed: [PopoverForecastPoint] { series.filter { $0.kind == .observed }.sorted { $0.at < $1.at } }
    var hasProjection: Bool { series.contains { $0.kind == .forecast } }
    var boundary: Date? { series.filter { $0.kind == .forecast }.map(\.at).min() }

    var domain: ClosedRange<Date>? {
        guard let first = series.map(\.at).min(), let last = series.map(\.at).max() else { return nil }
        let end = hasProjection ? max(last, reset ?? last) : last
        return min(first, end.addingTimeInterval(-3600))...end
    }

    var historyCaption: String {
        guard let first = observed.first, let last = observed.last else { return "No weekly readings yet." }
        if first.at == last.at { return "First reading. No earlier history is assumed." }
        let span = ResetDuration(from: first.at, to: last.at).compact
        let change = first.remainingPercent - last.remainingPercent
        if observed.allSatisfy({ abs($0.remainingPercent - first.remainingPercent) < 0.01 }) {
            return "\(span) recorded · no change observed"
        }
        return "\(span) recorded · \(String(format: "%.1f", abs(change))) pp \(change >= 0 ? "decrease" : "increase")"
    }

    func accessibilityLabel(provider: String) -> String {
        let kinds = Set(series.map(\.kind))
        var parts = ["\(provider) weekly remaining quota."]
        if kinds.contains(.observed) { parts += [historyCaption, "Solid line: observed."] }
        if kinds.contains(.forecast) { parts.append("Solid red line: estimated, not guaranteed.") }
        if kinds.contains(.sustainable) { parts.append("Gray dashed line: fixed ideal cycle, 100 percent at cycle start to zero at reset, not observed usage.") }
        if series.isEmpty { parts.append("No data available.") }
        return parts.joined(separator: " ")
    }
}

struct WeeklyChartView: View {
    let timeline: WeeklyChartTimeline
    let pace: String
    let accent: Color
    let provider: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("WEEKLY FORECAST")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent)
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("CURRENT PACE")
                        .font(.system(size: 8.6, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PopoverColor.secondaryForeground)
                    Text(pace)
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PopoverColor.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }.frame(maxWidth: 178, alignment: .trailing)
            }
            if timeline.series.isEmpty {
                Text("Weekly history will appear after the first reading.")
                    .font(.caption).foregroundStyle(PopoverColor.secondaryForeground)
                    .frame(maxWidth: .infinity, minHeight: 154, alignment: .center)
            } else {
                ForecastChartView(series: timeline.series,
                    accessibilityLabel: timeline.accessibilityLabel(provider: provider),
                    observedColor: accent, displayDomain: timeline.domain)
            }
        }.padding(.horizontal, 16).padding(.vertical, 9)
            .background(PopoverColor.forecastSurface)
    }
}
