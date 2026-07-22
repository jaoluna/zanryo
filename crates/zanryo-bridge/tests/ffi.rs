use std::env;
use std::ffi::{CStr, OsString, c_char};
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock};

use chrono::{Duration, TimeZone, Utc};
use tempfile::tempdir;
use zanryo_bridge::{
    BridgeHandle, zanryo_cached_json, zanryo_create, zanryo_destroy,
    zanryo_provider_discovery_json, zanryo_refresh_json, zanryo_string_free,
};
use zanryo_core::{AccountContext, HistoryRepository, LimitKind, PlanType, ProviderId, RateLimit};

unsafe fn owned_json(pointer: *mut c_char) -> String {
    assert!(!pointer.is_null());
    let value = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .unwrap()
        .to_owned();
    unsafe { zanryo_string_free(pointer) };
    value
}

fn executable(path: PathBuf) -> PathBuf {
    fs::write(&path, "").unwrap();
    let mut permissions = fs::metadata(&path).unwrap().permissions();
    permissions.set_mode(0o755);
    fs::set_permissions(&path, permissions).unwrap();
    path
}

fn environment_lock() -> &'static Mutex<()> {
    static LOCK: OnceLock<Mutex<()>> = OnceLock::new();
    LOCK.get_or_init(|| Mutex::new(()))
}

struct ScopedEnvironmentVariable {
    key: &'static str,
    previous: Option<OsString>,
}

impl ScopedEnvironmentVariable {
    fn set(key: &'static str, value: &std::path::Path) -> Self {
        let previous = env::var_os(key);
        unsafe { env::set_var(key, value) };
        Self { key, previous }
    }
}

impl Drop for ScopedEnvironmentVariable {
    fn drop(&mut self) {
        if let Some(previous) = &self.previous {
            unsafe { env::set_var(self.key, previous) };
        } else {
            unsafe { env::remove_var(self.key) };
        }
    }
}

#[test]
fn null_handle_returns_versioned_error_envelope() {
    let json = unsafe { owned_json(zanryo_cached_json(std::ptr::null_mut())) };
    let value: serde_json::Value = serde_json::from_str(&json).unwrap();

    assert_eq!(value["schema_version"], 1);
    assert_eq!(value["ok"], false);
    assert_eq!(value["error"]["code"], "invalid_handle");
}

#[test]
fn provider_discovery_json_uses_the_versioned_envelope_and_openai_wire_id() {
    let _environment = environment_lock().lock().unwrap();
    let directory = tempdir().unwrap();
    let codex = executable(directory.path().join("codex"));
    let _codex_path = ScopedEnvironmentVariable::set("CODEX_PATH", &codex);

    let json = unsafe { owned_json(zanryo_provider_discovery_json()) };
    let value: serde_json::Value = serde_json::from_str(&json).unwrap();

    assert_eq!(value["schema_version"], 1);
    assert_eq!(value["ok"], true);
    assert!(json.contains(r#""provider":"openai""#));
    assert_eq!(value["data"][0]["provider"], "openai");
    assert_eq!(
        value["data"][0]["executable_path"],
        codex.canonicalize().unwrap().to_string_lossy().as_ref()
    );
}

#[test]
fn create_and_destroy_handle_are_safe() {
    let handle = zanryo_create();

    assert!(!handle.is_null());

    unsafe {
        zanryo_destroy(handle);
        zanryo_destroy(std::ptr::null_mut());
    }
}

#[test]
fn cached_json_serializes_persisted_dashboard() {
    let directory = tempdir().unwrap();
    let path = directory.path().join("history.sqlite3");
    let history = HistoryRepository::open(&path).unwrap();
    let now = Utc.with_ymd_and_hms(2026, 7, 20, 9, 0, 0).unwrap();
    let weekly = RateLimit::new(
        ProviderId::OpenAi,
        LimitKind::Weekly,
        "codex",
        76.0,
        now + Duration::days(5),
        now,
    )
    .unwrap();
    history.insert_limits(&[weekly]).unwrap();
    history
        .upsert_account_context(&AccountContext::new(
            ProviderId::OpenAi,
            PlanType::Plus,
            now,
        ))
        .unwrap();
    drop(history);
    let handle = Box::into_raw(Box::new(BridgeHandle::open(&path)));

    let json = unsafe { owned_json(zanryo_cached_json(handle)) };
    let value: serde_json::Value = serde_json::from_str(&json).unwrap();

    assert_eq!(value["ok"], true);
    assert_eq!(value["data"]["quota"]["weekly"]["remaining_percent"], 76.0);
    assert_eq!(value["data"]["forecast"]["status"], "collecting_history");
    assert_eq!(value["data"]["account"]["plan_type"], "plus");
    assert!(value["data"]["account"].get("email").is_none());
    unsafe { zanryo_destroy(handle) };
}

#[test]
fn null_handle_refresh_returns_versioned_error() {
    let json = unsafe { owned_json(zanryo_refresh_json(std::ptr::null_mut())) };
    let value: serde_json::Value = serde_json::from_str(&json).unwrap();

    assert_eq!(value["schema_version"], 1);
    assert_eq!(value["error"]["code"], "invalid_handle");
}
