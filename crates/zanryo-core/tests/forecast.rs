use chrono::{DateTime, Duration, TimeZone, Utc};
use zanryo_core::{ForecastConfidence, ForecastEngine, ForecastStatus, LimitKind, RateLimit};

fn at(hour: u32, minute: u32) -> DateTime<Utc> {
    Utc.with_ymd_and_hms(2026, 7, 20, hour, minute, 0).unwrap()
}

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
fn collecting_history_with_fewer_than_three_samples() {
    let reset = at(9, 0) + Duration::days(5);
    let samples = vec![
        weekly(at(9, 0), 80.0, reset),
        weekly(at(9, 20), 79.0, reset),
    ];

    let report = ForecastEngine::calculate(&samples, at(9, 20));

    assert_eq!(report.status, ForecastStatus::CollectingHistory);
    assert_eq!(report.confidence, ForecastConfidence::Collecting);
    assert!(report.consumed_per_day.is_none());
    assert!(report.estimated_depletion_at.is_none());
    assert_eq!(report.chart.observed.len(), 2);
    assert!(report.chart.forecast.is_empty());
}

#[test]
fn collecting_history_when_span_is_under_thirty_minutes() {
    let reset = at(9, 0) + Duration::days(5);
    let samples = vec![
        weekly(at(9, 0), 80.0, reset),
        weekly(at(9, 10), 79.5, reset),
        weekly(at(9, 20), 79.0, reset),
    ];

    let report = ForecastEngine::calculate(&samples, at(9, 20));

    assert_eq!(report.status, ForecastStatus::CollectingHistory);
}

#[test]
fn blends_cycle_and_recent_pace_deterministically() {
    let reset = at(9, 0) + Duration::days(5);
    let samples = vec![
        weekly(at(9, 0) - Duration::hours(30), 90.0, reset),
        weekly(at(9, 0) - Duration::hours(24), 88.0, reset),
        weekly(at(9, 0) - Duration::hours(18), 84.0, reset),
        weekly(at(9, 0) - Duration::hours(12), 78.0, reset),
        weekly(at(9, 0) - Duration::hours(6), 72.0, reset),
        weekly(at(9, 0), 66.0, reset),
    ];

    let report = ForecastEngine::calculate(&samples, at(9, 0));

    assert_eq!(report.status, ForecastStatus::Estimated);
    assert!((report.consumed_per_day.unwrap() - 21.16).abs() < 0.01);
    assert!((report.sustainable_per_day.unwrap() - 13.20).abs() < 0.01);
    assert!((report.pace_difference.unwrap() - 7.96).abs() < 0.01);
    assert_eq!(
        report.estimated_depletion_at,
        Some(at(9, 0) + Duration::seconds(269_490))
    );
}

#[test]
fn excludes_other_cycles_spark_and_upward_corrections() {
    let reset = at(9, 0) + Duration::days(5);
    let old_reset = reset - Duration::days(7);
    let samples = vec![
        weekly(at(7, 0), 95.0, old_reset),
        RateLimit::new(LimitKind::Spark, "codex_bengalfox", 10.0, reset, at(8, 0)).unwrap(),
        weekly(at(8, 0), 80.0, reset),
        weekly(at(8, 30), 85.0, reset),
        weekly(at(9, 0), 78.0, reset),
        weekly(at(9, 30), 76.0, reset),
    ];

    let report = ForecastEngine::calculate(&samples, at(9, 30));

    assert_eq!(report.status, ForecastStatus::Estimated);
    assert!((report.consumed_per_day.unwrap() - 64.0).abs() < 0.01);
}

#[test]
fn builds_bounded_chart_series_and_sustainable_reference() {
    let now = at(9, 0);
    let reset = now + Duration::days(2);
    let samples = vec![
        weekly(now - Duration::hours(24), 70.0, reset),
        weekly(now - Duration::hours(12), 60.0, reset),
        weekly(now, 50.0, reset),
    ];

    let report = ForecastEngine::calculate(&samples, now);

    assert_eq!(report.chart.forecast.first().unwrap().at, now);
    assert_eq!(report.chart.forecast.last().unwrap().at, reset);
    assert_eq!(report.chart.sustainable.len(), 2);
    assert_eq!(report.chart.sustainable[0].at, reset - Duration::days(7));
    assert_eq!(report.chart.sustainable[0].remaining_percent, 100.0);
    assert_eq!(report.chart.sustainable.last().unwrap().at, reset);
    assert_eq!(
        report.chart.sustainable.last().unwrap().remaining_percent,
        0.0
    );
    assert!(report.chart.forecast.iter().all(|point| {
        (0.0..=100.0).contains(&point.remaining_percent)
            && point.uncertainty.low <= point.remaining_percent
            && point.uncertainty.high >= point.remaining_percent
    }));
}

