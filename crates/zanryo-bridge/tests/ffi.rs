use std::ffi::{CStr, c_char};

use chrono::{Duration, TimeZone, Utc};
use tempfile::tempdir;
use zanryo_bridge::{
    BridgeHandle, zanryo_cached_json, zanryo_create, zanryo_destroy, zanryo_refresh_json,
    zanryo_string_free,
};
use zanryo_core::{HistoryRepository, LimitKind, RateLimit};

unsafe fn owned_json(pointer: *mut c_char) -> String {
    assert!(!pointer.is_null());
    let value = unsafe { CStr::from_ptr(pointer) }
        .to_str()
        .unwrap()
        .to_owned();
    unsafe { zanryo_string_free(pointer) };
    value
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
        LimitKind::Weekly,
        "codex",
        76.0,
        now + Duration::days(5),
        now,
    )
    .unwrap();
    history.insert_limits(&[weekly]).unwrap();
    drop(history);
    let handle = Box::into_raw(Box::new(BridgeHandle::open(&path)));

    let json = unsafe { owned_json(zanryo_cached_json(handle)) };
    let value: serde_json::Value = serde_json::from_str(&json).unwrap();

    assert_eq!(value["ok"], true);
    assert_eq!(value["data"]["quota"]["weekly"]["remaining_percent"], 76.0);
    assert_eq!(value["data"]["forecast"]["status"], "collecting_history");
    unsafe { zanryo_destroy(handle) };
}

#[test]
fn null_handle_refresh_returns_versioned_error() {
    let json = unsafe { owned_json(zanryo_refresh_json(std::ptr::null_mut())) };
    let value: serde_json::Value = serde_json::from_str(&json).unwrap();

    assert_eq!(value["schema_version"], 1);
    assert_eq!(value["error"]["code"], "invalid_handle");
}
