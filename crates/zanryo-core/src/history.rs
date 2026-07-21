use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard};

use chrono::{DateTime, Utc};
use directories::ProjectDirs;
use rusqlite::{Connection, OptionalExtension, params};

use crate::{AccountContext, LimitKind, PlanType, RateLimit, Result, ZanryoError};

const SCHEMA: &str = "
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS quota_samples (
    id INTEGER PRIMARY KEY,
    observed_at TEXT NOT NULL,
    limit_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    remaining_percent REAL NOT NULL CHECK (remaining_percent BETWEEN 0 AND 100),
    resets_at TEXT NOT NULL,
    UNIQUE(observed_at, limit_id)
);

CREATE INDEX IF NOT EXISTS idx_quota_samples_observed
ON quota_samples(observed_at);

CREATE TABLE IF NOT EXISTS account_context (
    singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
    plan_type TEXT NOT NULL,
    observed_at TEXT NOT NULL
);
";

#[derive(Clone)]
pub struct HistoryRepository {
    connection: Arc<Mutex<Connection>>,
}

impl HistoryRepository {
    pub fn open(path: impl AsRef<Path>) -> Result<Self> {
        let connection = Connection::open(path).map_err(storage_error)?;
        connection.execute_batch(SCHEMA).map_err(storage_error)?;

        Ok(Self {
            connection: Arc::new(Mutex::new(connection)),
        })
    }

    pub fn open_default() -> Result<Self> {
        Self::open(Self::default_path()?)
    }

    pub fn default_path() -> Result<PathBuf> {
        let project = ProjectDirs::from("io", "joaoluna", "Zanryo").ok_or_else(|| {
            ZanryoError::Storage("application data path is unavailable".to_owned())
        })?;
        let directory = project.data_dir();
        std::fs::create_dir_all(directory).map_err(|_| {
            ZanryoError::Storage("failed to create application data path".to_owned())
        })?;
        set_private_directory_permissions(directory)?;
        Ok(directory.join("history.sqlite3"))
    }

    pub fn insert_limits(&self, limits: &[RateLimit]) -> Result<()> {
        let mut connection = self.lock()?;
        let transaction = connection.transaction().map_err(storage_error)?;

        for limit in limits {
            transaction
                .execute(
                    "
                    INSERT INTO quota_samples (
                        observed_at,
                        limit_id,
                        kind,
                        remaining_percent,
                        resets_at
                    )
                    VALUES (?1, ?2, ?3, ?4, ?5)
                    ON CONFLICT(observed_at, limit_id) DO UPDATE SET
                        kind = excluded.kind,
                        remaining_percent = excluded.remaining_percent,
                        resets_at = excluded.resets_at
                    ",
                    params![
                        limit.observed_at,
                        limit.limit_id,
                        kind_name(&limit.kind),
                        limit.remaining_percent,
                        limit.resets_at,
                    ],
                )
                .map_err(storage_error)?;
        }

        transaction.commit().map_err(storage_error)
    }

    pub fn latest_limits(&self) -> Result<Vec<RateLimit>> {
        let connection = self.lock()?;
        let latest: Option<DateTime<Utc>> = connection
            .query_row("SELECT MAX(observed_at) FROM quota_samples", [], |row| {
                row.get(0)
            })
            .optional()
            .map_err(storage_error)?
            .flatten();

        match latest {
            Some(observed_at) => query_limits(&connection, "WHERE observed_at = ?1", observed_at),
            None => Ok(Vec::new()),
        }
    }

    pub fn limits_since(&self, since: DateTime<Utc>) -> Result<Vec<RateLimit>> {
        let connection = self.lock()?;
        query_limits(&connection, "WHERE observed_at >= ?1", since)
    }

    pub fn prune_before(&self, cutoff: DateTime<Utc>) -> Result<usize> {
        self.lock()?
            .execute("DELETE FROM quota_samples WHERE observed_at < ?1", [cutoff])
            .map_err(storage_error)
    }

