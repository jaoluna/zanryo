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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub five_hour_forecast: Option<ForecastReport>,
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
    let five_hour_forecast = quota.five_hour.as_ref().map(|limit| {
        let matching: Vec<_> = samples
            .iter()
            .filter(|sample| sample.limit_id == limit.limit_id)
            .cloned()
            .collect();
        ForecastEngine::calculate_five_hour(&matching, now)
    });
    let account = history
        .latest_account_context(provider)?
        .unwrap_or_else(|| AccountContext::unknown(provider));

    Ok(Some(DashboardSnapshot {
        quota,
        forecast,
        five_hour_forecast,
        account,
    }))
}
