use ironrdp_displaycontrol::{client::DisplayControlClient, pdu::MonitorLayoutEntry};
use ironrdp_session::ActiveStage;

#[cfg(test)]
fn bulk_decompressor(
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

    // A real RemoteFX surface update with a single encoded 64x64 gray tile.
    // Only the first frame carries codec/channel headers, as on affected servers.
    fn rfx_surface(first: bool, index: u32, luminance: i16) -> Vec<u8> {
        use ironrdp_pdu::codecs::rfx::*;
        use ironrdp_pdu::geometry::ExclusiveRectangle;
        use ironrdp_pdu::surface_commands::*;
        let quant = Quant::default();
        let component = |value| {
            let mut samples = vec![value; 4096];
            let mut encoded = vec![0; 16384];
            let size = ironrdp_graphics::rfx_encode_component(
                &mut samples,
                &mut encoded,
                &quant,
                EntropyAlgorithm::Rlgr3,
            )
            .unwrap();
            encoded.truncate(size);
            encoded
        };
        let y = component(luminance);
        let chroma = component(0);
        let mut blocks = Vec::new();
        if first {
            blocks.extend([
                Block::Sync(SyncPdu),
                Block::CodecVersions(CodecVersionsPdu),
                Block::Channels(ChannelsPdu(vec![RfxChannel {
                    width: 64,
                    height: 64,
                }])),
                Block::CodecChannel(CodecChannel::Context(ContextPdu {
                    flags: OperatingMode::empty(),
                    entropy_algorithm: EntropyAlgorithm::Rlgr3,
                })),
            ]);
        }
        blocks.extend([
            Block::CodecChannel(CodecChannel::FrameBegin(FrameBeginPdu {
                index,
                number_of_regions: 1,
            })),
            Block::CodecChannel(CodecChannel::Region(RegionPdu {
                rectangles: vec![RfxRectangle {
                    x: 0,
                    y: 0,
                    width: 64,
                    height: 64,
                }],
            })),
            Block::CodecChannel(CodecChannel::TileSet(TileSetPdu {
                entropy_algorithm: EntropyAlgorithm::Rlgr3,
                quants: vec![quant],
                tiles: vec![Tile {
                    y_quant_index: 0,
                    cb_quant_index: 0,
                    cr_quant_index: 0,
                    x: 0,
                    y: 0,
                    y_data: &y,
                    cb_data: &chroma,
                    cr_data: &chroma,
                }],
            })),
            Block::CodecChannel(CodecChannel::FrameEnd(FrameEndPdu)),
        ]);
        let data: Vec<u8> = blocks
            .iter()
            .flat_map(|block| encode_vec(block).unwrap())
            .collect();
        let surface = SurfaceCommand::SetSurfaceBits(SurfaceBitsPdu {
            destination: ExclusiveRectangle {
                left: 0,
                top: 0,
                right: 64,
                bottom: 64,
            },
            extended_bitmap_data: ExtendedBitmapDataPdu {
                bpp: 32,
                codec_id: 3, // IronRDP's negotiated RemoteFX codec ID.
                width: 64,
                height: 64,
                header: None,
                data: &data,
            },
        });
        let mut surface = encode_vec(&surface).unwrap();
        surface.extend(
            encode_vec(&SurfaceCommand::FrameMarker(FrameMarkerPdu {
                frame_action: FrameAction::End,
                frame_id: Some(index),
            }))
            .unwrap(),
        );
        surface
    }

    fn surface_packet(surface: &[u8], compressed: bool) -> Vec<u8> {
        let mut compressor =
            ironrdp_bulk::BulkCompressor::new(ironrdp_bulk::CompressionType::Rdp5).unwrap();
        surface_packet_with_history(surface, compressed.then_some(&mut compressor))
    }

    fn surface_packet_with_history(
        surface: &[u8],
        compressor: Option<&mut ironrdp_bulk::BulkCompressor>,
    ) -> Vec<u8> {
        use ironrdp_pdu::fast_path::*;
        use ironrdp_pdu::rdp::{client_info::CompressionType, headers::CompressionFlags};
        let compressed = compressor.map(|compressor| {
            let (length, flags) = compressor.compress(surface).unwrap();
            (flags, compressor.compressed_data(length).to_vec())
        });
        let update = encode_vec(&FastPathUpdatePdu {
            fragmentation: Fragmentation::Single,
            update_code: UpdateCode::SurfaceCommands,
            compression_flags: compressed.as_ref().map(|(flags, _)| {
                CompressionFlags::from_bits_truncate((*flags).try_into().unwrap())
            }),
            compression_type: compressed.as_ref().map(|_| CompressionType::K64),
            data: compressed
                .as_ref()
                .map_or(surface, |(_, data)| data.as_slice()),
        })
        .unwrap();
        let mut frame =
            encode_vec(&FastPathHeader::new(EncryptionFlags::empty(), update.len())).unwrap();
        frame.extend(update);
        frame
    }

    #[test]
    fn reactivation_keeps_fragmented_desktop_update_in_progress() {
        use ironrdp_pdu::{fast_path::*, Action};
        use ironrdp_session::fast_path::ProcessorBuilder;
        let fragment = |data: &[u8], fragmentation| {
            let update = encode_vec(&FastPathUpdatePdu {
                fragmentation,
                update_code: UpdateCode::SurfaceCommands,
                compression_flags: None,
                compression_type: None,
                data,
            })
            .unwrap();
            let mut frame =
                encode_vec(&FastPathHeader::new(EncryptionFlags::empty(), update.len())).unwrap();
            frame.extend(update);
            frame
        };
        let mut stage = stage(false);
        let mut image = DecodedImage::new(
            ironrdp_graphics::image_processing::PixelFormat::RgbA32,
            800,
            600,
        );
        stage
            .process(
                &mut image,
                Action::FastPath,
                &surface_packet(&rfx_surface(true, 1, 0), false),
            )
            .unwrap();
        let update = rfx_surface(false, 2, 800);
        let split = update.len() / 2;
        stage
            .process(
                &mut image,
                Action::FastPath,
                &fragment(&update[..split], Fragmentation::First),
            )
            .unwrap();
        stage.reactivate(ProcessorBuilder {
            io_channel_id: 1003,
            user_channel_id: 1001,
            share_id: 2,
            enable_server_pointer: false,
            pointer_software_rendering: false,
            bulk_decompressor: None,
        });
        assert!(!stage.graphics_received());
        let mut image = DecodedImage::new(
            ironrdp_graphics::image_processing::PixelFormat::RgbA32,
            600,
            800,
        );
        stage
            .process(
                &mut image,
                Action::FastPath,
                &fragment(&update[split..], Fragmentation::Last),
            )
            .unwrap();
        assert!(stage.graphics_received());
        assert!(image.data()[0] > 128);
    }

    #[test]
    fn reactivation_preserves_continuous_bulk_compression_history() {
        use ironrdp_pdu::{rdp::client_info::CompressionType, Action};
        use ironrdp_session::fast_path::ProcessorBuilder;
        let mut server =
            ironrdp_bulk::BulkCompressor::new(ironrdp_bulk::CompressionType::Rdp5).unwrap();
        let mut stage = stage(false);
        for index in 1..=3 {
            stage.reactivate(ProcessorBuilder {
                io_channel_id: 1003,
                user_channel_id: 1001,
                share_id: index,
                enable_server_pointer: false,
                pointer_software_rendering: false,
                bulk_decompressor: bulk_decompressor(Some(CompressionType::K64)).unwrap(),
            });
            let frame = surface_packet_with_history(
                &rfx_surface(index == 1, index, 800),
                Some(&mut server),
            );
            let mut image = DecodedImage::new(
                ironrdp_graphics::image_processing::PixelFormat::RgbA32,
                800,
                600,
            );
            stage.process(&mut image, Action::FastPath, &frame).unwrap();
            assert!(
                image.data()[0] > 128,
                "reactivation {index} must decode the same gray tile"
            );
        }
    }

    #[test]
    fn reactivation_keeps_rfx_headers_rendering_and_acknowledgements() {
        use ironrdp_pdu::{
            rdp::{client_info::CompressionType, headers::ShareDataPdu},
            Action,
        };
        use ironrdp_session::{fast_path::ProcessorBuilder, ActiveStageOutput};
        for compressed in [false, true] {
            let compression = compressed.then_some(CompressionType::K64);
            let mut stage = stage(false);
            let mut previous_pixel = Vec::new();
            for (index, width, height, luminance) in
                [(1, 800, 600, 0), (2, 600, 800, 800), (3, 800, 600, -800)]
            {
                let share_id = 10 + index;
                stage.reactivate(ProcessorBuilder {
                    io_channel_id: 1003,
                    user_channel_id: 1001,
                    share_id,
                    enable_server_pointer: false,
                    pointer_software_rendering: false,
                    bulk_decompressor: bulk_decompressor(compression).unwrap(),
                });
                let mut image = DecodedImage::new(
                    ironrdp_graphics::image_processing::PixelFormat::RgbA32,
                    width,
                    height,
                );
                let frame = surface_packet(&rfx_surface(index == 1, index, luminance), compressed);
                if index == 2 && !compressed {
                    // Replacing the processor reproduces the reported failure.
                    let error = self::stage(false)
                        .process(&mut image, Action::FastPath, &frame)
                        .unwrap_err();
                    assert!(
                        error.to_string().contains("no RFX channel found"),
                        "{error}"
                    );
                }
                let outputs = stage.process(&mut image, Action::FastPath, &frame).unwrap();
                assert!(outputs
                    .iter()
                    .any(|out| matches!(out, ActiveStageOutput::GraphicsUpdate(_))));
                assert_ne!(&image.data()[..3], previous_pixel.as_slice());
                previous_pixel = image.data()[..3].to_vec();
                let mut expected = ironrdp_core::WriteBuf::new();
                ironrdp_pdu::rdp::headers::encode_share_data(
                    1001,
                    1003,
                    share_id,
                    ShareDataPdu::FrameAcknowledge(ironrdp_pdu::codecs::rfx::FrameAcknowledgePdu {
                        frame_id: index,
                    }),
                    &mut expected,
                )
                .unwrap();
                assert!(outputs.iter().any(|out| matches!(out,
                    ActiveStageOutput::ResponseFrame(frame) if frame.as_slice() == expected.filled()
                )), "acknowledgement must use the new activation share ID");
                let input = crate::rdp::InputMapper::new(width, height).send_chord("ctrl+c");
                assert!(!stage
                    .process_fastpath_input(&mut image, &input)
                    .unwrap()
                    .is_empty());
            }
        }
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
        let mut image = DecodedImage::new(
            ironrdp_graphics::image_processing::PixelFormat::RgbA32,
            800,
            600,
        );
        stage
            .process(
                &mut image,
                ironrdp_pdu::Action::FastPath,
                &surface_packet(&rfx_surface(true, 1, 0), false),
            )
            .unwrap();
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

    #[test]
    fn initial_resize_waits_for_desktop_pixels_not_cursor_or_channel_readiness() {
        use ironrdp_pdu::surface_commands::*;
        let mut stage = stage(true);
        open_channel(&mut stage);
        send_capabilities(&mut stage);
        let mut resize = DisplayResize::default();
        resize.request(450, 680, 100);
        assert!(resize.frame(&mut stage).is_none());
        let mut image = DecodedImage::new(
            ironrdp_graphics::image_processing::PixelFormat::RgbA32,
            1280,
            820,
        );
        // Input can move a software cursor before any desktop bitmap arrives.
        let events = crate::rdp::InputMapper::new(1280, 820).send_chord("ctrl+c");
        stage.process_fastpath_input(&mut image, &events).unwrap();
        assert!(!stage.graphics_received());
        // A server frame marker alone does not mean there are desktop pixels.
        let marker = encode_vec(&SurfaceCommand::FrameMarker(FrameMarkerPdu {
            frame_action: FrameAction::End,
            frame_id: Some(1),
        }))
        .unwrap();
        stage
            .process(
                &mut image,
                ironrdp_pdu::Action::FastPath,
                &surface_packet(&marker, false),
            )
            .unwrap();
        assert!(resize.frame(&mut stage).is_none());
        stage
            .process(
                &mut image,
                ironrdp_pdu::Action::FastPath,
                &surface_packet(&rfx_surface(true, 2, 0), false),
            )
            .unwrap();
        assert!(stage.graphics_received());
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
        // XRDP can open DISP while its desktop backend is still starting.
        // Resizing then can invalidate the first screen before it is delivered.
        if !stage.graphics_received() {
            return None;
        }
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
