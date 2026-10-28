pub mod app_controller;
pub mod error_reporting;
pub mod models;
pub mod rdp;
pub mod storage;

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_int, c_uchar, c_void};
use std::ptr;
use std::slice;
use std::sync::Arc;

use app_controller::AppController;
use storage::{CredentialVault, StorageDatabase};

pub type RdpUiEventCallback =
    extern "C" fn(json_ptr: *const c_char, bin_ptr: *const c_uchar, bin_len: usize, user_data: *mut c_void);

pub struct RdpAppHandle {
    controller: Arc<AppController>,
}

#[derive(Copy, Clone)]
struct SendUserData(*mut c_void);
unsafe impl Send for SendUserData {}
unsafe impl Sync for SendUserData {}

#[no_mangle]
pub extern "C" fn rdp_app_create(
    callback: RdpUiEventCallback,
    user_data: *mut c_void,
) -> *mut RdpAppHandle {
    let _ = tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info")),
        )
        .try_init();

    let db = match StorageDatabase::open_default() {
        Ok(db) => db,
        Err(e) => {
            eprintln!("Failed to open storage database: {e}");
            return ptr::null_mut();
        }
    };
    let vault = match CredentialVault::open_default() {
        Ok(v) => v,
        Err(e) => {
            eprintln!("Failed to open credential vault: {e}");
            return ptr::null_mut();
        }
    };

    let send_ctx = SendUserData(user_data);
    let controller = AppController::new(
        db,
        vault,
        Arc::new(move |json_str, bin_bytes| {
            let ctx = send_ctx;
            if let Ok(c_str) = CString::new(json_str) {
                let ptr_bytes = if bin_bytes.is_empty() {
                    ptr::null()
                } else {
                    bin_bytes.as_ptr()
                };
                callback(c_str.as_ptr(), ptr_bytes, bin_bytes.len(), ctx.0);
            }
        }),
    );

    Box::into_raw(Box::new(RdpAppHandle { controller }))
}

#[no_mangle]
pub unsafe extern "C" fn rdp_app_dispatch(
    handle: *mut RdpAppHandle,
    action_json: *const c_char,
) -> c_int {
    if handle.is_null() || action_json.is_null() {
        return -1;
    }
    let handle_ref = &*handle;
    let Ok(json_str) = CStr::from_ptr(action_json).to_str() else {
        return -2;
    };
    match handle_ref.controller.dispatch_action(json_str) {
        Ok(()) => 0,
        Err(err) => {
            let err_json = serde_json::json!({
                "type": "toast_error",
                "message": err,
            })
            .to_string();
            let _ = CString::new(err_json);
            -3
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn rdp_app_framebuffer_size(
    handle: *mut RdpAppHandle,
    out_width: *mut u16,
    out_height: *mut u16,
    out_seq: *mut u64,
) -> c_int {
    if handle.is_null() {
        return -1;
    }
    let fb_arc = (*handle).controller.framebuffer();
    let Ok(fb) = fb_arc.lock() else {
        return -2;
    };
    if !out_width.is_null() {
        *out_width = fb.width();
    }
    if !out_height.is_null() {
        *out_height = fb.height();
    }
    if !out_seq.is_null() {
        *out_seq = fb.frame_seq();
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn rdp_app_copy_framebuffer_rgba(
    handle: *mut RdpAppHandle,
    dst_rgba: *mut c_uchar,
    dst_capacity: usize,
) -> c_int {
    if handle.is_null() || dst_rgba.is_null() {
        return -1;
    }
    let fb_arc = (*handle).controller.framebuffer();
    let Ok(fb) = fb_arc.lock() else {
        return -2;
    };
    let src = fb.rgba_bytes();
    if dst_capacity < src.len() {
        return -3;
    }
    let dst = slice::from_raw_parts_mut(dst_rgba, src.len());
    dst.copy_from_slice(src);
    0
}

#[no_mangle]
pub unsafe extern "C" fn rdp_app_destroy(handle: *mut RdpAppHandle) {
    if !handle.is_null() {
        let _ = Box::from_raw(handle);
    }
}

/// Qt forwards only an allowlisted category and a source location, never log text.
#[no_mangle]
pub unsafe extern "C" fn rdp_report_ui_error(code: *const c_char, file: *const c_char, line: u32, fatal: c_int) {
    if code.is_null() { return; }
    let Some(reporter) = error_reporting::current() else { return; };
    let Ok(code) = CStr::from_ptr(code).to_str() else { return; };
    let Some(code) = error_reporting::ErrorCode::from_ui(code) else { return; };
    let source = if file.is_null() { "" } else { CStr::from_ptr(file).to_str().unwrap_or_default() };
    reporter.capture(code, source, line);
    if fatal != 0 { reporter.flush(std::time::Duration::from_secs(2)); }
}
