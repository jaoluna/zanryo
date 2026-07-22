use std::collections::HashMap;
use std::env;
use std::path::PathBuf;
use std::process::Stdio;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use chrono::Utc;
use serde_json::{Value, json};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{ChildStdin, Command};
use tokio::sync::{Mutex, oneshot, watch};
use tokio::time::timeout;

use crate::provider::resolve_executable;
use crate::{
    PlanType, RateLimit, Result, ZanryoError, decode_account_plan, decode_rate_limits,
    is_rate_limits_update,
};

const RPC_TIMEOUT: Duration = Duration::from_secs(5);

type RpcResponse = std::result::Result<Value, String>;
type PendingResponses = HashMap<u64, oneshot::Sender<RpcResponse>>;

#[async_trait::async_trait]
pub trait RateLimitSource: Send + Sync {
    async fn read_rate_limits(&self) -> Result<Vec<RateLimit>>;
    async fn read_account_plan(&self) -> Result<PlanType>;
}

pub struct CodexAppServer {
    stdin: Mutex<ChildStdin>,
    pending: Arc<Mutex<PendingResponses>>,
    state: RpcState,
    updates: watch::Sender<Option<Value>>,
}

impl CodexAppServer {
    pub async fn spawn(codex_path: PathBuf) -> Result<Self> {
        let mut child = Command::new(codex_path)
            .arg("app-server")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn()
            .map_err(|error| ZanryoError::Transport(format!("failed to start Codex: {error}")))?;

        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| ZanryoError::Transport("Codex stdin is unavailable".to_owned()))?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| ZanryoError::Transport("Codex stdout is unavailable".to_owned()))?;
        let stderr = child
            .stderr
            .take()
            .ok_or_else(|| ZanryoError::Transport("Codex stderr is unavailable".to_owned()))?;

        let pending = Arc::new(Mutex::new(PendingResponses::new()));
        let (updates, _) = watch::channel(None);

        spawn_stdout_reader(stdout, Arc::clone(&pending), updates.clone());
        spawn_stderr_drain(stderr);
        tokio::spawn(async move {
            let _ = child.wait().await;
        });

        let server = Self {
            stdin: Mutex::new(stdin),
            pending,
            state: RpcState::default(),
            updates,
        };

        let initialize_id = server.state.next_id();
        server
            .request(build_initialize_request(initialize_id))
            .await?;
        server
            .send_notification(json!({"method": "initialized"}))
            .await?;

        Ok(server)
    }

    pub fn subscribe_updates(&self) -> watch::Receiver<Option<Value>> {
        self.updates.subscribe()
    }

    async fn request(&self, request: Value) -> Result<Value> {
        let id = request
            .get("id")
            .and_then(Value::as_u64)
            .ok_or_else(|| ZanryoError::Transport("request id is missing".to_owned()))?;
        let (sender, receiver) = oneshot::channel();
        self.pending.lock().await.insert(id, sender);

        if let Err(error) = self.write_json(&request).await {
            self.pending.lock().await.remove(&id);
            return Err(error);
        }

        let response = match timeout(RPC_TIMEOUT, receiver).await {
            Err(_) => {
                self.pending.lock().await.remove(&id);
                return Err(ZanryoError::Transport("Codex request timed out".to_owned()));
            }
            Ok(Err(_)) => {
                return Err(ZanryoError::Transport(
                    "Codex response channel closed".to_owned(),
                ));
            }
            Ok(Ok(Err(message))) => return Err(ZanryoError::Transport(message)),
            Ok(Ok(Ok(response))) => response,
        };

        if let Some(error) = response.get("error") {
            return Err(ZanryoError::Transport(format!(
                "Codex returned an RPC error: {}",
                summarize_rpc_error(error)
            )));
        }

        Ok(response)
    }

    async fn send_notification(&self, notification: Value) -> Result<()> {
        self.write_json(&notification).await
    }

    async fn write_json(&self, value: &Value) -> Result<()> {
        let mut payload = serde_json::to_vec(value)
            .map_err(|error| ZanryoError::Transport(format!("JSON encoding failed: {error}")))?;
        payload.push(b'\n');

        let mut stdin = self.stdin.lock().await;
        stdin
            .write_all(&payload)
            .await
            .map_err(|error| ZanryoError::Transport(format!("Codex write failed: {error}")))?;
        stdin
            .flush()
            .await
            .map_err(|error| ZanryoError::Transport(format!("Codex flush failed: {error}")))
    }
}

