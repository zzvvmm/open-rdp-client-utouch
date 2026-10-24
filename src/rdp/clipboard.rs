use std::sync::{Arc, Mutex};

use ironrdp_cliprdr::backend::{ClipboardMessage, CliprdrBackend};
use ironrdp_cliprdr::pdu::{
    ClipboardFormat, ClipboardFormatId, ClipboardGeneralCapabilityFlags, FileContentsRequest,
    FileContentsResponse, FormatDataRequest, FormatDataResponse, LockDataId,
};
use ironrdp_core::{impl_as_any, IntoOwned as _};
use tokio::sync::mpsc;

pub struct UtClipboardBackend {
    temp_dir: String,
    local_text: Arc<Mutex<String>>,
    clipboard_tx: mpsc::UnboundedSender<ClipboardMessage>,
    remote_text_callback: Arc<dyn Fn(String) + Send + Sync>,
    last_requested_format: Option<ClipboardFormatId>,
}

impl core::fmt::Debug for UtClipboardBackend {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.debug_struct("UtClipboardBackend")
            .field("temp_dir", &self.temp_dir)
            .field("last_requested_format", &self.last_requested_format)
            .finish()
    }
}

impl_as_any!(UtClipboardBackend);

impl UtClipboardBackend {
    pub fn new(
        temp_dir: String,
        local_text: Arc<Mutex<String>>,
        clipboard_tx: mpsc::UnboundedSender<ClipboardMessage>,
        remote_text_callback: Arc<dyn Fn(String) + Send + Sync>,
    ) -> Self {
        Self {
            temp_dir,
            local_text,
            clipboard_tx,
            remote_text_callback,
            last_requested_format: None,
        }
    }

    pub fn advertise_formats() -> Vec<ClipboardFormat> {
        vec![
            ClipboardFormat::new(ClipboardFormatId::CF_UNICODETEXT),
            ClipboardFormat::new(ClipboardFormatId::CF_TEXT),
        ]
    }
}

impl CliprdrBackend for UtClipboardBackend {
    fn temporary_directory(&self) -> &str {
        &self.temp_dir
    }

    fn client_capabilities(&self) -> ClipboardGeneralCapabilityFlags {
        ClipboardGeneralCapabilityFlags::USE_LONG_FORMAT_NAMES
    }

    fn on_ready(&mut self) {}

    fn on_request_format_list(&mut self) {
        let has_local = self
            .local_text
            .lock()
            .map(|s| !s.is_empty())
            .unwrap_or(false);
        if has_local {
            let _ = self
                .clipboard_tx
                .send(ClipboardMessage::SendInitiateCopy(Self::advertise_formats()));
        } else {
            let _ = self
                .clipboard_tx
                .send(ClipboardMessage::SendInitiateCopy(Vec::new()));
        }
    }

    fn on_process_negotiated_capabilities(
        &mut self,
        _capabilities: ClipboardGeneralCapabilityFlags,
    ) {
    }

    fn on_remote_copy(&mut self, available_formats: &[ClipboardFormat]) {
        if available_formats
            .iter()
            .any(|f| f.id() == ClipboardFormatId::CF_UNICODETEXT)
        {
            self.last_requested_format = Some(ClipboardFormatId::CF_UNICODETEXT);
            let _ = self.clipboard_tx.send(ClipboardMessage::SendInitiatePaste(
                ClipboardFormatId::CF_UNICODETEXT,
            ));
        } else if available_formats
            .iter()
            .any(|f| f.id() == ClipboardFormatId::CF_TEXT)
        {
            self.last_requested_format = Some(ClipboardFormatId::CF_TEXT);
            let _ = self
                .clipboard_tx
                .send(ClipboardMessage::SendInitiatePaste(ClipboardFormatId::CF_TEXT));
        }
    }

    fn on_format_data_request(&mut self, request: FormatDataRequest) {
        let text = self
            .local_text
            .lock()
            .map(|s| s.clone())
            .unwrap_or_default();
        let response = match request.format {
            ClipboardFormatId::CF_UNICODETEXT => {
                FormatDataResponse::new_unicode_string(&text).into_owned()
            }
            ClipboardFormatId::CF_TEXT => FormatDataResponse::new_string(&text).into_owned(),
            _ => FormatDataResponse::new_error().into_owned(),
        };
        let _ = self
            .clipboard_tx
            .send(ClipboardMessage::SendFormatData(response));
    }

    fn on_format_data_response(&mut self, response: FormatDataResponse<'_>) {
        if response.is_error() {
            return;
        }
        let decoded = match self.last_requested_format {
            Some(ClipboardFormatId::CF_TEXT) => response.to_string().ok(),
            _ => response
                .to_unicode_string()
                .ok()
                .or_else(|| response.to_string().ok()),
        };
        if let Some(text) = decoded {
            if !text.is_empty() {
                if let Ok(mut guard) = self.local_text.lock() {
                    *guard = text.clone();
                }
                (self.remote_text_callback)(text);
            }
        }
    }

    fn on_file_contents_request(&mut self, request: FileContentsRequest) {
        let _ = self.clipboard_tx.send(
            ClipboardMessage::SendFileContentsResponse(FileContentsResponse::new_error(
                request.stream_id,
            )),
        );
    }

    fn on_file_contents_response(&mut self, _response: FileContentsResponse<'_>) {}

    fn on_lock(&mut self, _data_id: LockDataId) {}

    fn on_unlock(&mut self, _data_id: LockDataId) {}
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_clipboard_advertise_and_response() {
        let local_text = Arc::new(Mutex::new("Hello Ubuntu Touch RDP".to_string()));
        let (tx, mut rx) = mpsc::unbounded_channel();
        let received_remote = Arc::new(Mutex::new(String::new()));
        let received_clone = Arc::clone(&received_remote);

        let mut backend = UtClipboardBackend::new(
            "/tmp".to_string(),
            Arc::clone(&local_text),
            tx,
            Arc::new(move |text| {
                *received_clone.lock().unwrap() = text;
            }),
        );

        backend.on_request_format_list();
        assert!(matches!(
            rx.try_recv().unwrap(),
            ClipboardMessage::SendInitiateCopy(_)
        ));

        backend.on_remote_copy(&[ClipboardFormat::new(ClipboardFormatId::CF_UNICODETEXT)]);
        assert!(matches!(
            rx.try_recv().unwrap(),
            ClipboardMessage::SendInitiatePaste(ClipboardFormatId::CF_UNICODETEXT)
        ));

        let resp = FormatDataResponse::new_unicode_string("From Windows 11");
        backend.on_format_data_response(resp);
        assert_eq!(*received_remote.lock().unwrap(), "From Windows 11");
    }
}
