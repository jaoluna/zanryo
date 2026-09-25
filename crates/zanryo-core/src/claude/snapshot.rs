use crate::{Freshness, HistoryRepository, LimitKind, ProviderId, RateLimit, Result, ZanryoError};
use serde::Serialize;

/// Additive provider-aware DTO. The OpenAI legacy dashboard is unchanged.
#[derive(Debug, Clone, Serialize)]
pub struct ClaudeUsageSnapshot {
    pub provider: ProviderId,
    pub five_hour: Option<RateLimit>,
    pub weekly: Option<RateLimit>,
    pub freshness: Freshness,
}

impl ClaudeUsageSnapshot {
    pub fn from_limits(limits: Vec<RateLimit>, freshness: Freshness) -> Result<Self> {
        if limits.is_empty()
            || limits.iter().any(|limit| {
                limit.provider != ProviderId::Claude
                    || ![LimitKind::FiveHour, LimitKind::Weekly].contains(&limit.kind)
            })
            || limits
                .iter()
                .filter(|limit| limit.kind == LimitKind::FiveHour)
                .count()
                > 1
            || limits
                .iter()
                .filter(|limit| limit.kind == LimitKind::Weekly)
                .count()
                > 1
        {
            return Err(ZanryoError::Protocol("invalid Claude quota windows".into()));
        }
        Ok(Self {
            provider: ProviderId::Claude,
            five_hour: limits
                .iter()
                .find(|limit| limit.kind == LimitKind::FiveHour)
                .cloned(),
            weekly: limits
                .iter()
                .find(|limit| limit.kind == LimitKind::Weekly)
                .cloned(),
            freshness,
        })
    }
    pub fn cached(history: &HistoryRepository) -> Result<Option<Self>> {
        let limits = history.latest_limits(ProviderId::Claude)?;
        if limits.is_empty() {
            Ok(None)
        } else {
            Self::from_limits(limits, Freshness::Stale).map(Some)
        }
    }
    pub fn record(history: &HistoryRepository, limits: Vec<RateLimit>) -> Result<Self> {
        let snapshot = Self::from_limits(limits.clone(), Freshness::Fresh)?;
        history.insert_limits(&limits)?;
        Ok(snapshot)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn optional_windows_roundtrip_separately_and_leave_openai_unchanged() {
        let dir = tempfile::tempdir().unwrap();
        let history = HistoryRepository::open(dir.path().join("history.sqlite3")).unwrap();
        let now = chrono::Utc::now();
        let make = |provider, kind, id, percent| {
            RateLimit::new(
                provider,
                kind,
                id,
                percent,
                now + chrono::Duration::hours(2),
                now,
            )
            .unwrap()
        };
        let openai = make(ProviderId::OpenAi, LimitKind::Weekly, "codex", 28.0);
        history
            .insert_limits(std::slice::from_ref(&openai))
            .unwrap();
        let snapshot = ClaudeUsageSnapshot::record(
            &history,
            vec![make(
                ProviderId::Claude,
                LimitKind::FiveHour,
                "claude_five_hour",
                66.0,
            )],
        )
        .unwrap();
        assert!(snapshot.weekly.is_none());
        assert_eq!(snapshot.five_hour.unwrap().remaining_percent, 66.0);
        assert_eq!(
            ClaudeUsageSnapshot::cached(&history)
                .unwrap()
                .unwrap()
                .freshness,
            Freshness::Stale
        );
        assert_eq!(
            history.latest_limits(ProviderId::OpenAi).unwrap(),
            vec![openai]
        );
    }
    #[test]
    fn rejects_empty_foreign_or_duplicate_limits_before_persisting() {
        assert!(ClaudeUsageSnapshot::from_limits(vec![], Freshness::Fresh).is_err());
        let now = chrono::Utc::now();
        let limit = RateLimit::new(
            ProviderId::OpenAi,
            LimitKind::Weekly,
            "codex",
            28.0,
            now,
            now,
        )
        .unwrap();
        assert!(ClaudeUsageSnapshot::from_limits(vec![limit], Freshness::Fresh).is_err());
        let limit = RateLimit::new(
            ProviderId::Claude,
            LimitKind::Weekly,
            "claude_weekly",
            97.0,
            now,
            now,
        )
        .unwrap();
        assert!(
            ClaudeUsageSnapshot::from_limits(vec![limit.clone(), limit], Freshness::Fresh).is_err()
        );
    }
}
