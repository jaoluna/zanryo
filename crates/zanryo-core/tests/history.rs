use chrono::{Duration, TimeZone, Utc};
use tempfile::tempdir;
use zanryo_core::{HistoryRepository, LimitKind, RateLimit};

fn weekly_at(day: u32, remaining_percent: f64) -> RateLimit {
    let observed_at = Utc.with_ymd_and_hms(2026, 1, day, 12, 0, 0).unwrap();
    RateLimit::new(
        LimitKind::Weekly,
        "codex",
        remaining_percent,
        observed_at + Duration::days(7),
        observed_at,
    )
    .unwrap()
}

#[test]
fn round_trips_every_rate_limit_field() {
    let directory = tempdir().unwrap();
    let repository = HistoryRepository::open(directory.path().join("history.sqlite3")).unwrap();
    let original = weekly_at(1, 82.0);

    repository
        .insert_limits(std::slice::from_ref(&original))
        .unwrap();
    let stored = repository.latest_limits().unwrap();

    assert_eq!(stored, vec![original]);
}

#[test]
fn prunes_only_samples_older_than_the_cutoff() {
    let directory = tempdir().unwrap();
    let repository = HistoryRepository::open(directory.path().join("history.sqlite3")).unwrap();
    let old = weekly_at(1, 95.0);
    let recent = weekly_at(20, 70.0);

    repository.insert_limits(&[old]).unwrap();
    repository
        .insert_limits(std::slice::from_ref(&recent))
        .unwrap();
    repository
        .prune_before(Utc.with_ymd_and_hms(2026, 1, 10, 0, 0, 0).unwrap())
        .unwrap();

    let stored = repository
        .limits_since(Utc.with_ymd_and_hms(2026, 1, 1, 0, 0, 0).unwrap())
        .unwrap();
    assert_eq!(stored, vec![recent]);
}
