use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};

use crate::{ForecastEngine, ForecastReport, Freshness, HistoryRepository, QuotaSnapshot, Result};

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct DashboardSnapshot {
    pub quota: QuotaSnapshot,
    pub forecast: ForecastReport,
}

pub fn cached_dashboard(
    history: &HistoryRepository,
    now: DateTime<Utc>,
) -> Result<Option<DashboardSnapshot>> {
    let latest = history.latest_limits()?;
    if latest.is_empty() {
        return Ok(None);
    }

    let quota = QuotaSnapshot::from_limits(latest, Freshness::Stale)?;
    let samples = history.limits_since(now - Duration::days(8))?;
    let forecast = ForecastEngine::calculate(&samples, now);

    Ok(Some(DashboardSnapshot { quota, forecast }))
}
