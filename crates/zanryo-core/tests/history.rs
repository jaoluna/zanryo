use chrono::{Duration, TimeZone, Utc};
use rusqlite::Connection;
use tempfile::{NamedTempFile, tempdir};
use zanryo_core::{
    AccountContext, HistoryRepository, LimitKind, PlanType, ProviderId, RateLimit, ZanryoError,
};

const LEGACY_SCHEMA: &str = "
CREATE TABLE quota_samples (
    id INTEGER PRIMARY KEY,
    observed_at TEXT NOT NULL,
    limit_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    remaining_percent REAL NOT NULL CHECK (remaining_percent BETWEEN 0 AND 100),
    resets_at TEXT NOT NULL,
    UNIQUE(observed_at, limit_id)
);

CREATE INDEX idx_quota_samples_observed
ON quota_samples(observed_at);

CREATE TABLE account_context (
    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
    plan_type TEXT NOT NULL,
    observed_at TEXT NOT NULL
);
";

fn at(hour: u32, minute: u32) -> chrono::DateTime<Utc> {
    Utc.with_ymd_and_hms(2026, 7, 21, hour, minute, 0).unwrap()
}

fn weekly_at(day: u32, remaining_percent: f64) -> RateLimit {
    let observed_at = Utc.with_ymd_and_hms(2026, 1, day, 12, 0, 0).unwrap();
    RateLimit::new(
        ProviderId::OpenAi,
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
    let stored = repository.latest_limits(ProviderId::OpenAi).unwrap();

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
        .prune_before(
            ProviderId::OpenAi,
            Utc.with_ymd_and_hms(2026, 1, 10, 0, 0, 0).unwrap(),
        )
        .unwrap();

    let stored = repository
        .limits_since(
            ProviderId::OpenAi,
            Utc.with_ymd_and_hms(2026, 1, 1, 0, 0, 0).unwrap(),
        )
        .unwrap();
    assert_eq!(stored, vec![recent]);
}

#[test]
fn migrates_legacy_rows_to_openai_without_data_loss() {
    let file = NamedTempFile::new().unwrap();
    let connection = Connection::open(file.path()).unwrap();
    connection.execute_batch(LEGACY_SCHEMA).unwrap();
    connection
        .execute(
            "INSERT INTO quota_samples (id, observed_at, limit_id, kind, remaining_percent, resets_at)
             VALUES (314, ?1, 'codex', 'weekly', 55, ?2)",
            rusqlite::params![at(9, 0), at(17, 0)],
        )
        .unwrap();
    connection
        .execute(
            "INSERT INTO account_context (singleton, plan_type, observed_at)
             VALUES (1, 'plus', ?1)",
            [at(9, 0)],
        )
        .unwrap();
    drop(connection);

    let history = HistoryRepository::open(file.path()).unwrap();
    let limits = history.latest_limits(ProviderId::OpenAi).unwrap();
    let account = history
        .latest_account_context(ProviderId::OpenAi)
        .unwrap()
        .unwrap();

    assert_eq!(limits.len(), 1);
    assert_eq!(
        limits[0],
        RateLimit::new(
            ProviderId::OpenAi,
            LimitKind::Weekly,
            "codex",
            55.0,
            at(17, 0),
            at(9, 0),
        )
        .unwrap()
    );
    assert_eq!(
        account,
        AccountContext::new(ProviderId::OpenAi, PlanType::Plus, at(9, 0))
    );
    assert!(
        history
            .latest_limits(ProviderId::Claude)
            .unwrap()
            .is_empty()
    );
    drop(history);

    let connection = Connection::open(file.path()).unwrap();
    let migrated_id: i64 = connection
        .query_row("SELECT id FROM quota_samples", [], |row| row.get(0))
        .unwrap();
    assert_eq!(migrated_id, 314);
    let user_version: i64 = connection
        .query_row("PRAGMA user_version", [], |row| row.get(0))
        .unwrap();
    assert_eq!(user_version, 2);
}

#[test]
fn account_context_deletion_is_provider_scoped() {
    let directory = tempdir().unwrap();
    let history = HistoryRepository::open(directory.path().join("history.sqlite3")).unwrap();
    history
        .upsert_account_context(&AccountContext::new(
            ProviderId::OpenAi,
            PlanType::Plus,
            at(9, 0),
        ))
        .unwrap();
    history
        .upsert_account_context(&AccountContext::new(
            ProviderId::Claude,
            PlanType::Pro,
            at(10, 0),
        ))
        .unwrap();

    history
        .upsert_account_context(&AccountContext::unknown(ProviderId::OpenAi))
        .unwrap();

    assert_eq!(
        history.latest_account_context(ProviderId::OpenAi).unwrap(),
        None
    );
    assert_eq!(
        history.latest_account_context(ProviderId::Claude).unwrap(),
        Some(AccountContext::new(
            ProviderId::Claude,
            PlanType::Pro,
            at(10, 0),
        ))
    );
}

#[test]
fn refuses_to_open_a_future_schema_without_modifying_it() {
    let file = NamedTempFile::new().unwrap();
    let connection = Connection::open(file.path()).unwrap();
    connection
        .execute_batch(
            "
            CREATE TABLE future_sentinel (value TEXT NOT NULL);
            INSERT INTO future_sentinel (value) VALUES ('preserve me');
            PRAGMA user_version = 3;
            ",
        )
        .unwrap();
    drop(connection);

    match HistoryRepository::open(file.path()) {
        Err(ZanryoError::Storage(message)) => {
            assert_eq!(
                message,
                "history schema version 3 is newer than supported version 2"
            );
        }
        Err(error) => panic!("expected future schema to be rejected, got {error}"),
        Ok(_) => panic!("expected future schema to be rejected"),
    }

    let connection = Connection::open(file.path()).unwrap();
    let user_version: i64 = connection
        .query_row("PRAGMA user_version", [], |row| row.get(0))
        .unwrap();
    let sentinel: String = connection
        .query_row("SELECT value FROM future_sentinel", [], |row| row.get(0))
        .unwrap();
    assert_eq!(user_version, 3);
    assert_eq!(sentinel, "preserve me");
}

#[test]
fn providers_can_share_quota_keys_after_reopening_a_migrated_database() {
    let file = NamedTempFile::new().unwrap();
    let connection = Connection::open(file.path()).unwrap();
    connection.execute_batch(LEGACY_SCHEMA).unwrap();
    connection
        .execute(
            "INSERT INTO quota_samples (observed_at, limit_id, kind, remaining_percent, resets_at)
             VALUES (?1, 'codex', 'weekly', 55, ?2)",
            rusqlite::params![at(9, 0), at(17, 0)],
        )
        .unwrap();
    drop(connection);

    let history = HistoryRepository::open(file.path()).unwrap();
    let claude = RateLimit::new(
        ProviderId::Claude,
        LimitKind::Weekly,
        "codex",
        80.0,
        at(17, 0),
        at(9, 0),
    )
    .unwrap();
    history.insert_limits(&[claude]).unwrap();

    assert_eq!(
        history.latest_limits(ProviderId::OpenAi).unwrap()[0].remaining_percent,
        55.0
    );
    assert_eq!(
        history.latest_limits(ProviderId::Claude).unwrap()[0].remaining_percent,
        80.0
    );
    drop(history);

    let reopened = HistoryRepository::open(file.path()).unwrap();
    assert_eq!(reopened.latest_limits(ProviderId::OpenAi).unwrap().len(), 1);
    assert_eq!(reopened.latest_limits(ProviderId::Claude).unwrap().len(), 1);
}

#[test]
fn reopening_rejects_unknown_stored_provider_as_corruption() {
    let file = NamedTempFile::new().unwrap();
    let history = HistoryRepository::open(file.path()).unwrap();
    history.insert_limits(&[weekly_at(1, 55.0)]).unwrap();
    drop(history);

    Connection::open(file.path())
        .unwrap()
        .execute("UPDATE quota_samples SET provider = 'unknown'", [])
        .unwrap();

    match HistoryRepository::open(file.path()) {
        Err(ZanryoError::Storage(message)) => {
            assert!(message.contains("stored provider is invalid"));
        }
        Err(error) => panic!("expected storage corruption error, got {error}"),
        Ok(_) => panic!("expected unknown stored provider to be rejected"),
    }
}
