use crate::{
    ForecastEngine, ForecastReport, Freshness, HistoryRepository, LimitKind, ProviderId, RateLimit,
    Result, ZanryoError,
};
use serde::Serialize;

const FORECAST_HISTORY_DAYS: i64 = 8;
const RESET_MATCH_SECONDS: i64 = 5 * 60;

/// Additive provider-aware DTO. The OpenAI legacy dashboard is unchanged.
#[derive(Debug, Clone, Serialize)]
pub struct ClaudeUsageSnapshot {
    pub provider: ProviderId,
    pub five_hour: Option<RateLimit>,
    pub weekly: Option<RateLimit>,
    pub weekly_forecast: Option<ForecastReport>,
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
            weekly_forecast: None,
            freshness,
        })
    }
    pub fn cached(history: &HistoryRepository) -> Result<Option<Self>> {
        let limits = history.latest_limits(ProviderId::Claude)?;
        if limits.is_empty() {
            Ok(None)
        } else {
            let mut snapshot = Self::from_limits(limits, Freshness::Stale)?;
            snapshot.weekly_forecast =
                forecast_from_history(history, snapshot.weekly.as_ref(), chrono::Utc::now())?;
            Ok(Some(snapshot))
        }
    }
    pub fn record(history: &HistoryRepository, limits: Vec<RateLimit>) -> Result<Self> {
        let mut snapshot = Self::from_limits(limits.clone(), Freshness::Fresh)?;
        history.insert_limits(&limits)?;
        snapshot.weekly_forecast =
            forecast_from_history(history, snapshot.weekly.as_ref(), chrono::Utc::now())?;
        Ok(snapshot)
    }
}

