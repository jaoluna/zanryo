import XCTest
@testable import Zanryo

final class ClaudeUsageDecoderTests: XCTestCase {
    func testAdditiveWeeklyForecastDecodesAndLegacyPayloadStaysValid() throws {
        let legacy = payload(five: 66, weekly: 97)
        XCTAssertNil(try BridgeDecoder.decodeClaudeUsage(from: legacy)?.weeklyForecast)
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy) as? [String: Any])
        var data = try XCTUnwrap(envelope["data"] as? [String: Any])
        data["weekly_forecast"] = [
            "status": "collecting_history", "confidence": "collecting",
            "chart": ["observed": [["at": "2026-09-25T20:40:00Z", "remaining_percent": 97]],
                      "forecast": [], "sustainable": []],
        ]
        envelope["data"] = data
        let decoded = try XCTUnwrap(BridgeDecoder.decodeClaudeUsage(from: JSONSerialization.data(withJSONObject: envelope)))
        XCTAssertEqual(decoded.weeklyForecast?.status, .collectingHistory)
        XCTAssertEqual(decoded.weeklyForecast?.chart.observed.first?.remainingPercent, 97)
        XCTAssertEqual(decoded.fiveHour?.remainingPercent, 66)
    }

    func testOptionalWindowsAndRemainingScale() throws {
        let five = try XCTUnwrap(BridgeDecoder.decodeClaudeUsage(from: payload(five: 66, weekly: nil)))
        XCTAssertEqual(five.fiveHour?.remainingPercent, 66)
        XCTAssertNil(five.weekly)
        let weekly = try XCTUnwrap(BridgeDecoder.decodeClaudeUsage(from: payload(five: nil, weekly: 97)))
        XCTAssertNil(weekly.fiveHour)
        XCTAssertEqual(weekly.preferredLimit?.remainingPercent, 97)
        for percent in [0.0, 100.0] {
            XCTAssertEqual(try BridgeDecoder.decodeClaudeUsage(from: payload(five: percent, weekly: nil))?.fiveHour?.remainingPercent, percent)
        }
    }
    func testRejectsForeignEmptyAndOutOfRangePayload() {
        for data in [payload(five:66,weekly:97,provider:"openai"),payload(five:nil,weekly:nil),payload(five:101,weekly:nil)] {
            XCTAssertThrowsError(try BridgeDecoder.decodeClaudeUsage(from:data))
        }
    }
    func testSharedFreshnessRuleForAgeResetAndClockSkew() throws {
        let snapshot = try XCTUnwrap(BridgeDecoder.decodeClaudeUsage(from: payload(five:66,weekly:97)))
        let now = snapshot.fiveHour!.observedAt
        XCTAssertFalse(snapshot.isStale(at:now))
        XCTAssertTrue(snapshot.isStale(at:now.addingTimeInterval(361)))
        XCTAssertTrue(snapshot.isStale(at:now.addingTimeInterval(-1)))
        XCTAssertTrue(snapshot.isStale(at:snapshot.fiveHour!.resetsAt))
    }
    func testStatusUsesSessionNotSumAndKeepsProvidersSeparate() throws {
        let snapshot = try XCTUnwrap(BridgeDecoder.decodeClaudeUsage(from: payload(five:66,weekly:97)))
        let now = snapshot.fiveHour!.observedAt
        let presentation = StatusPresentation.claude(snapshot:snapshot,enabled:true,hasError:false,now:now)
        XCTAssertEqual(presentation.modules.count,1)
        XCTAssertEqual(presentation.modules.first?.provider,.claude)
        XCTAssertEqual(presentation.modules.first?.remainingPercent,66)
        XCTAssertFalse(presentation.modules.first!.isStale)
        XCTAssertTrue(StatusPresentation.claude(snapshot:snapshot,enabled:false,hasError:false).dragonOnly)
        XCTAssertTrue(StatusPresentation.claude(snapshot:snapshot,enabled:true,hasError:true,now:now).modules.first!.isStale)
        XCTAssertTrue(StatusPresentation.claude(snapshot:snapshot,enabled:true,hasError:false,now:now.addingTimeInterval(361)).modules.first!.isStale)
    }
    private func payload(five:Double?,weekly:Double?,provider:String="claude") -> Data {
        func window(_ percent:Double?,_ kind:String) -> String {
            guard let percent else { return "null" }
            return #"{"kind":"\#(kind)","limit_id":"claude_\#(kind)","remaining_percent":\#(percent),"resets_at":"2026-09-25T21:00:00Z","observed_at":"2026-09-25T20:40:00Z"}"#
        }
        return Data(#"{"schema_version":1,"ok":true,"data":{"provider":"\#(provider)","five_hour":\#(window(five,"five_hour")),"weekly":\#(window(weekly,"weekly")),"freshness":"fresh"},"error":null}"#.utf8)
    }
}

@MainActor
final class ClaudeUsageStoreTests: XCTestCase {
    func testRefreshThrottleAndForcedRefresh() async {
        let source = ClaudeUsageStub()
        let store = ClaudeUsageStore(source:source)
        let now = Date()
        await store.refresh(now:now)
        await store.refresh(now:now.addingTimeInterval(60))
        let calls = await source.calls
        XCTAssertEqual(calls,1)
        await store.refresh(force:true,now:now.addingTimeInterval(61))
        let forced = await source.calls
        XCTAssertEqual(forced,2)
        XCTAssertEqual(store.snapshot?.fiveHour?.remainingPercent,66)
    }
    func testFailurePreservesLastReadingAndIsThrottled() async {
        let source = ClaudeUsageStub()
        let store = ClaudeUsageStore(source:source)
        let now = Date()
        await store.refresh(now:now)
        await source.fail()
        await store.refresh(now:now.addingTimeInterval(301))
        XCTAssertEqual(store.snapshot?.fiveHour?.remainingPercent,66)
        XCTAssertNotNil(store.lastError)
        await store.refresh(now:now.addingTimeInterval(320))
        let calls = await source.calls
        XCTAssertEqual(calls,2)
    }
    func testConcurrentRefreshIsCoalesced() async {
        let source = ClaudeUsageStub()
        let store = ClaudeUsageStore(source:source)
        async let first:Void = store.refresh(force:true)
        async let second:Void = store.refresh(force:true)
        _ = await (first,second)
        let calls = await source.calls
        XCTAssertEqual(calls,1)
    }
}

private actor ClaudeUsageStub: ClaudeUsageProviding {
    var calls = 0
    var shouldFail = false
    func fail() { shouldFail = true }
    func cachedClaude() async throws -> ClaudeUsageSnapshot? { nil }
    func refreshClaude() async throws -> ClaudeUsageSnapshot {
        calls += 1
        try await Task.sleep(for:.milliseconds(20))
        if shouldFail { throw DisplayError(code:"offline",message:"Offline") }
        let now = Date()
        return ClaudeUsageSnapshot(provider:.claude,fiveHour:RateLimit(kind:.fiveHour,limitId:"claude_five_hour",remainingPercent:66,resetsAt:now.addingTimeInterval(3600),observedAt:now),weekly:nil,freshness:.fresh)
    }
}