    pub fn upsert_account_context(&self, context: &AccountContext) -> Result<()> {
        if context.plan_type == PlanType::Unknown || context.observed_at.is_none() {
            self.lock()?
                .execute("DELETE FROM account_context WHERE singleton = 1", [])
                .map_err(storage_error)?;
            return Ok(());
        }

        let observed_at = context.observed_at.as_ref().expect("checked above");
        self.lock()?
            .execute(
                "
                INSERT INTO account_context (singleton, plan_type, observed_at)
                VALUES (1, ?1, ?2)
                ON CONFLICT(singleton) DO UPDATE SET
                    plan_type = excluded.plan_type,
                    observed_at = excluded.observed_at
                ",
                params![plan_type_name(context.plan_type), observed_at],
            )
            .map_err(storage_error)?;
        Ok(())
    }

    pub fn latest_account_context(&self) -> Result<Option<AccountContext>> {
        let connection = self.lock()?;
        let stored: Option<(String, DateTime<Utc>)> = connection
            .query_row(
                "SELECT plan_type, observed_at FROM account_context WHERE singleton = 1",
                [],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .optional()
            .map_err(storage_error)?;

        let Some((plan_type, observed_at)) = stored else {
            return Ok(None);
        };
        let plan_type = PlanType::from_app_server(&plan_type);
        if plan_type == PlanType::Unknown {
            connection
                .execute("DELETE FROM account_context WHERE singleton = 1", [])
                .map_err(storage_error)?;
            return Ok(None);
        }

        Ok(Some(AccountContext::new(plan_type, observed_at)))
    }

    fn lock(&self) -> Result<MutexGuard<'_, Connection>> {
        self.connection
            .lock()
            .map_err(|_| ZanryoError::Storage("history lock poisoned".to_owned()))
    }
}

fn query_limits(
    connection: &Connection,
    filter: &str,
    timestamp: DateTime<Utc>,
) -> Result<Vec<RateLimit>> {
    let sql = format!(
        "
        SELECT kind, limit_id, remaining_percent, resets_at, observed_at
        FROM quota_samples
        {filter}
        ORDER BY observed_at ASC, limit_id ASC
        "
    );
    let mut statement = connection.prepare(&sql).map_err(storage_error)?;
    let rows = statement
        .query_map([timestamp], |row| {
            let kind: String = row.get(0)?;
            Ok((
                kind,
                row.get::<_, String>(1)?,
                row.get::<_, f64>(2)?,
                row.get::<_, DateTime<Utc>>(3)?,
                row.get::<_, DateTime<Utc>>(4)?,
            ))
        })
        .map_err(storage_error)?;

    rows.map(|row| {
        let (kind, limit_id, remaining_percent, resets_at, observed_at) =
            row.map_err(storage_error)?;
        RateLimit::new(
            parse_kind(&kind)?,
            limit_id,
            remaining_percent,
            resets_at,
            observed_at,
        )
    })
    .collect()
}

fn kind_name(kind: &LimitKind) -> &'static str {
    match kind {
        LimitKind::Weekly => "weekly",
        LimitKind::Spark => "spark",
        LimitKind::Other => "other",
    }
}

fn plan_type_name(plan_type: PlanType) -> &'static str {
    match plan_type {
        PlanType::Free => "free",
        PlanType::Go => "go",
        PlanType::Plus => "plus",
        PlanType::Pro => "pro",
        PlanType::ProLite => "pro_lite",
        PlanType::Team => "team",
        PlanType::Business => "business",
        PlanType::Enterprise => "enterprise",
        PlanType::Edu => "edu",
        PlanType::Unknown => "unknown",
    }
}

fn parse_kind(value: &str) -> Result<LimitKind> {
    match value {
        "weekly" => Ok(LimitKind::Weekly),
        "spark" => Ok(LimitKind::Spark),
        "other" => Ok(LimitKind::Other),
        _ => Err(ZanryoError::Storage(
            "stored limit kind is invalid".to_owned(),
        )),
    }
}

fn storage_error(error: rusqlite::Error) -> ZanryoError {
    ZanryoError::Storage(format!("SQLite operation failed: {error}"))
}

#[cfg(unix)]
fn set_private_directory_permissions(path: &Path) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;

    std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700))
        .map_err(|_| ZanryoError::Storage("failed to secure application data path".to_owned()))
}

#[cfg(not(unix))]
fn set_private_directory_permissions(_path: &Path) -> Result<()> {
    Ok(())
}