fn forecast_from_history(
    history: &HistoryRepository,
    weekly: Option<&RateLimit>,
    now: chrono::DateTime<chrono::Utc>,
) -> Result<Option<ForecastReport>> {
    let Some(weekly) = weekly else {
        return Ok(None);
    };

    // Claude's weekly window is a distinct quota. Keep its exact provider and
    // limit identity; never mix in the five-hour window or another weekly ID.
    let samples: Vec<_> = history
        .limits_since(
            ProviderId::Claude,
            now - chrono::Duration::days(FORECAST_HISTORY_DAYS),
        )?
        .into_iter()
        .filter(|sample| {
            sample.provider == ProviderId::Claude
                && sample.kind == LimitKind::Weekly
                && sample.limit_id == weekly.limit_id
        })
        .collect();

    let current_reset = samples
        .iter()
        .max_by_key(|sample| sample.observed_at)
        .map(|sample| sample.resets_at);
    let cycle_samples: Vec<_> = samples
        .into_iter()
        .filter(|sample| {
            current_reset.is_some_and(|reset| {
                (sample.resets_at - reset).num_seconds().abs() <= RESET_MATCH_SECONDS
            })
        })
        .collect();
    let mut forecast = ForecastEngine::calculate(&cycle_samples, now);

    // The generic engine adds a synthetic 100% cycle-start point. The Claude
    // observed history must contain recorded samples only.
    forecast.chart.observed.retain(|point| {
        cycle_samples.iter().any(|sample| {
            sample.observed_at == point.at
                && (sample.remaining_percent - point.remaining_percent).abs() < f64::EPSILON
        })
    });

    // A stale cached quota can outlive its reset. Keep its recorded history,
    // but do not present a current pace or projection for an expired cycle.
    if weekly.resets_at <= now {
        forecast.status = crate::ForecastStatus::CollectingHistory;
        forecast.confidence = crate::ForecastConfidence::Collecting;
        forecast.consumed_per_day = None;
        forecast.sustainable_per_day = None;
        forecast.pace_difference = None;
        forecast.estimated_depletion_at = None;
        forecast.rate_range = None;
        forecast.chart.forecast.clear();
        forecast.chart.sustainable.clear();
    }

    Ok(Some(forecast))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make(
        provider: ProviderId,
        kind: LimitKind,
        id: &str,
        percent: f64,
        resets_at: chrono::DateTime<chrono::Utc>,
        observed_at: chrono::DateTime<chrono::Utc>,
    ) -> RateLimit {
        RateLimit::new(provider, kind, id, percent, resets_at, observed_at).unwrap()
    }

    #[test]
    fn optional_windows_roundtrip_separately_and_leave_openai_unchanged() {
        let dir = tempfile::tempdir().unwrap();
        let history = HistoryRepository::open(dir.path().join("history.sqlite3")).unwrap();
        let now = chrono::Utc::now();
        let reset = now + chrono::Duration::hours(2);
        let openai = make(
            ProviderId::OpenAi,
            LimitKind::Weekly,
            "codex",
            28.0,
            reset,
            now,
        );
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
                reset,
                now,
            )],
        )
        .unwrap();
        assert!(snapshot.weekly.is_none());
        assert!(snapshot.weekly_forecast.is_none());
        assert_eq!(snapshot.five_hour.unwrap().remaining_percent, 66.0);
        let cached = ClaudeUsageSnapshot::cached(&history).unwrap().unwrap();
        assert_eq!(cached.freshness, Freshness::Stale);
        assert!(cached.weekly_forecast.is_none());
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

    #[test]
    fn records_only_real_weekly_samples_before_forecast_minimum_history() {
        let dir = tempfile::tempdir().unwrap();
        let history = HistoryRepository::open(dir.path().join("history.sqlite3")).unwrap();
        let now = chrono::Utc::now();
        let sample = make(
            ProviderId::Claude,
            LimitKind::Weekly,
            "claude_weekly",
            91.0,
            now + chrono::Duration::days(3),
            now - chrono::Duration::minutes(10),
        );

        let snapshot = ClaudeUsageSnapshot::record(&history, vec![sample.clone()]).unwrap();
        let forecast = snapshot.weekly_forecast.unwrap();
        assert_eq!(forecast.status, crate::ForecastStatus::CollectingHistory);
        assert_eq!(forecast.chart.observed.len(), 1);
        assert_eq!(forecast.chart.observed[0].at, sample.observed_at);
        assert_eq!(forecast.chart.observed[0].remaining_percent, 91.0);
        assert!(forecast.chart.forecast.is_empty());
    }

    #[test]
    fn estimates_after_three_weekly_samples_without_synthetic_observed_anchor() {
        let dir = tempfile::tempdir().unwrap();
        let history = HistoryRepository::open(dir.path().join("history.sqlite3")).unwrap();
        let now = chrono::Utc::now();
        let reset = now + chrono::Duration::days(3);
        let observed_at = [
            now - chrono::Duration::hours(1),
            now - chrono::Duration::minutes(30),
            now,
        ];
        let limits: Vec<_> = observed_at
            .into_iter()
            .zip([95.0, 90.0, 85.0])
            .map(|(at, remaining)| {
                make(
                    ProviderId::Claude,
                    LimitKind::Weekly,
                    "claude_weekly",
                    remaining,
                    reset,
                    at,
                )
            })
            .collect();

        assert!(
            ClaudeUsageSnapshot::from_limits(vec![limits[2].clone()], Freshness::Fresh)
                .unwrap()
                .weekly_forecast
                .is_none()
        );
        history.insert_limits(&limits[..2]).unwrap();
        let snapshot = ClaudeUsageSnapshot::record(&history, vec![limits[2].clone()]).unwrap();
        let forecast = snapshot.weekly_forecast.unwrap();
        assert_eq!(forecast.status, crate::ForecastStatus::Estimated);
        assert_eq!(forecast.chart.observed.len(), 3);
        assert!(forecast.consumed_per_day.is_some());
        for point in &forecast.chart.observed {
            assert!(limits.iter().any(|sample| {
                sample.observed_at == point.at
                    && (sample.remaining_percent - point.remaining_percent).abs() < f64::EPSILON
            }));
        }
        assert!(forecast.chart.sustainable.iter().any(|point| {
            point.at == reset - chrono::Duration::days(7) && point.remaining_percent == 100.0
        }));
    }

    #[test]
    fn cached_forecast_filters_provider_window_id_and_prior_reset_cycle() {
        let dir = tempfile::tempdir().unwrap();
        let history = HistoryRepository::open(dir.path().join("history.sqlite3")).unwrap();
        let now = chrono::Utc::now();
        let reset = now + chrono::Duration::days(3);
        let old_reset = reset - chrono::Duration::days(7);
        let mut recorded = vec![
            make(
                ProviderId::OpenAi,
                LimitKind::Weekly,
                "codex",
                5.0,
                reset,
                now - chrono::Duration::minutes(50),
            ),
            make(
                ProviderId::Claude,
                LimitKind::FiveHour,
                "claude_five_hour",
                1.0,
                now + chrono::Duration::hours(2),
                now - chrono::Duration::minutes(40),
            ),
            make(
                ProviderId::Claude,
                LimitKind::Weekly,
                "other_weekly_id",
                2.0,
                reset,
                now - chrono::Duration::minutes(35),
            ),
        ];
        for (offset, remaining) in [(240, 99.0), (210, 98.0), (180, 97.0)] {
            recorded.push(make(
                ProviderId::Claude,
                LimitKind::Weekly,
                "claude_weekly",
                remaining,
                old_reset,
                now - chrono::Duration::minutes(offset),
            ));
        }
        let current = [
            make(
                ProviderId::Claude,
                LimitKind::Weekly,
                "claude_weekly",
                90.0,
                reset,
                now - chrono::Duration::minutes(60),
            ),
            make(
                ProviderId::Claude,
                LimitKind::Weekly,
                "claude_weekly",
                80.0,
                reset,
                now - chrono::Duration::minutes(30),
            ),
            make(
                ProviderId::Claude,
                LimitKind::Weekly,
                "claude_weekly",
                70.0,
                reset,
                now,
            ),
        ];
        recorded.extend(current.clone());
        history.insert_limits(&recorded).unwrap();

        let snapshot = ClaudeUsageSnapshot::cached(&history).unwrap().unwrap();
        assert_eq!(snapshot.freshness, Freshness::Stale);
        let forecast = snapshot.weekly_forecast.unwrap();
        assert_eq!(forecast.status, crate::ForecastStatus::Estimated);
        assert_eq!(forecast.chart.observed.len(), 3);
        for point in &forecast.chart.observed {
            assert!(current.iter().any(|sample| {
                sample.observed_at == point.at
                    && (sample.remaining_percent - point.remaining_percent).abs() < f64::EPSILON
            }));
        }
    }

    #[test]
    fn expired_weekly_cycle_keeps_observations_but_clears_all_projections() {
        let dir = tempfile::tempdir().unwrap();
        let history = HistoryRepository::open(dir.path().join("history.sqlite3")).unwrap();
        let now = chrono::Utc::now();
        let reset = now - chrono::Duration::hours(1);
        let samples = [
            make(
                ProviderId::Claude,
                LimitKind::Weekly,
                "claude_weekly",
                90.0,
                reset,
                now - chrono::Duration::hours(3),
            ),
            make(
                ProviderId::Claude,
                LimitKind::Weekly,
                "claude_weekly",
                80.0,
                reset,
                now - chrono::Duration::hours(2),
            ),
            make(
                ProviderId::Claude,
                LimitKind::Weekly,
                "claude_weekly",
                70.0,
                reset,
                now - chrono::Duration::minutes(61),
            ),
        ];
        history.insert_limits(&samples).unwrap();

        let snapshot = ClaudeUsageSnapshot::cached(&history).unwrap().unwrap();
        let forecast = snapshot.weekly_forecast.unwrap();
        assert_eq!(forecast.status, crate::ForecastStatus::CollectingHistory);
        assert_eq!(forecast.confidence, crate::ForecastConfidence::Collecting);
        assert_eq!(forecast.chart.observed.len(), samples.len());
        assert!(forecast.consumed_per_day.is_none());
        assert!(forecast.sustainable_per_day.is_none());
        assert!(forecast.pace_difference.is_none());
        assert!(forecast.estimated_depletion_at.is_none());
        assert!(forecast.rate_range.is_none());
        assert!(forecast.chart.forecast.is_empty());
        assert!(forecast.chart.sustainable.is_empty());
        for (point, sample) in forecast.chart.observed.iter().zip(samples) {
            assert_eq!(point.at, sample.observed_at);
            assert_eq!(point.remaining_percent, sample.remaining_percent);
        }
    }
}
