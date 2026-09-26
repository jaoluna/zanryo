import XCTest
@testable import Zanryo

final class ResetDurationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_774_171_200)

    func testMinutesAreNotDiscardedAndOnlyPartialMinuteRoundsUp() {
        for (seconds, compact, menu) in [
            (14_100.0, "3h 55m", "3h55m"), (3_599, "1h", "1h"),
            (3_541, "1h", "1h"), (3_540, "59m", "59m"), (1, "1m", "1m"),
            (0, "0m", "0m"), (-1, "0m", "0m"),
            (518_100, "5d 23h 55m", "5d23:55"), (516_000, "5d 23h 20m", "5d23:20"),
            (507_600, "5d 21h", "5d21:00"),
            (518_341, "6d", "6d00:00"), (518_400, "6d", "6d00:00"),
            (89_999, "1d 1h", "1d01:00"), (90_000, "1d 1h", "1d01:00"),
        ] {
            let value = ResetDuration(from: now, to: now.addingTimeInterval(seconds))
            XCTAssertEqual(value.compact, compact, "\(seconds)")
            XCTAssertEqual(value.menuBar, menu, "\(seconds)")
        }
    }

    func testSpokenDurationPreservesMinutesAndPluralization() {
        XCTAssertEqual(ResetDuration(from: now, to: now.addingTimeInterval(90_060)).spoken,
                       "1 day, 1 hour and 1 minute")
        XCTAssertEqual(ResetDuration(from: now, to: now.addingTimeInterval(14_100)).spoken,
                       "3 hours and 55 minutes")
    }

    func testElapsedTimeCrossingDSTDoesNotLoseAnHour() throws {
        let parser = ISO8601DateFormatter()
        let start = try XCTUnwrap(parser.date(from: "2026-11-01T04:30:00Z"))
        let end = try XCTUnwrap(parser.date(from: "2026-11-01T08:30:00Z"))
        XCTAssertEqual(ResetDuration(from: start, to: end).compact, "4h")
    }
}
