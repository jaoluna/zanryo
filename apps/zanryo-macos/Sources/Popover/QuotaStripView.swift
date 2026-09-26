import SwiftUI

/// One visual grammar; limits retain their own values, observation and reset.
struct QuotaStripView: View {
    struct Window: Identifiable {
        let title: String
        let limit: RateLimit
        var id: String { limit.limitId }
    }

    let provider: String
    let windows: [Window]
    let accent: Color
    var emptyText = "Reading quota…"
    var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(provider.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1).foregroundStyle(PopoverColor.secondaryForeground)
            if windows.isEmpty {
                Text(emptyText).font(.system(size: 16, weight: .medium))
            } else if windows.count == 1, let window = windows.first {
                HStack(alignment: .center, spacing: 16) {
                    value(window, size: 42)
                    Spacer(minLength: 0)
                    labels(window, alignment: .trailing)
                }
                meter(windows[0])
            } else {
                HStack(alignment: .top, spacing: 20) {
                    ForEach(Array(windows.prefix(2))) { window in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(window.title.uppercased())
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(PopoverColor.secondaryForeground)
                            value(window, size: 30)
                            meter(window)
                            reset(window)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                ForEach(Array(windows.dropFirst(2))) { window in
                    Divider().overlay(PopoverColor.divider)
                    HStack {
                        Text(window.title).font(.system(size: 11, weight: .medium))
                        value(window, size: 16)
                        Spacer(minLength: 4)
                        reset(window)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    private func value(_ window: Window, size: CGFloat) -> some View {
        Text("\(Int(window.limit.remainingPercent.rounded()))%")
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .foregroundStyle(accent).lineLimit(1)
            .accessibilityLabel("\(window.title): \(Int(window.limit.remainingPercent.rounded())) percent remaining")
    }

    private func labels(_ window: Window, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 5) {
            Text("\(window.title) remaining").font(.system(size: 12, weight: .medium))
            reset(window)
        }
    }

    private func reset(_ window: Window) -> some View {
        let duration = ResetDuration(from: now, to: window.limit.resetsAt)
        return Text(window.limit.resetsAt <= now ? "Reset due · refresh" : "Reset in \(duration.compact)")
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .foregroundStyle(PopoverColor.secondaryForeground)
            .fixedSize(horizontal: false, vertical: true)
            .help("\(window.limit.resetsAt.formatted(date: .complete, time: .shortened)) · \(TimeZone.current.identifier)")
            .accessibilityLabel("Resets \(window.limit.resetsAt.formatted(date: .complete, time: .shortened)), in \(duration.spoken)")
    }

    private func meter(_ window: Window) -> some View {
        GeometryReader { geometry in
            Capsule().fill(PopoverColor.divider)
                .overlay(alignment: .leading) {
                    Capsule().fill(accent)
                        .frame(width: geometry.size.width * min(100, max(0, window.limit.remainingPercent)) / 100)
                }
        }.frame(height: 3).accessibilityHidden(true)
    }
}
