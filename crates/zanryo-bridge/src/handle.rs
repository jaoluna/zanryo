use std::path::Path;
use std::sync::{Arc, Mutex};

use tokio::runtime::{Builder, Runtime};
use zanryo_core::{
    CodexAppServer, DashboardSnapshot, HistoryRepository, QuotaService, ZanryoError,
    cached_dashboard, resolve_codex_path,
};

use crate::envelope::BridgeError;

pub struct BridgeHandle {
    runtime: Option<Runtime>,
    history: Option<HistoryRepository>,
    service: Mutex<Option<Arc<QuotaService<CodexAppServer>>>>,
    initialization_error: Option<BridgeError>,
}

impl Default for BridgeHandle {
    fn default() -> Self {
        Self::new()
    }
}

impl BridgeHandle {
    pub fn new() -> Self {
        Self::from_history_result(HistoryRepository::open_default())
    }

    pub fn open(path: impl AsRef<Path>) -> Self {
        Self::from_history_result(HistoryRepository::open(path))
    }

    fn from_history_result(history: zanryo_core::Result<HistoryRepository>) -> Self {
        let runtime = Builder::new_multi_thread()
            .worker_threads(1)
            .thread_name("zanryo-rust")
            .enable_all()
            .build()
            .map_err(|error| {
                BridgeError::internal(format!("runtime initialization failed: {error}"))
            });
        let history = history.map_err(BridgeError::from);
        let initialization_error = runtime
            .as_ref()
            .err()
            .cloned()
            .or_else(|| history.as_ref().err().cloned());

        Self {
            runtime: runtime.ok(),
            history: history.ok(),
            service: Mutex::new(None),
            initialization_error,
        }
    }

    pub fn cached(&self) -> Result<Option<DashboardSnapshot>, BridgeError> {
        if let Some(error) = &self.initialization_error {
            return Err(error.clone());
        }

        let history = self
            .history
            .as_ref()
            .ok_or_else(|| BridgeError::internal("history is unavailable"))?;
        cached_dashboard(history, chrono::Utc::now()).map_err(BridgeError::from)
    }

    pub fn refresh(&self) -> Result<DashboardSnapshot, BridgeError> {
        if let Some(error) = &self.initialization_error {
            return Err(error.clone());
        }

        let runtime = self
            .runtime
            .as_ref()
            .ok_or_else(|| BridgeError::internal("runtime is unavailable"))?;
        runtime.block_on(async {
            let service = self.service().await?;
            service
                .refresh_dashboard(chrono::Utc::now())
                .await
                .map_err(BridgeError::from)
        })
    }

    async fn service(&self) -> Result<Arc<QuotaService<CodexAppServer>>, BridgeError> {
        if let Some(service) = self
            .service
            .lock()
            .map_err(|_| BridgeError::internal("service lock is poisoned"))?
            .clone()
        {
            return Ok(service);
        }

        let codex_path = resolve_codex_path().ok_or_else(|| {
            BridgeError::from(ZanryoError::Transport(
                "Codex executable was not found".to_owned(),
            ))
        })?;
        let source = CodexAppServer::spawn(codex_path)
            .await
            .map_err(BridgeError::from)?;
        let history = self
            .history
            .as_ref()
            .ok_or_else(|| BridgeError::internal("history is unavailable"))?
            .clone();
        let service = Arc::new(QuotaService::new(source, history));
        *self
            .service
            .lock()
            .map_err(|_| BridgeError::internal("service lock is poisoned"))? =
            Some(Arc::clone(&service));
        Ok(service)
    }
}

impl Drop for BridgeHandle {
    fn drop(&mut self) {
        if let Some(runtime) = self.runtime.take() {
            runtime.shutdown_background();
        }
    }
}
