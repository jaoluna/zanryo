use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard};

use chrono::{DateTime, Utc};
use directories::ProjectDirs;
use rusqlite::{Connection, OptionalExtension, Transaction, TransactionBehavior, params};

use crate::{AccountContext, LimitKind, PlanType, ProviderId, RateLimit, Result, ZanryoError};

const CONNECTION_SETTINGS: &str = "
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
";

const CURRENT_SCHEMA_VERSION: i64 = 2;

const V2_SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS quota_samples (
    id INTEGER PRIMARY KEY,
    provider TEXT NOT NULL,
    observed_at TEXT NOT NULL,
    limit_id TEXT NOT NULL,
    kind TEXT NOT NULL,
    remaining_percent REAL NOT NULL CHECK (remaining_percent BETWEEN 0 AND 100),
    resets_at TEXT NOT NULL,
    UNIQUE(provider, observed_at, limit_id)
);

CREATE INDEX IF NOT EXISTS idx_quota_samples_provider_observed
ON quota_samples(provider, observed_at);

CREATE TABLE IF NOT EXISTS account_context (
    provider TEXT PRIMARY KEY,
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
        let mut connection = Connection::open(path).map_err(storage_error)?;
        initialize_schema(&mut connection)?;

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
                        provider,
                        observed_at,
                        limit_id,
                        kind,
                        remaining_percent,
                        resets_at
                    )
                    VALUES (?1, ?2, ?3, ?4, ?5, ?6)
                    ON CONFLICT(provider, observed_at, limit_id) DO UPDATE SET
                        kind = excluded.kind,
                        remaining_percent = excluded.remaining_percent,
                        resets_at = excluded.resets_at
                    ",
                    params![
                        limit.provider.as_str(),
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

    pub fn latest_limits(&self, provider: ProviderId) -> Result<Vec<RateLimit>> {
        let connection = self.lock()?;
        let latest: Option<DateTime<Utc>> = connection
            .query_row(
                "SELECT MAX(observed_at) FROM quota_samples WHERE provider = ?1",
                [provider.as_str()],
                |row| row.get(0),
            )
            .map_err(storage_error)?;

        match latest {
            Some(observed_at) => {
                query_limits(&connection, provider, "AND observed_at = ?2", observed_at)
            }
            None => Ok(Vec::new()),
        }
    }

    pub fn limits_since(
        &self,
        provider: ProviderId,
        since: DateTime<Utc>,
    ) -> Result<Vec<RateLimit>> {
        let connection = self.lock()?;
        query_limits(&connection, provider, "AND observed_at >= ?2", since)
    }

    pub fn prune_before(&self, provider: ProviderId, cutoff: DateTime<Utc>) -> Result<usize> {
        self.lock()?
            .execute(
                "DELETE FROM quota_samples WHERE provider = ?1 AND observed_at < ?2",
                params![provider.as_str(), cutoff],
            )
            .map_err(storage_error)
    }

    pub fn upsert_account_context(&self, context: &AccountContext) -> Result<()> {
        if context.plan_type == PlanType::Unknown || context.observed_at.is_none() {
            self.lock()?
                .execute(
                    "DELETE FROM account_context WHERE provider = ?1",
                    [context.provider.as_str()],
                )
                .map_err(storage_error)?;
            return Ok(());
        }

        let observed_at = context.observed_at.as_ref().expect("checked above");
        self.lock()?
            .execute(
                "
                INSERT INTO account_context (provider, plan_type, observed_at)
                VALUES (?1, ?2, ?3)
                ON CONFLICT(provider) DO UPDATE SET
                    plan_type = excluded.plan_type,
                    observed_at = excluded.observed_at
                ",
                params![
                    context.provider.as_str(),
                    plan_type_name(context.plan_type),
                    observed_at,
                ],
            )
            .map_err(storage_error)?;
        Ok(())
    }

    pub fn latest_account_context(&self, provider: ProviderId) -> Result<Option<AccountContext>> {
        let connection = self.lock()?;
        let stored: Option<(String, String, DateTime<Utc>)> = connection
            .query_row(
                "SELECT provider, plan_type, observed_at FROM account_context WHERE provider = ?1",
                [provider.as_str()],
                |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)),
            )
            .optional()
            .map_err(storage_error)?;

        let Some((stored_provider, plan_type, observed_at)) = stored else {
            return Ok(None);
        };
        let stored_provider = parse_provider(&stored_provider)?;
        let plan_type = PlanType::from_app_server(&plan_type);
        if plan_type == PlanType::Unknown {
            connection
                .execute(
                    "DELETE FROM account_context WHERE provider = ?1",
                    [provider.as_str()],
                )
                .map_err(storage_error)?;
            return Ok(None);
        }

        Ok(Some(AccountContext::new(
            stored_provider,
            plan_type,
            observed_at,
        )))
    }

    fn lock(&self) -> Result<MutexGuard<'_, Connection>> {
        self.connection
            .lock()
            .map_err(|_| ZanryoError::Storage("history lock poisoned".to_owned()))
    }
}

