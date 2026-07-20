use std::collections::BTreeMap;

use chrono::{DateTime, Utc};
use serde::Deserialize;
use serde_json::Value;

use crate::{LimitKind, RateLimit, Result, ZanryoError};

const WEEKLY_WINDOW_MINUTES: i64 = 7 * 24 * 60;

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RpcEnvelope {
    #[serde(default)]
    result: Option<RateLimitsResponse>,
    #[serde(default)]
    params: Option<RateLimitsNotification>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RateLimitsResponse {
    #[serde(default)]
    rate_limits: Option<RateLimitSnapshot>,
    #[serde(default)]
    rate_limits_by_limit_id: Option<BTreeMap<String, RateLimitSnapshot>>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RateLimitsNotification {
    #[serde(default)]
    rate_limits: Option<RateLimitSnapshot>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RateLimitSnapshot {
    #[serde(default)]
    limit_id: Option<String>,
    #[serde(default)]
    limit_name: Option<String>,
    #[serde(default)]
    primary: Option<RateLimitWindow>,
    #[serde(default)]
    secondary: Option<RateLimitWindow>,
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RateLimitWindow {
    #[serde(default)]
    used_percent: Option<i32>,
    #[serde(default)]
    window_duration_mins: Option<i64>,
    #[serde(default)]
    resets_at: Option<i64>,
}

pub fn decode_rate_limits(value: Value, observed_at: DateTime<Utc>) -> Result<Vec<RateLimit>> {
    let envelope: RpcEnvelope = serde_json::from_value(value)
        .map_err(|error| ZanryoError::Protocol(format!("invalid JSON-RPC payload: {error}")))?;

    if let Some(result) = envelope.result {
        if let Some(by_id) = result
            .rate_limits_by_limit_id
            .filter(|limits| !limits.is_empty())
        {
            return by_id
                .into_iter()
                .map(|(map_id, snapshot)| decode_snapshot(snapshot, Some(map_id), observed_at))
                .collect();
        }

        if let Some(snapshot) = result.rate_limits {
            return Ok(vec![decode_snapshot(snapshot, None, observed_at)?]);
        }
    }

    if let Some(snapshot) = envelope.params.and_then(|params| params.rate_limits) {
        return Ok(vec![decode_snapshot(snapshot, None, observed_at)?]);
    }

    Err(ZanryoError::Protocol(
        "rateLimits payload is missing".to_owned(),
    ))
}

pub fn is_rate_limits_update(value: &Value) -> bool {
    value.get("method").and_then(Value::as_str) == Some("account/rateLimits/updated")
}

fn decode_snapshot(
    snapshot: RateLimitSnapshot,
    fallback_id: Option<String>,
    observed_at: DateTime<Utc>,
) -> Result<RateLimit> {
    let limit_id = snapshot
        .limit_id
        .or(fallback_id)
        .ok_or_else(|| ZanryoError::Protocol("limitId is missing".to_owned()))?;
    let kind = classify_limit(&limit_id, snapshot.limit_name.as_deref());
    let window = select_window(snapshot.primary.as_ref(), snapshot.secondary.as_ref())
        .ok_or_else(|| ZanryoError::Protocol(format!("{limit_id}.window is missing")))?;
    let used_percent = window
        .used_percent
        .ok_or_else(|| ZanryoError::Protocol(format!("{limit_id}.usedPercent is missing")))?;
    let reset_timestamp = window
        .resets_at
        .ok_or_else(|| ZanryoError::Protocol(format!("{limit_id}.resetsAt is missing")))?;
    let resets_at = DateTime::<Utc>::from_timestamp(reset_timestamp, 0)
        .ok_or_else(|| ZanryoError::Protocol(format!("{limit_id}.resetsAt is invalid")))?;

    RateLimit::new(
        kind,
        limit_id,
        100.0 - f64::from(used_percent),
        resets_at,
        observed_at,
    )
}

fn select_window<'a>(
    primary: Option<&'a RateLimitWindow>,
    secondary: Option<&'a RateLimitWindow>,
) -> Option<&'a RateLimitWindow> {
    let windows = [primary, secondary];

    windows
        .iter()
        .flatten()
        .copied()
        .find(|window| window.window_duration_mins == Some(WEEKLY_WINDOW_MINUTES))
        .or_else(|| {
            windows
                .iter()
                .flatten()
                .copied()
                .max_by_key(|window| window.window_duration_mins.unwrap_or_default())
        })
}

fn classify_limit(limit_id: &str, limit_name: Option<&str>) -> LimitKind {
    let identity = format!(
        "{} {}",
        limit_id.to_ascii_lowercase(),
        limit_name.unwrap_or_default().to_ascii_lowercase()
    );

    if identity.contains("spark") || identity.contains("bengalfox") {
        LimitKind::Spark
    } else if limit_id.eq_ignore_ascii_case("codex") {
        LimitKind::Weekly
    } else {
        LimitKind::Other
    }
}
