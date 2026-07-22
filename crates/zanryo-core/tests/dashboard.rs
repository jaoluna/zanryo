use chrono::{DateTime, Duration, TimeZone, Utc};
use tempfile::tempdir;
use zanryo_core::{
    AccountContext, ForecastStatus, Freshness, HistoryRepository, LimitKind, PlanType, ProviderId,
    RateLimit, cached_dashboard,
};

fn weekly(
    observed_at: DateTime<Utc>,
    remaining_percent: f64,
    resets_at: DateTime<Utc>,
) -> RateLimit {
    RateLimit::new(
        ProviderId::OpenAi,
        LimitKind::Weekly,
        "codex",
        remaining_percent,
        resets_at,
        observed_at,
    )
    .unwrap()
}

fn spark(
    observed_at: DateTime<Utc>,
    remaining_percent: f64,
    resets_at: DateTime<Utc>,
) -> RateLimit {
    RateLimit::new(
        ProviderId::OpenAi,
        LimitKind::Spark,
        "codex_bengalfox",
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

    let dashboard = cached_dashboard(&history, ProviderId::OpenAi, now)
        .unwrap()
        .unwrap();

    assert_eq!(dashboard.quota.freshness, Freshness::Stale);
    assert_eq!(dashboard.quota.weekly.remaining_percent, 76.0);
    assert_eq!(dashboard.forecast.status, ForecastStatus::Estimated);
    assert_eq!(
        dashboard.account,
        AccountContext::unknown(ProviderId::OpenAi)
    );
    assert_eq!(dashboard.account.plan_type, PlanType::Unknown);
}

#[test]
fn dashboard_serialization_preserves_legacy_public_shape() {
    let directory = tempdir().unwrap();
    let history = HistoryRepository::open(directory.path().join("history.sqlite3")).unwrap();
    let now = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();
    let reset = now + Duration::days(5);
    history
        .insert_limits(&[
            weekly(now, 76.0, reset),
            spark(now, 72.0, reset + Duration::days(1)),
        ])
        .unwrap();

    let dashboard = cached_dashboard(&history, ProviderId::OpenAi, now)
        .unwrap()
        .unwrap();
    let value = serde_json::to_value(&dashboard).unwrap();
    let quota = value["quota"].as_object().unwrap();

    assert!(!quota.contains_key("provider"));
    assert!(!quota.contains_key("five_hour"));
    assert!(!quota.contains_key("fable"));
    assert!(value["quota"]["weekly"].get("provider").is_none());
    assert!(value["quota"]["spark"].get("provider").is_none());
    assert!(value["account"].get("provider").is_none());

    let decoded: zanryo_core::DashboardSnapshot = serde_json::from_value(value).unwrap();
    assert_eq!(decoded.quota.provider, ProviderId::OpenAi);
    assert_eq!(decoded.quota.weekly.provider, ProviderId::OpenAi);
    assert_eq!(decoded.quota.spark.unwrap().provider, ProviderId::OpenAi);
    assert_eq!(decoded.account.provider, ProviderId::OpenAi);
    assert!(decoded.quota.five_hour.is_none());
    assert!(decoded.quota.fable.is_none());
}
