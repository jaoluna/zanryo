use chrono::{TimeZone, Utc};
use serde_json::Value;
use zanryo_core::{LimitKind, decode_rate_limits, is_rate_limits_update};

#[test]
fn decodes_weekly_and_spark_from_read_response() {
    let value: Value = serde_json::from_str(include_str!("fixtures/rate_limits.json")).unwrap();
    let observed = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();
    let limits = decode_rate_limits(value, observed).unwrap();

    assert_eq!(limits.len(), 2);
    assert!(limits.iter().any(|item| item.kind == LimitKind::Weekly));
    assert!(limits.iter().any(|item| item.kind == LimitKind::Spark));
}

#[test]
fn recognizes_rate_limit_update_notification() {
    let value: Value =
        serde_json::from_str(include_str!("fixtures/rate_limits_update.json")).unwrap();
    assert!(is_rate_limits_update(&value));
}

#[test]
fn converts_used_percent_and_unix_reset_time() {
    let value: Value = serde_json::from_str(include_str!("fixtures/rate_limits.json")).unwrap();
    let observed = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();
    let limits = decode_rate_limits(value, observed).unwrap();
    let weekly = limits
        .iter()
        .find(|item| item.kind == LimitKind::Weekly)
        .unwrap();

    assert_eq!(weekly.remaining_percent, 15.0);
    assert_eq!(weekly.resets_at.timestamp(), 1_784_991_600);
}
