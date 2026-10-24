use std::borrow::Cow;
use std::sync::Arc;

use ironrdp_rdpsnd::client::RdpsndClientHandler;
use ironrdp_rdpsnd::pdu::{AudioFormat, PitchPdu, VolumePdu, WaveFormat};

#[derive(Debug, Clone)]
pub struct PcmAudioChunk {
    pub sample_rate: u32,
    pub channels: u16,
    pub bits_per_sample: u16,
    pub pcm_bytes: Vec<u8>,
}

pub struct UtRdpsndHandler {
    supported_formats: Vec<AudioFormat>,
    volume_left: u16,
    volume_right: u16,
    sink_callback: Arc<dyn Fn(PcmAudioChunk) + Send + Sync>,
}

impl core::fmt::Debug for UtRdpsndHandler {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        f.debug_struct("UtRdpsndHandler")
            .field("formats", &self.supported_formats.len())
            .field("volume_left", &self.volume_left)
            .field("volume_right", &self.volume_right)
            .finish()
    }
}

impl UtRdpsndHandler {
    pub fn new(sink_callback: Arc<dyn Fn(PcmAudioChunk) + Send + Sync>) -> Self {
        let supported_formats = vec![
            AudioFormat {
                format: WaveFormat::PCM,
                n_channels: 2,
                n_samples_per_sec: 44_100,
                n_avg_bytes_per_sec: 44_100 * 2 * 2,
                n_block_align: 4,
                bits_per_sample: 16,
                data: None,
            },
            AudioFormat {
                format: WaveFormat::PCM,
                n_channels: 2,
                n_samples_per_sec: 48_000,
                n_avg_bytes_per_sec: 48_000 * 2 * 2,
                n_block_align: 4,
                bits_per_sample: 16,
                data: None,
            },
        ];
        Self {
            supported_formats,
            volume_left: 0xFFFF,
            volume_right: 0xFFFF,
            sink_callback,
        }
    }
}

impl RdpsndClientHandler for UtRdpsndHandler {
    fn get_formats(&self) -> &[AudioFormat] {
        &self.supported_formats
    }

    fn wave(&mut self, format_no: usize, _ts: u32, data: Cow<'_, [u8]>) {
        let Some(fmt) = self.supported_formats.get(format_no) else {
            return;
        };
        if data.is_empty() {
            return;
        }
        let mut pcm_bytes = data.into_owned();
        // Apply volume attenuation if server set volume < 100%
        if self.volume_left < 0xFFFF || self.volume_right < 0xFFFF {
            let avg_vol = (u32::from(self.volume_left) + u32::from(self.volume_right)) / 2;
            for sample_bytes in pcm_bytes.chunks_exact_mut(2) {
                let sample = i16::from_le_bytes([sample_bytes[0], sample_bytes[1]]);
                let scaled = ((i32::from(sample) * (avg_vol as i32)) >> 16) as i16;
                let out = scaled.to_le_bytes();
                sample_bytes[0] = out[0];
                sample_bytes[1] = out[1];
            }
        }

        (self.sink_callback)(PcmAudioChunk {
            sample_rate: fmt.n_samples_per_sec,
            channels: fmt.n_channels,
            bits_per_sample: fmt.bits_per_sample,
            pcm_bytes,
        });
    }

    fn set_volume(&mut self, volume: VolumePdu) {
        self.volume_left = volume.volume_left;
        self.volume_right = volume.volume_right;
    }

    fn set_pitch(&mut self, _pitch: PitchPdu) {}

    fn close(&mut self) {}
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Mutex;

    #[test]
    fn test_rdpsnd_handler_pcm_dispatch() {
        let chunks = Arc::new(Mutex::new(Vec::new()));
        let chunks_clone = Arc::clone(&chunks);
        let mut handler = UtRdpsndHandler::new(Arc::new(move |chunk| {
            chunks_clone.lock().unwrap().push(chunk);
        }));

        assert_eq!(handler.get_formats().len(), 2);
        handler.wave(0, 100, Cow::Borrowed(&[0u8, 16, 0, 16]));
        let guard = chunks.lock().unwrap();
        assert_eq!(guard.len(), 1);
        assert_eq!(guard[0].sample_rate, 44_100);
    }
}
