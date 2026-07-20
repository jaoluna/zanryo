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
    assert_eq!(report.chart.sustainable[0].remaining_percent, 50.0);
    assert_eq!(report.chart.sustainable[1].remaining_percent, 0.0);
    assert!(report.chart.forecast.iter().all(|point| {
        (0.0..=100.0).contains(&point.remaining_percent)
            && point.uncertainty.low <= point.remaining_percent
            && point.uncertainty.high >= point.remaining_percent
    }));
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