fn query_limits(
    connection: &Connection,
    provider: ProviderId,
    filter: &str,
    timestamp: DateTime<Utc>,
) -> Result<Vec<RateLimit>> {
    let sql = format!(
        "
        SELECT provider, kind, limit_id, remaining_percent, resets_at, observed_at
        FROM quota_samples
        WHERE provider = ?1 {filter}
        ORDER BY observed_at ASC, limit_id ASC
        "
    );
    let mut statement = connection.prepare(&sql).map_err(storage_error)?;
    let rows = statement
        .query_map(params![provider.as_str(), timestamp], |row| {
            let stored_provider: String = row.get(0)?;
            Ok((
                stored_provider,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, f64>(3)?,
                row.get::<_, DateTime<Utc>>(4)?,
                row.get::<_, DateTime<Utc>>(5)?,
            ))
        })
        .map_err(storage_error)?;

    rows.map(|row| {
        let (stored_provider, kind, limit_id, remaining_percent, resets_at, observed_at) =
            row.map_err(storage_error)?;
        RateLimit::new(
            parse_provider(&stored_provider)?,
            parse_kind(&kind)?,
            limit_id,
            remaining_percent,
            resets_at,
            observed_at,
        )
    })
    .collect()
}

fn initialize_schema(connection: &mut Connection) -> Result<()> {
    connection
        .execute_batch(CONNECTION_SETTINGS)
        .map_err(storage_error)?;
    let stored_schema_version: i64 = connection
        .pragma_query_value(None, "user_version", |row| row.get(0))
        .map_err(storage_error)?;
    if stored_schema_version > CURRENT_SCHEMA_VERSION {
        return Err(ZanryoError::Storage(format!(
            "history schema version {stored_schema_version} is newer than supported version {CURRENT_SCHEMA_VERSION}"
        )));
    }

    let transaction = connection
        .transaction_with_behavior(TransactionBehavior::Immediate)
        .map_err(storage_error)?;

    if table_exists(&transaction, "quota_samples")? && !quota_samples_has_provider(&transaction)? {
        migrate_legacy_schema(&transaction)?;
    } else {
        transaction
            .execute_batch(V2_SCHEMA)
            .map_err(storage_error)?;
    }

    validate_stored_providers(&transaction)?;

    transaction
        .pragma_update(None, "user_version", CURRENT_SCHEMA_VERSION)
        .map_err(storage_error)?;
    transaction.commit().map_err(storage_error)
}