pub fn resolve_codex_path() -> Option<PathBuf> {
    let mut candidates = Vec::new();

    if let Some(explicit) = env::var_os("CODEX_PATH") {
        candidates.push(PathBuf::from(explicit));
    }
    if let Some(path) = env::var_os("PATH") {
        candidates.extend(env::split_paths(&path).map(|directory| directory.join("codex")));
    }
    if let Some(bundled) = env::current_exe()
        .ok()
        .and_then(|executable| executable.parent().map(|directory| directory.join("codex")))
    {
        candidates.push(bundled);
    }
    candidates.push(PathBuf::from(
        "/Applications/ChatGPT.app/Contents/Resources/codex",
    ));

    resolve_executable(candidates)
}

#[async_trait::async_trait]
impl RateLimitSource for CodexAppServer {
    async fn read_rate_limits(&self) -> Result<Vec<RateLimit>> {
        let id = self.state.next_id();
        let response = self.request(build_rate_limits_request(id)).await?;
        decode_rate_limits(response, Utc::now())
    }

    async fn read_account_plan(&self) -> Result<PlanType> {
        let id = self.state.next_id();
        let response = self.request(build_account_request(id)).await?;
        decode_account_plan(response)
    }
}

struct RpcState {
    next_id: AtomicU64,
}

impl Default for RpcState {
    fn default() -> Self {
        Self {
            next_id: AtomicU64::new(1),
        }
    }
}

impl RpcState {
    fn next_id(&self) -> u64 {
        self.next_id.fetch_add(1, Ordering::Relaxed)
    }
}

fn build_initialize_request(id: u64) -> Value {
    json!({
        "id": id,
        "method": "initialize",
        "params": {
            "clientInfo": {
                "name": "zanryo",
                "title": "Zanryo",
                "version": env!("CARGO_PKG_VERSION")
            },
            "capabilities": {
                "experimentalApi": true
            }
        }
    })
}

fn build_rate_limits_request(id: u64) -> Value {
    json!({
        "id": id,
        "method": "account/rateLimits/read"
    })
}

fn build_account_request(id: u64) -> Value {
    json!({
        "id": id,
        "method": "account/read",
        "params": {}
    })
}

fn spawn_stdout_reader(
    stdout: tokio::process::ChildStdout,
    pending: Arc<Mutex<PendingResponses>>,
    updates: watch::Sender<Option<Value>>,
) {
    tokio::spawn(async move {
        let mut lines = BufReader::new(stdout).lines();

        loop {
            match lines.next_line().await {
                Ok(Some(line)) => match serde_json::from_str::<Value>(&line) {
                    Ok(value) => route_message(value, &pending, &updates).await,
                    Err(_) => {
                        fail_pending(&pending, "Codex emitted invalid JSON").await;
                        break;
                    }
                },
                Ok(None) => {
                    fail_pending(&pending, "Codex app-server closed").await;
                    break;
                }
                Err(_) => {
                    fail_pending(&pending, "Codex output read failed").await;
                    break;
                }
            }
        }
    });
}

fn spawn_stderr_drain(stderr: tokio::process::ChildStderr) {
    tokio::spawn(async move {
        let mut lines = BufReader::new(stderr).lines();
        while matches!(lines.next_line().await, Ok(Some(_))) {}
    });
}

async fn route_message(
    value: Value,
    pending: &Mutex<PendingResponses>,
    updates: &watch::Sender<Option<Value>>,
) {
    if let Some(id) = value.get("id").and_then(Value::as_u64) {
        if let Some(sender) = pending.lock().await.remove(&id) {
            let _ = sender.send(Ok(value));
        }
    } else if is_rate_limits_update(&value) {
        updates.send_replace(Some(value));
    }
}

async fn fail_pending(pending: &Mutex<PendingResponses>, message: &str) {
    for (_, sender) in pending.lock().await.drain() {
        let _ = sender.send(Err(message.to_owned()));
    }
}

fn summarize_rpc_error(error: &Value) -> String {
    error
        .get("message")
        .and_then(Value::as_str)
        .unwrap_or("unknown error")
        .to_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn request_ids_are_monotonic() {
        let state = RpcState::default();
        assert_eq!(state.next_id(), 1);
        assert_eq!(state.next_id(), 2);
    }

    #[test]
    fn read_request_uses_official_method() {
        let request = build_rate_limits_request(7);
        assert_eq!(request["id"], 7);
        assert_eq!(request["method"], "account/rateLimits/read");
        assert!(request.get("params").is_none());
    }

    #[test]
    fn account_request_uses_required_empty_params_object() {
        let request = build_account_request(3);

        assert_eq!(request["id"], 3);
        assert_eq!(request["method"], "account/read");
        assert_eq!(request["params"], json!({}));
    }

    #[test]
    fn initialize_request_identifies_zanryo() {
        let request = build_initialize_request(1);
        assert_eq!(request["method"], "initialize");
        assert_eq!(request["params"]["clientInfo"]["name"], "zanryo");
        assert_eq!(request["params"]["capabilities"]["experimentalApi"], true);
    }
}
