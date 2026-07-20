use chrono::{DateTime, Duration, TimeZone, Utc};
use tempfile::tempdir;
use zanryo_core::{
    ForecastStatus, Freshness, HistoryRepository, LimitKind, RateLimit, cached_dashboard,
};

fn weekly(
    observed_at: DateTime<Utc>,
    remaining_percent: f64,
    resets_at: DateTime<Utc>,
) -> RateLimit {
    RateLimit::new(
        LimitKind::Weekly,
        "codex",
        remaining_percent,
        resets_at,
        observed_at,
    )
    .unwrap()
}

#[test]
fn cached_dashboard_combines_latest_quota_with_history_forecast() {
    let directory = tempdir().unwrap();
    let history = HistoryRepository::open(directory.path().join("history.sqlite3")).unwrap();
    let now = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();
    let reset = now + Duration::days(5);
    let samples = vec![
        weekly(now - Duration::hours(2), 80.0, reset),
        weekly(now - Duration::hours(1), 78.0, reset),
        weekly(now, 76.0, reset),
    ];
    history.insert_limits(&samples).unwrap();

    let dashboard = cached_dashboard(&history, now).unwrap().unwrap();

    assert_eq!(dashboard.quota.freshness, Freshness::Stale);
    assert_eq!(dashboard.quota.weekly.remaining_percent, 76.0);
    assert_eq!(dashboard.forecast.status, ForecastStatus::Estimated);
}
