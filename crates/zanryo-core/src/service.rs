use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};

use chrono::{DateTime, Duration, Utc};
use tokio::sync::{Mutex, RwLock};

use crate::{
    ForecastEngine, ForecastReport, Freshness, HistoryRepository, QuotaSnapshot, RateLimitSource,
    Result, ZanryoError,
};

const HISTORY_RETENTION_DAYS: i64 = 90;

pub struct QuotaService<S> {
    source: Arc<S>,
    history: HistoryRepository,
    refresh_lock: Mutex<()>,
    generation: AtomicU64,
    last_success: RwLock<Option<QuotaSnapshot>>,
}

impl<S> QuotaService<S>
where
    S: RateLimitSource + 'static,
{
    pub fn new(source: S, history: HistoryRepository) -> Self {
        Self {
            source: Arc::new(source),
            history,
            refresh_lock: Mutex::new(()),
            generation: AtomicU64::new(0),
            last_success: RwLock::new(None),
        }
    }

    pub async fn refresh(&self) -> Result<QuotaSnapshot> {
        let observed_generation = self.generation.load(Ordering::Acquire);
        let _guard = self.refresh_lock.lock().await;

        if self.generation.load(Ordering::Acquire) != observed_generation {
            if let Some(snapshot) = self.last_success.read().await.clone() {
                return Ok(snapshot);
            }
        }

        match self.source.read_rate_limits().await {
            Ok(limits) => {
                let snapshot = QuotaSnapshot::from_limits(limits.clone(), Freshness::Fresh)?;
                let history = self.history.clone();
                run_history_task(move || {
                    history.insert_limits(&limits)?;
                    history.prune_before(Utc::now() - Duration::days(HISTORY_RETENTION_DAYS))?;
                    Ok(())
                })
                .await?;

                *self.last_success.write().await = Some(snapshot.clone());
                self.generation.fetch_add(1, Ordering::Release);
                Ok(snapshot)
            }
            Err(source_error) => match self.cached().await? {
                Some(snapshot) => Ok(snapshot),
                None => Err(source_error),
            },
        }
    }

    pub async fn cached(&self) -> Result<Option<QuotaSnapshot>> {
        let history = self.history.clone();
        let limits = run_history_task(move || history.latest_limits()).await?;

        if limits.is_empty() {
            Ok(None)
        } else {
            QuotaSnapshot::from_limits(limits, Freshness::Stale).map(Some)
        }
    }

    pub async fn forecast(&self, now: DateTime<Utc>) -> Result<ForecastReport> {
        let history = self.history.clone();
        let since = now - Duration::days(8);
        let samples = run_history_task(move || history.limits_since(since)).await?;
        Ok(ForecastEngine::calculate(&samples, now))
    }
}

async fn run_history_task<T, F>(operation: F) -> Result<T>
where
    T: Send + 'static,
    F: FnOnce() -> Result<T> + Send + 'static,
{
    tokio::task::spawn_blocking(operation)
        .await
        .map_err(|_| ZanryoError::Storage("history task failed".to_owned()))?
}
