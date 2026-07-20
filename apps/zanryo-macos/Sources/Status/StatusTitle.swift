import AppKit
import Foundation

struct StatusTitle {
    let attributed: NSAttributedString
    let accessibilityLabel: String

    static func make(
        snapshot: DashboardSnapshot?,
        now: Date = Date(),
        calendar: Calendar = .autoupdatingCurrent
    ) -> StatusTitle {
        guard let snapshot else {
            return StatusTitle(
                attributed: NSAttributedString(string: "Zanryo unavailable"),
                accessibilityLabel: "Zanryo quota is unavailable."
            )
        }

        let weekly = snapshot.quota.weekly
        let percentage = Int(weekly.remainingPercent.rounded())
        let reset = ResetDuration(
            from: now,
            to: weekly.resetsAt,
            calendar: calendar
        )
        let staleMarker = snapshot.quota.freshness == .stale ? " ·" : ""
        let value = "Zanryo \(percentage)% · \(reset.compact)\(staleMarker)"
        let attributed = NSMutableAttributedString(string: value)
        let percentageRange = (value as NSString).range(of: "\(percentage)%")
        attributed.addAttribute(
            .foregroundColor,
            value: NSColor(
                srgbRed: CGFloat(0xF2) / 255,
                green: CGFloat(0xB6) / 255,
                blue: CGFloat(0x32) / 255,
                alpha: 1
            ),
            range: percentageRange
        )

        var accessibilityLabel =
            "Zanryo has \(percentage) percent of the weekly Codex limit remaining. Resets in \(reset.spoken)."
        if snapshot.quota.freshness == .stale {
            accessibilityLabel += " Data may be outdated."
        }

        return StatusTitle(
            attributed: attributed,
            accessibilityLabel: accessibilityLabel
        )
    }
}

private struct ResetDuration {
    let days: Int
    let hours: Int

    init(from start: Date, to end: Date, calendar: Calendar) {
        guard end > start else {
            days = 0
            hours = 0
            return
        }

        let components = calendar.dateComponents([.day, .hour], from: start, to: end)
        days = max(0, components.day ?? 0)
        hours = max(0, components.hour ?? 0)
    }

    var compact: String {
        if days == 0 {
            return "\(hours)h"
        }
        return "\(days)d \(hours)h"
    }

    var spoken: String {
        if days == 0 {
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }

        let dayUnit = days == 1 ? "day" : "days"
        let hourUnit = hours == 1 ? "hour" : "hours"
        return "\(days) \(dayUnit) and \(hours) \(hourUnit)"
    }
}