#[test]
fn chart_observed_series_keeps_transitions_without_repeating_plateaus() {
    let now = at(9, 0);
    let reset = now + Duration::days(2);
    let samples = vec![
        weekly(now - Duration::hours(9), 90.0, reset),
        weekly(now - Duration::hours(8), 90.0, reset),
        weekly(now - Duration::hours(7), 90.0, reset),
        weekly(now - Duration::hours(6), 82.0, reset),
        weekly(now - Duration::hours(5), 82.0, reset),
        weekly(now - Duration::hours(4), 82.0, reset),
        weekly(now - Duration::hours(3), 70.0, reset),
        weekly(now - Duration::hours(2), 70.0, reset),
        weekly(now - Duration::hours(1), 70.0, reset),
    ];

    let report = ForecastEngine::calculate(&samples, now);
    let observed: Vec<_> = report
        .chart
        .observed
        .iter()
        .map(|point| point.remaining_percent)
        .collect();

    assert_eq!(observed, vec![100.0, 90.0, 90.0, 82.0, 82.0, 70.0, 70.0]);
    assert_eq!(
        report.chart.sustainable.first().unwrap().remaining_percent,
        100.0
    );
    assert_eq!(
        report.chart.sustainable.last().unwrap().remaining_percent,
        0.0
    );
}

#[test]
fn chart_observed_series_starts_at_cycle_start_when_first_sample_is_late() {
    let now = at(9, 0);
    let reset = now + Duration::days(5);
    let budget_start = reset - Duration::days(7);
    let samples = vec![
        weekly(budget_start + Duration::hours(3), 94.0, reset),
        weekly(budget_start + Duration::hours(4), 92.0, reset),
        weekly(budget_start + Duration::hours(5), 90.0, reset),
    ];

    let report = ForecastEngine::calculate(&samples, now);

    assert_eq!(report.chart.observed.first().unwrap().at, budget_start);
    assert_eq!(
        report.chart.observed.first().unwrap().remaining_percent,
        100.0
    );
}

#[test]
fn chart_observed_series_clips_reset_jitter_before_cycle_start() {
    let now = at(9, 0);
    let reset = now + Duration::days(5);
    let budget_start = reset - Duration::days(7);
    let samples = vec![
        weekly(budget_start - Duration::minutes(4), 100.0, reset),
        weekly(budget_start + Duration::minutes(10), 96.0, reset),
        weekly(budget_start + Duration::minutes(20), 96.0, reset),
        weekly(budget_start + Duration::minutes(30), 92.0, reset),
    ];

    let report = ForecastEngine::calculate(&samples, now);

    assert_eq!(report.chart.observed.first().unwrap().at, budget_start);
    assert_eq!(
        report.chart.observed.first().unwrap().remaining_percent,
        100.0
    );
    assert!(
        report
            .chart
            .observed
            .iter()
            .all(|point| point.at >= budget_start)
    );
    assert_eq!(
        report
            .chart
            .observed
            .iter()
            .map(|point| point.remaining_percent)
            .collect::<Vec<_>>(),
        vec![100.0, 96.0, 96.0, 92.0]
    );
}

#[test]
fn projects_from_now_when_latest_sample_is_stale() {
    let now = at(9, 0);
    let reset = now + Duration::days(1);
    let samples = vec![
        weekly(now - Duration::hours(30), 65.0, reset),
        weekly(now - Duration::hours(18), 55.0, reset),
        weekly(now - Duration::hours(6), 45.0, reset),
    ];

    let report = ForecastEngine::calculate(&samples, now);

    assert_eq!(report.status, ForecastStatus::Estimated);
    assert!((report.consumed_per_day.unwrap() - 20.0).abs() < 0.01);
    assert!((report.sustainable_per_day.unwrap() - 40.0).abs() < 0.01);
    assert_eq!(report.estimated_depletion_at, Some(now + Duration::days(2)));
    assert!((report.chart.forecast.first().unwrap().remaining_percent - 40.0).abs() < 0.01);
    assert!((report.chart.sustainable.first().unwrap().remaining_percent - 100.0).abs() < 0.01);
    assert_eq!(report.chart.sustainable.last().unwrap().at, reset);
    assert!((report.chart.sustainable.last().unwrap().remaining_percent - 0.0).abs() < 0.01);
}

#[test]
fn forecast_chart_stops_at_depletion_instead_of_drawing_zero_until_reset() {
    let now = at(9, 0);
    let reset = now + Duration::days(5);
    let samples = vec![
        weekly(now - Duration::days(2), 100.0, reset),
        weekly(now - Duration::days(1), 60.0, reset),
        weekly(now, 20.0, reset),
    ];

    let report = ForecastEngine::calculate(&samples, now);
    let last_forecast = report.chart.forecast.last().unwrap();

    assert!(last_forecast.at < reset);
    assert!((last_forecast.remaining_percent - 0.0).abs() < 0.01);
    assert_eq!(
        report.chart.sustainable.first().unwrap().at,
        reset - Duration::days(7)
    );
    assert_eq!(
        report.chart.sustainable.first().unwrap().remaining_percent,
        100.0
    );
    assert_eq!(report.chart.sustainable.last().unwrap().at, reset);
    assert_eq!(
        report.chart.sustainable.last().unwrap().remaining_percent,
        0.0
    );
}

#[test]
fn confidence_increases_with_coverage_and_stable_residuals() {
    let now = at(9, 0);
    let reset = now + Duration::days(5);
    let samples: Vec<_> = (0..=24)
        .map(|hour| {
            let observed = now - Duration::hours(24 - hour);
            weekly(observed, 90.0 - hour as f64, reset)
        })
        .collect();

    let report = ForecastEngine::calculate(&samples, now);

    assert_eq!(report.confidence, ForecastConfidence::High);
    let range = report.rate_range.unwrap();
    assert!(range.low <= report.consumed_per_day.unwrap());
    assert!(range.high >= report.consumed_per_day.unwrap());
}
