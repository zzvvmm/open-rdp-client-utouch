//! Preserve interleaved traffic while exchanging activation PDUs.
use std::collections::VecDeque;

use ironrdp_connector::{ConnectorError, ConnectorErrorExt as _, ConnectorResult};
use ironrdp_pdu::{Action, PduHint};
use ironrdp_tokio::{Framed, FramedRead};

pub(super) type DeferredFrames = VecDeque<(Action, Vec<u8>)>;
const MAX_DEFERRED_BYTES: usize = 16 * 1024 * 1024;

pub(super) async fn read_input<S: FramedRead>(
    reader: &mut Framed<S>,
    hint: &dyn PduHint,
    io_channel_id: u16,
    deferred: &mut DeferredFrames,
    deadline: tokio::time::Instant,
) -> ConnectorResult<Vec<u8>> {
    loop {
        let (action, frame) = tokio::time::timeout_at(deadline, reader.read_pdu())
            .await
            .map_err(|_| ironrdp_connector::general_err!("display reactivation timed out"))?
            .map_err(|e| ironrdp_connector::custom_err!("read reactivation PDU", e))?;
        let matched = hint
            .find_size(&frame)
            .map_err(ConnectorError::decode)?
            .is_some_and(|(matched, _)| matched);
        let other_channel = matches!(action, Action::X224)
            && ironrdp_pdu::mcs::decode_send_data_indication(&frame)
                .is_ok_and(|data| data.channel_id != io_channel_id);
        if matched && !other_channel {
            return Ok(frame.to_vec());
        }
        // read_by_hint discards these frames. Losing even one compressed
        // FastPath update desynchronizes the connection's MPPC dictionary.
        if deferred.iter().map(|(_, frame)| frame.len()).sum::<usize>() + frame.len()
            > MAX_DEFERRED_BYTES
        {
            return Err(ironrdp_connector::general_err!(
                "display reactivation traffic limit exceeded"
            ));
        }
        deferred.push_back((action, frame.to_vec()));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ironrdp_core::encode_vec;
    use ironrdp_pdu::{
        fast_path::{EncryptionFlags, FastPathHeader},
        mcs::{McsMessage, SendDataIndication},
        x224::X224,
    };
    use tokio::io::AsyncWriteExt;

    fn channel_frame(channel_id: u16) -> Vec<u8> {
        encode_vec(&X224(McsMessage::SendDataIndication(SendDataIndication {
            initiator_id: 1001,
            channel_id,
            user_data: b"activation".as_slice().into(),
        })))
        .unwrap()
    }

    #[tokio::test]
    async fn activation_preserves_interleaved_graphics_and_other_channels_in_order() {
        let (client, mut server) = tokio::io::duplex(4096);
        let mut reader = ironrdp_tokio::TokioFramed::new(client);
        let mut fastpath = encode_vec(&FastPathHeader::new(EncryptionFlags::empty(), 3)).unwrap();
        fastpath.extend([3, 0, 0]); // Synchronize update.
        let svc = channel_frame(1004);
        let activation = channel_frame(1003);
        for frame in [&fastpath, &svc, &fastpath, &activation] {
            server.write_all(frame).await.unwrap();
        }
        let mut deferred = DeferredFrames::new();
        let input = read_input(
            &mut reader,
            &ironrdp_pdu::X224_HINT,
            1003,
            &mut deferred,
            tokio::time::Instant::now() + std::time::Duration::from_secs(1),
        )
        .await
        .unwrap();
        assert_eq!(input, activation);
        assert_eq!(deferred.len(), 3);
        assert_eq!(deferred.pop_front().unwrap().1, fastpath);
        assert_eq!(deferred.pop_front().unwrap().1, svc);
        assert_eq!(deferred.pop_front().unwrap().1, fastpath);
    }

    #[tokio::test]
    async fn activation_stall_has_a_deadline() {
        let (client, _server) = tokio::io::duplex(4096);
        let mut reader = ironrdp_tokio::TokioFramed::new(client);
        let error = read_input(
            &mut reader,
            &ironrdp_pdu::X224_HINT,
            1003,
            &mut DeferredFrames::new(),
            tokio::time::Instant::now() + std::time::Duration::from_millis(10),
        )
        .await
        .unwrap_err();
        assert!(error.to_string().contains("reactivation timed out"));
    }
}
