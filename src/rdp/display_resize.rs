use ironrdp_displaycontrol::{client::DisplayControlClient, pdu::MonitorLayoutEntry};
use ironrdp_session::ActiveStage;

pub(super) fn bulk_decompressor(
    compression: Option<ironrdp_pdu::rdp::client_info::CompressionType>,
) -> ironrdp_session::SessionResult<Option<ironrdp_bulk::BulkCompressor>> {
    use ironrdp_bulk::{BulkCompressor, CompressionType as BulkType};
    use ironrdp_pdu::rdp::client_info::CompressionType;
    let Some(compression) = compression else {
        return Ok(None);
    };
    let level = match compression {
        CompressionType::K8 => BulkType::Rdp4,
        CompressionType::K64 => BulkType::Rdp5,
        CompressionType::Rdp6 => BulkType::Rdp6,
        CompressionType::Rdp61 => BulkType::Rdp61,
    };
    BulkCompressor::new(level)
        .map(Some)
        .map_err(|e| ironrdp_session::custom_err!("restore bulk decompression after resize", e))
}

/// Resizing is optional: unsupported/not-yet-ready DISP must never end a session.
#[derive(Default)]
pub(super) struct DisplayResize {
    pending: Option<(u32, u32, u32)>,
    last_sent: Option<(u32, u32, u32)>,
}

#[cfg(test)]
mod tests {
    use super::*;
    use ironrdp_core::encode_vec;
    use ironrdp_displaycontrol::pdu::DisplayControlCapabilities;
    use ironrdp_dvc::{
        pdu::{CreateRequestPdu, DataPdu, DrdynvcDataPdu, DrdynvcServerPdu},
        DrdynvcClient,
    };
    use ironrdp_session::{image::DecodedImage, ActiveStageBuilder};
    use ironrdp_svc::{StaticChannelSet, SvcProcessor};

    #[test]
    fn reactivation_restores_negotiated_compressed_updates() {
        use ironrdp_bulk::{flags, BulkCompressor, CompressionType as BulkType};
        use ironrdp_pdu::rdp::client_info::CompressionType;
        let payload = b"compressed desktop data after rotation ".repeat(100);
        let mut server = BulkCompressor::new(BulkType::Rdp5).unwrap();
        let (length, flags) = server.compress(&payload).unwrap();
        assert_ne!(flags & flags::PACKET_COMPRESSED, 0);
        let mut restored = bulk_decompressor(Some(CompressionType::K64))
            .unwrap()
            .unwrap();
        assert_eq!(
            restored
                .decompress(server.compressed_data(length), flags)
                .unwrap(),
            payload
        );
        assert!(bulk_decompressor(None).unwrap().is_none());
    }

    fn stage(display_channel: bool) -> ActiveStage {
        let mut channels = StaticChannelSet::new();
        if display_channel {
            channels.insert(
                DrdynvcClient::new()
                    .with_dynamic_channel(DisplayControlClient::new(|_| Ok(Vec::new()))),
            );
            channels.attach_channel_id(std::any::TypeId::of::<DrdynvcClient>(), 1004);
        }
        ActiveStageBuilder {
            static_channels: channels,
            user_channel_id: 1001,
            io_channel_id: 1003,
            message_channel_id: None,
            share_id: 1,
            compression_type: None,
            enable_server_pointer: false,
            pointer_software_rendering: false,
        }
        .build()
    }

    fn open_channel(stage: &mut ActiveStage) {
        let create = DrdynvcServerPdu::Create(CreateRequestPdu::new(
            1,
            ironrdp_displaycontrol::CHANNEL_NAME.to_string(),
        ));
        stage
            .get_svc_processor_mut::<DrdynvcClient>()
            .unwrap()
            .process(&encode_vec(&create).unwrap())
            .unwrap();
    }

    fn send_capabilities(stage: &mut ActiveStage) {
        let caps = DisplayControlCapabilities::new(1, 8192, 8192).unwrap();
        let data = DrdynvcServerPdu::Data(DrdynvcDataPdu::Data(DataPdu::new(
            1,
            encode_vec(&caps).unwrap(),
        )));
        stage
            .get_svc_processor_mut::<DrdynvcClient>()
            .unwrap()
            .process(&encode_vec(&data).unwrap())
            .unwrap();
    }

    #[test]
    fn unsupported_resize_keeps_input_on_the_existing_session() {
        let mut stage = stage(false);
        let mut resize = DisplayResize::default();
        for (width, height) in [(450, 820), (820, 450), (450, 820)] {
            resize.request(width, height, 100);
            assert!(resize.frame(&mut stage).is_none());
            let mut image = DecodedImage::new(
                ironrdp_graphics::image_processing::PixelFormat::RgbA32,
                800,
                600,
            );
            let events = crate::rdp::InputMapper::new(800, 600).send_chord("ctrl+c");
            assert!(!stage
                .process_fastpath_input(&mut image, &events)
                .unwrap()
                .is_empty());
        }
    }

    #[test]
    fn resize_waits_for_capabilities_coalesces_and_deduplicates() {
        let mut stage = stage(true);
        let mut resize = DisplayResize::default();
        resize.request(450, 820, 125);
        assert!(resize.frame(&mut stage).is_none());
        open_channel(&mut stage);
        assert!(
            resize.frame(&mut stage).is_none(),
            "a channel ID alone is not ready"
        );
        resize.request(820, 450, 125);
        send_capabilities(&mut stage);
        assert!(!resize.frame(&mut stage).unwrap().is_empty());
        assert_eq!(resize.last_sent, Some((820, 450, 125)));
        resize.request(820, 450, 125);
        assert!(resize.frame(&mut stage).is_none());
        resize.request(450, 820, 125);
        resize.request(820, 450, 125);
        assert!(resize.frame(&mut stage).is_none());
        resize.request(450, 820, 125);
        assert!(resize.frame(&mut stage).is_some());
    }
}

impl DisplayResize {
    pub(super) fn request(&mut self, width: u16, height: u16, scale: u32) {
        let (width, height) = MonitorLayoutEntry::adjust_display_size(width.into(), height.into());
        let request = (width, height, scale);
        // Keep only the latest orientation, including a return to the last size.
        self.pending = if self.last_sent == Some(request) {
            None
        } else {
            Some(request)
        };
    }

    pub(super) fn frame(&mut self, stage: &mut ActiveStage) -> Option<Vec<u8>> {
        let (width, height, scale) = self.pending?;
        let channel = stage.get_dvc::<DisplayControlClient>()?;
        let client = channel.channel_processor_downcast_ref::<DisplayControlClient>()?;
        if channel.channel_id().is_none() || !client.ready() {
            return None;
        }
        match stage.encode_resize(width, height, Some(scale), None) {
            Some(Ok(frame)) => {
                self.last_sent = self.pending.take();
                Some(frame)
            }
            Some(Err(error)) => {
                // The local viewport still fits the existing desktop. A failed
                // optional layout request must not close the authenticated socket.
                tracing::warn!(%error, "Keeping current desktop after resize encoding failed");
                self.pending = None;
                None
            }
            None => None,
        }
    }
}