fn migrate_legacy_schema(transaction: &Transaction<'_>) -> Result<()> {
    transaction
        .execute_batch(
            "
            ALTER TABLE quota_samples RENAME TO quota_samples_legacy;
            DROP INDEX IF EXISTS idx_quota_samples_observed;
            CREATE TABLE quota_samples (
                id INTEGER PRIMARY KEY,
                provider TEXT NOT NULL,
                observed_at TEXT NOT NULL,
                limit_id TEXT NOT NULL,
                kind TEXT NOT NULL,
                remaining_percent REAL NOT NULL CHECK (remaining_percent BETWEEN 0 AND 100),
                resets_at TEXT NOT NULL,
                UNIQUE(provider, observed_at, limit_id)
            );
            INSERT INTO quota_samples (
                id, provider, observed_at, limit_id, kind, remaining_percent, resets_at
            )
            SELECT id, 'openai', observed_at, limit_id, kind, remaining_percent, resets_at
            FROM quota_samples_legacy;
            DROP TABLE quota_samples_legacy;
            CREATE INDEX idx_quota_samples_provider_observed
            ON quota_samples(provider, observed_at);
            ",
        )
        .map_err(storage_error)?;

    if table_exists(transaction, "account_context")? {
        transaction
            .execute_batch(
                "
                ALTER TABLE account_context RENAME TO account_context_legacy;
                CREATE TABLE account_context (
                    provider TEXT PRIMARY KEY,
                    plan_type TEXT NOT NULL,
                    observed_at TEXT NOT NULL
                );
                INSERT INTO account_context (provider, plan_type, observed_at)
                SELECT 'openai', plan_type, observed_at
                FROM account_context_legacy
                WHERE singleton = 1;
                DROP TABLE account_context_legacy;
                ",
            )
            .map_err(storage_error)?;
    } else {
        transaction
            .execute_batch(
                "
                CREATE TABLE account_context (
                    provider TEXT PRIMARY KEY,
                    plan_type TEXT NOT NULL,
                    observed_at TEXT NOT NULL
                );
                ",
            )
            .map_err(storage_error)?;
    }

    Ok(())
}

fn table_exists(connection: &Connection, table_name: &str) -> Result<bool> {
    connection
        .query_row(
            "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?1)",
            [table_name],
            |row| row.get::<_, i64>(0),
        )
        .map(|exists| exists != 0)
        .map_err(storage_error)
}

fn quota_samples_has_provider(connection: &Connection) -> Result<bool> {
    let mut statement = connection
        .prepare("PRAGMA table_info(quota_samples)")
        .map_err(storage_error)?;
    let columns = statement
        .query_map([], |row| row.get::<_, String>(1))
        .map_err(storage_error)?;

    for column in columns {
        if column.map_err(storage_error)? == "provider" {
            return Ok(true);
        }
    }

    Ok(false)
}

fn validate_stored_providers(connection: &Connection) -> Result<()> {
    let mut statement = connection
        .prepare(
            "
            SELECT provider FROM quota_samples
            UNION ALL
            SELECT provider FROM account_context
            ",
        )
        .map_err(storage_error)?;
    let providers = statement
        .query_map([], |row| row.get::<_, String>(0))
        .map_err(storage_error)?;

    for provider in providers {
        parse_provider(&provider.map_err(storage_error)?)?;
    }

    Ok(())
}

fn kind_name(kind: &LimitKind) -> &'static str {
    match kind {
        LimitKind::FiveHour => "five_hour",
        LimitKind::Weekly => "weekly",
        LimitKind::Spark => "spark",
        LimitKind::Fable => "fable",
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
        "five_hour" => Ok(LimitKind::FiveHour),
        "weekly" => Ok(LimitKind::Weekly),
        "spark" => Ok(LimitKind::Spark),
        "fable" => Ok(LimitKind::Fable),
        "other" => Ok(LimitKind::Other),
        _ => Err(ZanryoError::Storage(
            "stored limit kind is invalid".to_owned(),
        )),
    }
}

fn parse_provider(value: &str) -> Result<ProviderId> {
    match value {
        "openai" => Ok(ProviderId::OpenAi),
        "claude" => Ok(ProviderId::Claude),
        _ => Err(ZanryoError::Storage(
            "stored provider is invalid".to_owned(),
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
