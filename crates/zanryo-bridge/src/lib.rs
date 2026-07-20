mod envelope;
mod handle;

use std::ffi::{CString, c_char};
use std::panic::{AssertUnwindSafe, catch_unwind};
use std::ptr;

use envelope::{BridgeError, failure, success};
pub use handle::BridgeHandle;

fn json_pointer(json: String) -> *mut c_char {
    CString::new(json)
        .unwrap_or_else(|_| CString::new(fallback_json()).expect("fallback JSON has no null byte"))
        .into_raw()
}

fn serialize<T: serde::Serialize>(value: &T) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| fallback_json())
}

fn fallback_json() -> String {
    r#"{"schema_version":1,"ok":false,"data":null,"error":{"code":"internal_error","message":"Bridge serialization failed"}}"#.to_owned()
}

fn guarded_json(operation: impl FnOnce() -> String) -> *mut c_char {
    match catch_unwind(AssertUnwindSafe(operation)) {
        Ok(json) => json_pointer(json),
        Err(_) => json_pointer(serialize(&failure(BridgeError::internal(
            "Zanryo bridge operation panicked",
        )))),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn zanryo_create() -> *mut BridgeHandle {
    match catch_unwind(AssertUnwindSafe(BridgeHandle::new)) {
        Ok(handle) => Box::into_raw(Box::new(handle)),
        Err(_) => ptr::null_mut(),
    }
}

/// # Safety
///
/// `handle` must be null or a live pointer returned by `zanryo_create`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn zanryo_cached_json(handle: *mut BridgeHandle) -> *mut c_char {
    guarded_json(|| {
        let Some(handle) = (unsafe { handle.as_ref() }) else {
            return serialize(&failure(BridgeError::invalid_handle()));
        };

        match handle.cached() {
            Ok(data) => serialize(&success(data)),
            Err(error) => serialize(&failure(error)),
        }
    })
}

/// # Safety
///
/// `handle` must be null or a live pointer returned by `zanryo_create`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn zanryo_refresh_json(handle: *mut BridgeHandle) -> *mut c_char {
    guarded_json(|| {
        let Some(handle) = (unsafe { handle.as_ref() }) else {
            return serialize(&failure(BridgeError::invalid_handle()));
        };

        match handle.refresh() {
            Ok(data) => serialize(&success(data)),
            Err(error) => serialize(&failure(error)),
        }
    })
}

/// # Safety
///
/// `value` must be null or a pointer returned by a Zanryo JSON function that
/// has not already been freed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn zanryo_string_free(value: *mut c_char) {
    if !value.is_null() {
        let _ = unsafe { CString::from_raw(value) };
    }
}

/// # Safety
///
/// `handle` must be null or a live pointer returned by `zanryo_create` that
/// has not already been destroyed.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn zanryo_destroy(handle: *mut BridgeHandle) {
    if !handle.is_null() {
        let _ = unsafe { Box::from_raw(handle) };
    }
}

#[cfg(test)]
mod tests {
    use std::ffi::CStr;

    use super::*;

    #[test]
    fn panic_is_converted_to_internal_error_json() {
        let pointer = guarded_json(|| panic!("bridge test panic"));
        let json = unsafe { CStr::from_ptr(pointer) }
            .to_str()
            .unwrap()
            .to_owned();
        unsafe { zanryo_string_free(pointer) };
        let value: serde_json::Value = serde_json::from_str(&json).unwrap();

        assert_eq!(value["ok"], false);
        assert_eq!(value["error"]["code"], "internal_error");
    }
}
