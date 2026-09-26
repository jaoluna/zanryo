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
        if kinds.contains(.forecast) { parts.append("Red dashed line: estimated, not guaranteed.") }
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
    var confidence: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("WEEKLY OUTLOOK")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent)
                Spacer(minLength: 4)
                Text(pace).font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(PopoverColor.secondaryForeground)
            }
            if timeline.series.isEmpty {
                Text("Weekly history will appear after the first reading.")
                    .font(.caption).foregroundStyle(PopoverColor.secondaryForeground)
                    .frame(maxWidth: .infinity, minHeight: 154, alignment: .center)
            } else {
                ForecastChartView(series: timeline.series,
                    accessibilityLabel: timeline.accessibilityLabel(provider: provider),
                    observedColor: accent, displayDomain: timeline.domain,
                    onlyAvailableLegends: true, forecastDashed: true, forecastLabel: "Projected",
                    markEstimatedAsObserved: false, evenlySpacedTimeTicks: true, insetPoints: true,
                    projectionBoundary: timeline.boundary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(timeline.historyCaption)
                    .fixedSize(horizontal: false, vertical: true)
                if timeline.hasProjection, let confidence {
                    Spacer(minLength: 0)
                    Text("\(confidence) confidence").fontWeight(.semibold)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }.font(.system(size: 9.5)).foregroundStyle(PopoverColor.secondaryForeground)
        }.padding(.horizontal, 16).padding(.vertical, 12)
            .background(PopoverColor.forecastSurface)
    }
}
