# Local IronRDP session patch

This directory contains the published `ironrdp-session` 0.11.0 crate, from
Devolutions/IronRDP commit `11a0810cfbbabd8b8023875a05e3041216d4b01b`.
The upstream MIT and Apache licenses are retained. Registry bookkeeping,
the crate's lockfile, changelog, and workspace-only original manifest are omitted.

The source changes are in `src/active_stage.rs` and `src/fast_path.rs`.
`ActiveStage::reactivate` and `Processor::reactivate` update activation-specific
parameters without rebuilding the graphics decoder. Rebuilding loses RemoteFX
context/channel headers; a server resuming frames without new headers then fails
with `no RFX channel found`. Frame acknowledgement channel/share IDs and pointer
options are refreshed. RemoteFX headers, fragment assembly, compression history,
bitmap decoder, palette, and pointer cache are retained. Resetting MPPC history
can silently corrupt decoded pixels when a server continues using its dictionary.

`graphics_received` distinguishes desktop bitmaps/surfaces from pointer-only and
frame-marker updates. The application waits for desktop content before its first
DISP request. Protocol geometry/flag diagnostics are available at debug/trace
level and contain no pixel payloads.

The application uses this method after Deactivate All/reactivation. Regression
coverage is in `src/rdp/display_resize.rs` in the application, and runs with the
normal `cargo test --locked` command. Cargo's local patch applies to transitive
users too, so the application has one consistent session crate.

The application also queues interleaved traffic during activation (instead of
dropping FastPath frames via `read_by_hint`). Its default connection configuration
does not negotiate outer bulk compression: the current engine still showed
corruption with XRDP despite state preservation. RemoteFX graphics compression
remains enabled. Re-enable bulk compression only after real-server resize tests
verify a corrected engine.

To review changes against the published crate, compare its `src` directory with
this directory. Remove the Cargo patch once an upstream version provides an
equivalent state-preserving reactivation API, and rerun the protocol tests.
