use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};

use crate::{
    AccountContext, ForecastEngine, ForecastReport, Freshness, HistoryRepository, ProviderId,
    QuotaSnapshot, Result,
};

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct DashboardSnapshot {
    pub quota: QuotaSnapshot,
    pub forecast: ForecastReport,
    pub account: AccountContext,
}

pub fn cached_dashboard(
    history: &HistoryRepository,
    provider: ProviderId,
    now: DateTime<Utc>,
) -> Result<Option<DashboardSnapshot>> {
    let latest = history.latest_limits(provider)?;
    if latest.is_empty() {
        return Ok(None);
    }

    let quota = QuotaSnapshot::from_limits(provider, latest, Freshness::Stale)?;
    let samples = history.limits_since(provider, now - Duration::days(8))?;
    let forecast = ForecastEngine::calculate(&samples, now);
    let account = history
        .latest_account_context(provider)?
        .unwrap_or_else(|| AccountContext::unknown(provider));

    Ok(Some(DashboardSnapshot {
        quota,
        forecast,
        account,
    }))
}
