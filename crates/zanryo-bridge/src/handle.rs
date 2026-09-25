use std::path::Path;
use std::sync::{Arc, Mutex};

use tokio::runtime::{Builder, Runtime};
use zanryo_core::{
    CodexAppServer, DashboardSnapshot, HistoryRepository, ProviderId, QuotaService, ZanryoError,
    cached_dashboard, resolve_codex_path,
};

use crate::envelope::BridgeError;
use zanryo_core::claude::{ClaudeUsageProbe, ClaudeUsageSnapshot, ProbeConfig};

pub struct BridgeHandle {
    runtime: Option<Runtime>,
    history: Option<HistoryRepository>,
    service: Mutex<Option<Arc<QuotaService<CodexAppServer>>>>,
    initialization_error: Option<BridgeError>,
    claude_lock: Mutex<()>,
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
            claude_lock: Mutex::new(()),
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
        cached_dashboard(history, ProviderId::OpenAi, chrono::Utc::now()).map_err(BridgeError::from)
    }

    pub fn claude_cached(&self) -> Result<Option<ClaudeUsageSnapshot>, BridgeError> {
        let history = self
            .history
            .as_ref()
            .ok_or_else(|| BridgeError::internal("history is unavailable"))?;
        ClaudeUsageSnapshot::cached(history).map_err(BridgeError::from)
    }

    pub fn claude_refresh(
        &self,
        working_directory: &Path,
    ) -> Result<ClaudeUsageSnapshot, BridgeError> {
        let _guard = self
            .claude_lock
            .try_lock()
            .map_err(|_| BridgeError::internal("Claude refresh already running"))?;
        let history = self
            .history
            .as_ref()
            .ok_or_else(|| BridgeError::internal("history is unavailable"))?;
        let result = (|| {
            let executable = zanryo_core::discover_installed_providers()
                .into_iter()
                .find(|item| item.provider == ProviderId::Claude)
                .ok_or_else(|| BridgeError {
                    code: "claude_unavailable",
                    message: "Claude CLI was not found".into(),
                })?
                .executable_path;
            let limits =
                ClaudeUsageProbe::new(ProbeConfig::new(executable, working_directory.to_owned()))
                    .read()
                    .map_err(|error| BridgeError {
                        code: "claude_unavailable",
                        message: error.to_string(),
                    })?;
            ClaudeUsageSnapshot::record(history, limits).map_err(BridgeError::from)
        })();
        match result {
            Ok(snapshot) => Ok(snapshot),
            Err(error) => self.claude_cached()?.ok_or(error),
        }
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
        let service = Arc::new(QuotaService::new(ProviderId::OpenAi, source, history));
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
