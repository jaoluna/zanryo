use chrono::{TimeZone, Utc};
use rusqlite::Connection;
use tempfile::tempdir;
use zanryo_core::{AccountContext, HistoryRepository, PlanType};

fn at(hour: u32, minute: u32) -> chrono::DateTime<Utc> {
    Utc.with_ymd_and_hms(2026, 7, 21, hour, minute, 0).unwrap()
}

#[test]
fn app_server_plan_types_map_only_known_values() {
    for (raw, expected) in [
        ("free", PlanType::Free),
        ("go", PlanType::Go),
        ("plus", PlanType::Plus),
        ("pro", PlanType::Pro),
        ("pro_lite", PlanType::ProLite),
        ("team", PlanType::Team),
        ("business", PlanType::Business),
        ("enterprise", PlanType::Enterprise),
        ("edu", PlanType::Edu),
        ("future_plan", PlanType::Unknown),
        ("Plus", PlanType::Unknown),
    ] {
        assert_eq!(PlanType::from_app_server(raw), expected);
    }
}

#[test]
fn unknown_context_has_no_timestamp_or_identifier_fields() {
    let context = AccountContext::unknown();
    let value = serde_json::to_value(context).unwrap();

    assert_eq!(value["plan_type"], "unknown");
    assert!(value["observed_at"].is_null());
    assert!(value.get("email").is_none());
    assert!(value.get("account_id").is_none());
}

#[test]
fn unknown_raw_plan_is_safe_and_has_no_identifier_fields() {
    let context = AccountContext::new(PlanType::from_app_server("future_plan"), Utc::now());
    let value = serde_json::to_value(context).unwrap();

    assert_eq!(value["plan_type"], "unknown");
    assert!(value["observed_at"].is_null());
    assert!(value.get("email").is_none());
    assert!(value.get("account_id").is_none());
}

#[test]
fn sqlite_unmapped_plan_is_deleted_before_returning_none() {
    let directory = tempdir().unwrap();
    let path = directory.path().join("history.sqlite3");
    let repository = HistoryRepository::open(&path).unwrap();
    repository
        .upsert_account_context(&AccountContext::new(PlanType::Plus, at(9, 0)))
        .unwrap();
    Connection::open(&path)
        .unwrap()
        .execute("UPDATE account_context SET plan_type = 'future_plan'", [])
        .unwrap();

    assert_eq!(repository.latest_account_context().unwrap(), None);

    let cached_rows: i64 = Connection::open(&path)
        .unwrap()
        .query_row("SELECT COUNT(*) FROM account_context", [], |row| row.get(0))
        .unwrap();

    assert_eq!(cached_rows, 0);
}

#[test]
fn upserting_unknown_context_suppresses_the_cached_row() {
    let directory = tempdir().unwrap();
    let repository = HistoryRepository::open(directory.path().join("history.sqlite3")).unwrap();
    repository
        .upsert_account_context(&AccountContext::new(PlanType::Plus, at(9, 0)))
        .unwrap();

    repository
        .upsert_account_context(&AccountContext::new(PlanType::Unknown, at(10, 0)))
        .unwrap();

    assert_eq!(repository.latest_account_context().unwrap(), None);
}

#[test]
fn latest_account_context_round_trips_only_plan_and_observed_time() {
    let repository =
        HistoryRepository::open(tempdir().unwrap().path().join("history.sqlite3")).unwrap();
    let saved = AccountContext::new(PlanType::Plus, at(9, 0));

    repository.upsert_account_context(&saved).unwrap();

    assert_eq!(repository.latest_account_context().unwrap(), Some(saved));
}
