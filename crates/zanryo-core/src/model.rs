use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::{ProviderId, Result, ZanryoError};

fn legacy_dashboard_provider() -> ProviderId {
    ProviderId::OpenAi
}

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

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct AccountContext {
    #[serde(skip_serializing, default = "legacy_dashboard_provider")]
    pub provider: ProviderId,
    pub plan_type: PlanType,
    pub observed_at: Option<DateTime<Utc>>,
}

impl AccountContext {
    pub fn unknown(provider: ProviderId) -> Self {
        Self {
            provider,
            plan_type: PlanType::Unknown,
            observed_at: None,
        }
    }

    pub fn new(provider: ProviderId, plan_type: PlanType, observed_at: DateTime<Utc>) -> Self {
        match plan_type {
            PlanType::Unknown => Self::unknown(provider),
            _ => Self {
                provider,
                plan_type,
                observed_at: Some(observed_at),
            },
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LimitKind {
    FiveHour,
    Weekly,
    Spark,
    Fable,
    Other,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct RateLimit {
    #[serde(skip_serializing, default = "legacy_dashboard_provider")]
    pub provider: ProviderId,
    pub kind: LimitKind,
    pub limit_id: String,
    pub remaining_percent: f64,
    pub resets_at: DateTime<Utc>,
    pub observed_at: DateTime<Utc>,
}

impl RateLimit {
    pub fn new(
        provider: ProviderId,
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
            provider,
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
    #[serde(skip_serializing, default = "legacy_dashboard_provider")]
    pub provider: ProviderId,
    #[serde(skip_serializing, default)]
    pub five_hour: Option<RateLimit>,
    pub weekly: RateLimit,
    pub spark: Option<RateLimit>,
    #[serde(skip_serializing, default)]
    pub fable: Option<RateLimit>,
    pub other: Vec<RateLimit>,
    pub freshness: Freshness,
}

impl QuotaSnapshot {
    pub fn from_limits(
        provider: ProviderId,
        limits: Vec<RateLimit>,
        freshness: Freshness,
    ) -> Result<Self> {
        if limits.iter().any(|limit| limit.provider != provider) {
            return Err(ZanryoError::Protocol(
                "quota limits must belong to the snapshot provider".to_owned(),
            ));
        }

        let five_hour = limits
            .iter()
            .find(|limit| limit.kind == LimitKind::FiveHour)
            .cloned();
        let weekly = limits
            .iter()
            .find(|limit| limit.kind == LimitKind::Weekly)
            .cloned()
            .ok_or(ZanryoError::MissingWeeklyLimit)?;
        let spark = limits
            .iter()
            .find(|limit| limit.kind == LimitKind::Spark)
            .cloned();
        let fable = limits
            .iter()
            .find(|limit| limit.kind == LimitKind::Fable)
            .cloned();
        let other = limits
            .into_iter()
            .filter(|limit| limit.kind == LimitKind::Other)
            .collect();

        Ok(Self {
            provider,
            five_hour,
            weekly,
            spark,
            fable,
            other,
            freshness,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ProviderId;
    use chrono::{TimeZone, Utc};

    #[test]
    fn quota_snapshot_rejects_limits_from_another_provider() {
        let now = Utc.with_ymd_and_hms(2026, 7, 22, 9, 0, 0).unwrap();
        let limit = RateLimit::new(
            ProviderId::Claude,
            LimitKind::Weekly,
            "claude_weekly",
            60.0,
            now + chrono::Duration::days(6),
            now,
        )
        .unwrap();

        let error = QuotaSnapshot::from_limits(ProviderId::OpenAi, vec![limit], Freshness::Fresh)
            .unwrap_err();

        assert!(matches!(error, ZanryoError::Protocol(_)));
    }

    #[test]
    fn quota_snapshot_selects_all_known_window_kinds() {
        let now = Utc.with_ymd_and_hms(2026, 7, 22, 9, 0, 0).unwrap();
        let make = |kind, id| {
            RateLimit::new(
                ProviderId::OpenAi,
                kind,
                id,
                70.0,
                now + chrono::Duration::days(1),
                now,
            )
            .unwrap()
        };
        let snapshot = QuotaSnapshot::from_limits(
            ProviderId::OpenAi,
            vec![
                make(LimitKind::Weekly, "weekly"),
                make(LimitKind::FiveHour, "five_hour"),
                make(LimitKind::Spark, "spark"),
                make(LimitKind::Fable, "fable"),
            ],
            Freshness::Fresh,
        )
        .unwrap();

        assert_eq!(snapshot.provider, ProviderId::OpenAi);
        assert_eq!(snapshot.five_hour.unwrap().limit_id, "five_hour");
        assert_eq!(snapshot.fable.unwrap().limit_id, "fable");
    }

    #[test]
    fn quota_snapshot_selects_weekly_and_spark() {
        let reset = Utc.with_ymd_and_hms(2026, 7, 25, 12, 0, 0).unwrap();
        let observed = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();
        let limits = vec![
            RateLimit::new(
                ProviderId::OpenAi,
                LimitKind::Weekly,
                "codex_weekly",
                15.0,
                reset,
                observed,
            )
            .unwrap(),
            RateLimit::new(
                ProviderId::OpenAi,
                LimitKind::Spark,
                "spark",
                72.0,
                reset,
                observed,
            )
            .unwrap(),
        ];

        let snapshot =
            QuotaSnapshot::from_limits(ProviderId::OpenAi, limits, Freshness::Fresh).unwrap();

        assert_eq!(snapshot.weekly.remaining_percent, 15.0);
        assert_eq!(snapshot.spark.unwrap().remaining_percent, 72.0);
    }

    #[test]
    fn remaining_percentage_rejects_out_of_range_values() {
        let now = Utc::now();
        let error = RateLimit::new(
            ProviderId::OpenAi,
            LimitKind::Weekly,
            "weekly",
            101.0,
            now,
            now,
        )
        .unwrap_err();
        assert!(matches!(error, ZanryoError::InvalidPercentage(101.0)));
    }
}
