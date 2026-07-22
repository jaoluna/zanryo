import XCTest
@testable import Zanryo

final class BridgeEnvelopeTests: XCTestCase {
    func testDecodesProviderDiscoveryInStableOrder() throws {
        let data = Data(
            #"{"schema_version":1,"ok":true,"data":[{"provider":"openai","executable_path":"/usr/local/bin/codex"},{"provider":"claude","executable_path":"/Users/test/.local/bin/claude"}],"error":null}"#.utf8
        )

        let providers = try BridgeDecoder.decodeInstallations(from: data)

        XCTAssertEqual(providers.map(\.provider), [.openAI, .claude])
    }

    func testDecodesEmptyProviderDiscovery() throws {
        let data = Data(#"{"schema_version":1,"ok":true,"data":null,"error":null}"#.utf8)

        let providers = try BridgeDecoder.decodeInstallations(from: data)

        XCTAssertEqual(providers, [])
    }

    func testProviderDiscoverySurfacesRemoteError() {
        let data = Data(
            #"{"schema_version":1,"ok":false,"data":null,"error":{"code":"discovery_failed","message":"Provider discovery failed"}}"#.utf8
        )

        XCTAssertThrowsError(try BridgeDecoder.decodeInstallations(from: data)) { error in
            XCTAssertEqual(
                error as? BridgeDecodeError,
                .remote(code: "discovery_failed", message: "Provider discovery failed")
            )
        }
    }

    func testDecodesVersionOneDashboardAndIgnoresUnknownFields() throws {
        let data = Data(
            """
            {
              "schema_version": 1,
              "ok": true,
              "data": {
                "quota": {
                  "weekly": {
                    "kind": "weekly",
                    "limit_id": "codex",
                    "remaining_percent": 15,
                    "resets_at": "2026-07-25T12:00:00Z",
                    "observed_at": "2026-07-20T09:00:00.125Z"
                  },
                  "spark": {
                    "kind": "spark",
                    "limit_id": "codex_bengalfox",
                    "remaining_percent": 88,
                    "resets_at": "2026-07-25T12:00:00Z",
                    "observed_at": "2026-07-20T09:00:00Z"
                  },
                  "other": [],
                  "freshness": "fresh"
                },
                "forecast": {
                  "status": "estimated",
                  "confidence": "low",
                  "consumed_per_day": 12.5,
                  "sustainable_per_day": 3,
                  "pace_difference": 9.5,
                  "estimated_depletion_at": "2026-07-21T14:00:00Z",
                  "rate_range": { "low": 10, "high": 15 },
                  "chart": {
                    "observed": [
                      {
                        "at": "2026-07-20T09:00:00Z",
                        "remaining_percent": 15
                      }
                    ],
                    "forecast": [
                      {
                        "at": "2026-07-21T09:00:00Z",
                        "remaining_percent": 2.5,
                        "uncertainty": { "low": 0, "high": 5 }
                      }
                    ],
                    "sustainable": []
                  }
                },
                "future_field": "ignored"
              },
              "error": null,
              "future_envelope_field": true
            }
            """.utf8
        )

        let snapshot = try BridgeDecoder.decodeOptionalSnapshot(from: data)

        XCTAssertEqual(snapshot?.quota.weekly.remainingPercent, 15)
        XCTAssertEqual(snapshot?.quota.spark?.remainingPercent, 88)
        XCTAssertEqual(snapshot?.forecast.confidence, .low)
        XCTAssertEqual(snapshot?.forecast.chart.forecast.count, 1)
        XCTAssertNil(snapshot?.account)
    }

    func testDecodesKnownAccountPlanWithoutAccountIdentifier() throws {
        let data = Data(
            """
            {
              "schema_version": 1,
              "ok": true,
              "data": {
                "quota": {
                  "weekly": {
                    "kind": "weekly",
                    "limit_id": "codex",
                    "remaining_percent": 15,
                    "resets_at": "2026-07-25T12:00:00Z",
                    "observed_at": "2026-07-20T09:00:00Z"
                  },
                  "spark": null,
                  "other": [],
                  "freshness": "fresh"
                },
                "forecast": {
                  "status": "collecting_history",
                  "confidence": "collecting",
                  "consumed_per_day": null,
                  "sustainable_per_day": null,
                  "pace_difference": null,
                  "estimated_depletion_at": null,
                  "rate_range": null,
                  "chart": { "observed": [], "forecast": [], "sustainable": [] }
                },
                "account": {
                  "plan_type": "plus",
                  "observed_at": "2026-07-20T09:00:00Z"
                }
              },
              "error": null
            }
            """.utf8
        )

        let snapshot = try BridgeDecoder.decodeRequiredSnapshot(from: data)

        XCTAssertEqual(snapshot.account?.planType, .plus)
        XCTAssertNotNil(snapshot.account?.observedAt)
    }

    func testDecodesUnknownPlanAndMissingObservationTimestampSafely() throws {
        let data = Data(
            """
            {
              "schema_version": 1,
              "ok": true,
              "data": {
                "quota": {
                  "weekly": {
                    "kind": "weekly",
                    "limit_id": "codex",
                    "remaining_percent": 15,
                    "resets_at": "2026-07-25T12:00:00Z",
                    "observed_at": "2026-07-20T09:00:00Z"
                  },
                  "spark": null,
                  "other": [],
                  "freshness": "fresh"
                },
                "forecast": {
                  "status": "collecting_history",
                  "confidence": "collecting",
                  "consumed_per_day": null,
                  "sustainable_per_day": null,
                  "pace_difference": null,
                  "estimated_depletion_at": null,
                  "rate_range": null,
                  "chart": { "observed": [], "forecast": [], "sustainable": [] }
                },
                "account": { "plan_type": "future_plan" }
              },
              "error": null
            }
            """.utf8
        )

        let snapshot = try BridgeDecoder.decodeRequiredSnapshot(from: data)

        XCTAssertEqual(snapshot.account?.planType, .unknown)
        XCTAssertNil(snapshot.account?.observedAt)
    }

    func testRejectsUnsupportedSchemaBeforeReadingData() {
        let data = Data(
            """
            {
              "schema_version": 2,
              "ok": true,
              "data": null,
              "error": null
            }
            """.utf8
        )

        XCTAssertThrowsError(try BridgeDecoder.decodeOptionalSnapshot(from: data)) { error in
            XCTAssertEqual(error as? BridgeDecodeError, .unsupportedSchema(2))
        }
    }
}
