use chrono::{Duration, TimeZone, Utc};
use zanryo_core::{
    ForecastEngine, ForecastStatus, Freshness, HistoryRepository, LimitKind, ProviderId, RateLimit,
    cached_dashboard,
};

fn samples(provider: ProviderId) -> Vec<RateLimit> {
    let now = Utc.with_ymd_and_hms(2026, 9, 26, 12, 0, 0).unwrap();
    (0..3)
        .map(|i| {
            RateLimit::new(
                provider,
                LimitKind::FiveHour,
                "primary",
                80.0 - f64::from(i) * 10.0,
                now + Duration::hours(2),
                now - Duration::minutes(60 - i64::from(i) * 30),
            )
            .unwrap()
        })
        .collect()
}

#[test]
fn five_hour_uses_its_own_cycle_scale_rate_and_real_samples() {
    let data = samples(ProviderId::OpenAi);
    let now = data[2].observed_at;
    let mut mixed = data.clone();
    mixed.push(
        RateLimit::new(
            ProviderId::OpenAi,
            LimitKind::Weekly,
            "weekly",
            1.0,
            now + Duration::days(3),
            now,
        )
        .unwrap(),
    );
    mixed.push(
        RateLimit::new(
            ProviderId::OpenAi,
            LimitKind::FiveHour,
            "primary",
            0.0,
            now - Duration::hours(3),
            now - Duration::hours(4),
        )
        .unwrap(),
    );
    mixed.push(
        RateLimit::new(
            ProviderId::OpenAi,
            LimitKind::FiveHour,
            "unrelated",
            2.0,
            data[2].resets_at,
            now - Duration::minutes(10),
        )
        .unwrap(),
    );
    let result = ForecastEngine::calculate_five_hour(&mixed, now);
    assert_eq!(result.status, ForecastStatus::Estimated);
    assert_eq!(
        result
            .chart
            .observed
            .iter()
            .map(|p| p.remaining_percent)
            .collect::<Vec<_>>(),
        vec![80.0, 70.0, 60.0]
    );
    assert_eq!(
        result.chart.sustainable[0].at,
        data[2].resets_at - Duration::hours(5)
    );
    assert!((result.consumed_per_day.unwrap() / 24.0 - 20.0).abs() < 0.001);
    assert!(
        result
            .chart
            .forecast
            .iter()
            .all(|p| p.at <= data[2].resets_at)
    );
    assert!(
        ForecastEngine::calculate_five_hour(&mixed, data[2].resets_at)
            .chart
            .forecast
            .is_empty()
    );
}

#[test]
fn reset_starts_a_new_cycle_without_joining_old_balance() {
    let mut data = samples(ProviderId::Claude);
    let reset = data[2].resets_at;
    data.push(
        RateLimit::new(
            ProviderId::Claude,
            LimitKind::FiveHour,
            "primary",
            100.0,
            reset + Duration::hours(5),
            reset,
        )
        .unwrap(),
    );
    let result = ForecastEngine::calculate_five_hour(&data, reset);
    assert_eq!(result.status, ForecastStatus::CollectingHistory);
    assert_eq!(result.chart.observed.len(), 1);
    assert_eq!(result.chart.observed[0].at, reset);
    assert_eq!(result.chart.observed[0].remaining_percent, 100.0);
}

#[test]
fn future_readings_cannot_move_the_selected_five_hour_cycle() {
    let mut data = samples(ProviderId::Claude);
    let now = data[2].observed_at;
    data.push(
        RateLimit::new(
            ProviderId::Claude,
            LimitKind::FiveHour,
            "primary",
            100.0,
            now + Duration::hours(6),
            now + Duration::hours(1),
        )
        .unwrap(),
    );
    let result = ForecastEngine::calculate_five_hour(&data, now);
    assert_eq!(result.chart.observed.last().unwrap().at, now);
    assert_eq!(
        result.chart.observed.last().unwrap().remaining_percent,
        60.0
    );
}

#[test]
fn provider_boundaries_and_flat_values_remain_honest() {
    let mut data = samples(ProviderId::Claude);
    let now = data[2].observed_at;
    for limit in &mut data {
        limit.remaining_percent = 97.0;
    }
    let result = ForecastEngine::calculate_five_hour(&data, now);
    assert_eq!(result.consumed_per_day, Some(0.0));
    assert!(
        result
            .chart
            .observed
            .iter()
            .all(|p| p.remaining_percent == 97.0)
    );
    data.push(samples(ProviderId::OpenAi)[2].clone());
    assert!(
        ForecastEngine::calculate_five_hour(&data, now)
            .chart
            .observed
            .is_empty()
    );
}

#[test]
fn codex_cached_bridge_exposes_separate_optional_five_hour_report() {
    let dir = tempfile::tempdir().unwrap();
    let history = HistoryRepository::open(dir.path().join("history.sqlite3")).unwrap();
    let mut data = samples(ProviderId::OpenAi);
    let now = data[2].observed_at;
    data.push(
        RateLimit::new(
            ProviderId::OpenAi,
            LimitKind::Weekly,
            "weekly",
            21.0,
            now + Duration::days(3),
            now,
        )
        .unwrap(),
    );
    history.insert_limits(&data).unwrap();
    let snapshot = cached_dashboard(&history, ProviderId::OpenAi, now)
        .unwrap()
        .unwrap();
    assert_eq!(snapshot.quota.freshness, Freshness::Stale);
    assert_eq!(snapshot.forecast.chart.observed[0].remaining_percent, 21.0);
    assert_eq!(
        snapshot
            .five_hour_forecast
            .as_ref()
            .unwrap()
            .chart
            .observed
            .last()
            .unwrap()
            .remaining_percent,
        60.0
    );
    let value = serde_json::to_value(snapshot).unwrap();
    assert!(value["five_hour_forecast"].is_object());
}

#[test]
fn claude_record_and_cache_keep_both_reports_separate() {
    use zanryo_core::claude::ClaudeUsageSnapshot;
    let dir = tempfile::tempdir().unwrap();
    let history = HistoryRepository::open(dir.path().join("history.sqlite3")).unwrap();
    let now = Utc::now();
    let old = samples(ProviderId::Claude);
    let shift = now - old[2].observed_at;
    let data: Vec<_> = old
        .into_iter()
        .map(|mut s| {
            s.observed_at += shift;
            s.resets_at += shift;
            s
        })
        .collect();
    history.insert_limits(&data[..2]).unwrap();
    let weekly = RateLimit::new(
        ProviderId::Claude,
        LimitKind::Weekly,
        "weekly",
        21.0,
        now + Duration::days(3),
        now,
    )
    .unwrap();
    let snapshot = ClaudeUsageSnapshot::record(&history, vec![data[2].clone(), weekly]).unwrap();
    for snapshot in [
        snapshot,
        ClaudeUsageSnapshot::cached(&history).unwrap().unwrap(),
    ] {
        assert_eq!(
            snapshot.weekly_forecast.unwrap().chart.observed[0].remaining_percent,
            21.0
        );
        let five = snapshot.five_hour_forecast.unwrap();
        assert_eq!(five.chart.observed.last().unwrap().remaining_percent, 60.0);
        assert_eq!(
            five.chart.sustainable[0].at,
            data[2].resets_at - Duration::hours(5)
        );
    }
}
