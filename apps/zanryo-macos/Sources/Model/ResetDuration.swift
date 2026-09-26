import Foundation

/// Elapsed time, independent of calendar/DST. Never discard a partial hour.
struct ResetDuration {
    let days: Int
    let hours: Int
    let minutes: Int
    private let hasPartialHour: Bool

    init(from start: Date, to end: Date) {
        let seconds = max(0, end.timeIntervalSince(start))
        let totalMinutes = Int(ceil(seconds / 60))
        hasPartialHour = seconds.truncatingRemainder(dividingBy: 3_600) > 0
        days = totalMinutes / 1_440
        hours = (totalMinutes % 1_440) / 60
        minutes = totalMinutes % 60
    }

    private var units: [(value: Int, short: String, long: String)] {
        let nonzero = [(days, "d", "day"), (hours, "h", "hour"), (minutes, "m", "minute")]
            .filter { $0.0 > 0 }
        return nonzero.isEmpty ? [(0, "m", "minute")] : nonzero
    }

    var compact: String {
        units.map { "\($0.value)\($0.short)" }.joined(separator: " ")
    }

    /// Menu space is scarce. Weekly resets round UP to hours and say so;
    /// short windows retain minutes. Full precision stays in the popover/AX.
    var menuBar: String {
        guard days > 0 else { return compact.replacingOccurrences(of: " ", with: "") }
        let roundedHours = days * 24 + hours + (minutes > 0 ? 1 : 0)
        let remainder = roundedHours % 24
        return (hasPartialHour ? "≈" : "") + "\(roundedHours / 24)d" + (remainder > 0 ? "\(remainder)h" : "")
    }

    var spoken: String {
        let parts = units.map { "\($0.value) \($0.long)\($0.value == 1 ? "" : "s")" }
        guard parts.count > 1 else { return parts[0] }
        return parts.dropLast().joined(separator: ", ") + " and " + parts.last!
    }
}
