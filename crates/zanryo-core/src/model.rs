use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::{Result, ZanryoError};

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PlanType {
    Free,
    Go,
    Plus,
    Pro,
    ProLite,
    Team,
    Business,
    Enterprise,
    Edu,
    #[default]
    Unknown,
}

impl PlanType {
    pub fn from_app_server(value: &str) -> Self {
        match value {
            "free" => Self::Free,
            "go" => Self::Go,
            "plus" => Self::Plus,
            "pro" => Self::Pro,
            "pro_lite" => Self::ProLite,
            "team" => Self::Team,
            "business" => Self::Business,
            "enterprise" => Self::Enterprise,
            "edu" => Self::Edu,
            _ => Self::Unknown,
        }
    }
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct AccountContext {
    pub plan_type: PlanType,
    pub observed_at: Option<DateTime<Utc>>,
}

impl AccountContext {
    pub fn unknown() -> Self {
        Self::default()
    }

    pub fn new(plan_type: PlanType, observed_at: DateTime<Utc>) -> Self {
        match plan_type {
            PlanType::Unknown => Self::unknown(),
            _ => Self {
                plan_type,
                observed_at: Some(observed_at),
            },
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LimitKind {
    Weekly,
    Spark,
    Other,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct RateLimit {
    pub kind: LimitKind,
    pub limit_id: String,
    pub remaining_percent: f64,
    pub resets_at: DateTime<Utc>,
    pub observed_at: DateTime<Utc>,
}

impl RateLimit {
    pub fn new(
        kind: LimitKind,
        limit_id: impl Into<String>,
        remaining_percent: f64,
        resets_at: DateTime<Utc>,
        observed_at: DateTime<Utc>,
    ) -> Result<Self> {
        if !(0.0..=100.0).contains(&remaining_percent) {
            return Err(ZanryoError::InvalidPercentage(remaining_percent));
        }

        Ok(Self {
            kind,
            limit_id: limit_id.into(),
            remaining_percent,
            resets_at,
            observed_at,
        })
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Freshness {
    Fresh,
    Stale,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct QuotaSnapshot {
    pub weekly: RateLimit,
    pub spark: Option<RateLimit>,
    pub other: Vec<RateLimit>,
    pub freshness: Freshness,
}

impl QuotaSnapshot {
    pub fn from_limits(limits: Vec<RateLimit>, freshness: Freshness) -> Result<Self> {
        let weekly = limits
            .iter()
            .find(|limit| limit.kind == LimitKind::Weekly)
            .cloned()
            .ok_or(ZanryoError::MissingWeeklyLimit)?;
        let spark = limits
            .iter()
            .find(|limit| limit.kind == LimitKind::Spark)
            .cloned();
        let other = limits
            .into_iter()
            .filter(|limit| limit.kind == LimitKind::Other)
            .collect();

        Ok(Self {
            weekly,
            spark,
            other,
            freshness,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::{TimeZone, Utc};

    #[test]
    fn quota_snapshot_selects_weekly_and_spark() {
        let reset = Utc.with_ymd_and_hms(2026, 7, 25, 12, 0, 0).unwrap();
        let observed = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();
        let limits = vec![
            RateLimit::new(LimitKind::Weekly, "codex_weekly", 15.0, reset, observed).unwrap(),
            RateLimit::new(LimitKind::Spark, "spark", 72.0, reset, observed).unwrap(),
        ];

        let snapshot = QuotaSnapshot::from_limits(limits, Freshness::Fresh).unwrap();

        assert_eq!(snapshot.weekly.remaining_percent, 15.0);
        assert_eq!(snapshot.spark.unwrap().remaining_percent, 72.0);
    }

    #[test]
    fn remaining_percentage_rejects_out_of_range_values() {
        let now = Utc::now();
        let error = RateLimit::new(LimitKind::Weekly, "weekly", 101.0, now, now).unwrap_err();
        assert!(matches!(error, ZanryoError::InvalidPercentage(101.0)));
    }
}
