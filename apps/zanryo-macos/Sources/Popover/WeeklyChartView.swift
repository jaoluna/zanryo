import SwiftUI

enum QuotaChartMode: String, CaseIterable {
    case overview = "Overview"
    case history = "History"
    case projection = "Projection"
}

struct WeeklyChartTimeline {
    let series: [PopoverForecastPoint]
    let reset: Date?

    var observed: [PopoverForecastPoint] { series.filter { $0.kind == .observed }.sorted { $0.at < $1.at } }
    var projected: [PopoverForecastPoint] { series.filter { $0.kind != .observed }.sorted { $0.at < $1.at } }
    var hasProjection: Bool { series.contains { $0.kind == .forecast } }
    var boundary: Date? { series.filter { $0.kind == .forecast }.map(\.at).min() }

    func points(for mode: QuotaChartMode) -> [PopoverForecastPoint] {
        switch mode {
        case .overview: series
        case .history: observed
        case .projection: projected
        }
    }

    func domain(for mode: QuotaChartMode) -> ClosedRange<Date>? {
        let points = points(for: mode)
        guard let first = points.map(\.at).min(), let last = points.map(\.at).max() else { return nil }
        let end = mode != .history && hasProjection ? max(last, reset ?? last) : last
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

    func accessibilityLabel(for mode: QuotaChartMode, provider: String) -> String {
        let points = points(for: mode)
        let kinds = Set(points.map(\.kind))
        var parts = ["\(provider) weekly remaining quota. \(mode.rawValue)."]
        if kinds.contains(.observed) { parts += [historyCaption, "Solid line: observed."] }
        if kinds.contains(.forecast) { parts.append("Red dashed line: estimated, not guaranteed.") }
        if kinds.contains(.sustainable) { parts.append("Gray dashed line: allowed pace.") }
        if points.isEmpty { parts.append("No data available.") }
        return parts.joined(separator: " ")
    }
}

struct WeeklyChartView: View {
    let timeline: WeeklyChartTimeline
    let pace: String
    let accent: Color
    let provider: String
    var confidence: String? = nil
    @State var mode: QuotaChartMode = .overview

    var body: some View {
        let selection: QuotaChartMode = mode == .projection && !timeline.hasProjection ? .history : mode
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("WEEKLY OUTLOOK")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent)
                Spacer(minLength: 4)
                Text(pace).font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(PopoverColor.secondaryForeground)
            }
            HStack(spacing: 3) {
                ForEach(QuotaChartMode.allCases, id: \.self) { choice in
                    Button { mode = choice } label: {
                        Text(choice.rawValue).font(.system(size: 10.5, weight: .semibold))
                            .frame(maxWidth: .infinity).padding(.vertical, 5)
                            .background(selection == choice ? PopoverColor.background : .clear,
                                        in: RoundedRectangle(cornerRadius: 5))
                            .foregroundStyle(selection == choice ? PopoverColor.foreground : PopoverColor.secondaryForeground)
                    }.buttonStyle(.plain)
                        .disabled(choice == .projection && !timeline.hasProjection)
                        .opacity(choice == .projection && !timeline.hasProjection ? 0.4 : 1)
                        .accessibilityAddTraits(selection == choice ? .isSelected : [])
                }
            }.padding(3).background(PopoverColor.chartSurface, in: RoundedRectangle(cornerRadius: 7))
            if timeline.series.isEmpty {
                Text("Weekly history will appear after the first reading.")
                    .font(.caption).foregroundStyle(PopoverColor.secondaryForeground)
                    .frame(maxWidth: .infinity, minHeight: 154, alignment: .center)
            } else {
                ForecastChartView(series: timeline.points(for: selection),
                    accessibilityLabel: timeline.accessibilityLabel(for: selection, provider: provider),
                    observedColor: accent, displayDomain: timeline.domain(for: selection),
                    onlyAvailableLegends: true, forecastDashed: true, forecastLabel: "Projected",
                    markEstimatedAsObserved: false, evenlySpacedTimeTicks: true, insetPoints: true,
                    projectionBoundary: selection == .overview ? timeline.boundary : nil)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(selection == .projection ? "Estimate until weekly reset" : timeline.historyCaption)
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
