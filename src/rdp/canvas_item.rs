use std::fs;
use std::io::Write;
use std::path::Path;
use std::sync::{Arc, Mutex};

use flate2::write::ZlibEncoder;
use flate2::Compression;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct DirtyRect {
    pub x: u16,
    pub y: u16,
    pub width: u16,
    pub height: u16,
}

impl DirtyRect {
    pub fn union(self, other: Self) -> Self {
        let x1 = self.x.min(other.x);
        let y1 = self.y.min(other.y);
        let x2 = self
            .x
            .saturating_add(self.width)
            .max(other.x.saturating_add(other.width));
        let y2 = self
            .y
            .saturating_add(self.height)
            .max(other.y.saturating_add(other.height));
        Self {
            x: x1,
            y: y1,
            width: x2.saturating_sub(x1),
            height: y2.saturating_sub(y1),
        }
    }
}

#[derive(Debug)]
pub struct SharedFrameBuffer {
    width: u16,
    height: u16,
    rgba: Vec<u8>,
    frame_seq: u64,
    pending_dirty: Option<DirtyRect>,
    cursor_x: u16,
    cursor_y: u16,
    cursor_visible: bool,
}

impl Default for SharedFrameBuffer {
    fn default() -> Self {
        Self::new(1280, 720)
    }
}

impl SharedFrameBuffer {
    pub fn new(width: u16, height: u16) -> Self {
        let w = width.max(64);
        let h = height.max(64);
        let len = usize::from(w) * usize::from(h) * 4;
        Self {
            width: w,
            height: h,
            rgba: vec![0u8; len],
            frame_seq: 0,
            pending_dirty: None,
            cursor_x: w / 2,
            cursor_y: h / 2,
            cursor_visible: true,
        }
    }

    pub fn new_shared(width: u16, height: u16) -> Arc<Mutex<Self>> {
        Arc::new(Mutex::new(Self::new(width, height)))
    }

    pub fn width(&self) -> u16 {
        self.width
    }

    pub fn height(&self) -> u16 {
        self.height
    }

    pub fn frame_seq(&self) -> u64 {
        self.frame_seq
    }

    pub fn rgba_bytes(&self) -> &[u8] {
        &self.rgba
    }

    pub fn cursor_position(&self) -> (u16, u16) {
        (self.cursor_x, self.cursor_y)
    }

    pub fn set_cursor_position(&mut self, x: u16, y: u16) {
        self.cursor_x = x.min(self.width.saturating_sub(1));
        self.cursor_y = y.min(self.height.saturating_sub(1));
    }

    pub fn set_cursor_visible(&mut self, visible: bool) {
        self.cursor_visible = visible;
    }

    pub fn take_dirty(&mut self) -> Option<DirtyRect> {
        self.pending_dirty.take()
    }

    pub fn resize_clear(&mut self, width: u16, height: u16) {
        let w = width.max(64);
        let h = height.max(64);
        self.width = w;
        self.height = h;
        self.rgba.resize(usize::from(w) * usize::from(h) * 4, 0);
        // Vec::resize retains old bytes when shrinking. Their old row stride
        // must never be displayed as pixels belonging to the resized desktop.
        self.rgba.fill(0);
        self.cursor_x = self.cursor_x.min(w.saturating_sub(1));
        self.cursor_y = self.cursor_y.min(h.saturating_sub(1));
        self.frame_seq = self.frame_seq.wrapping_add(1);
        self.pending_dirty = Some(DirtyRect {
            x: 0,
            y: 0,
            width: w,
            height: h,
        });
    }

    pub fn update_full_rgba(&mut self, width: u16, height: u16, src_rgba: &[u8]) {
        let expected = usize::from(width) * usize::from(height) * 4;
        if src_rgba.len() < expected {
            return;
        }
        if self.width != width || self.height != height || self.rgba.len() != expected {
            self.width = width;
            self.height = height;
            self.rgba.resize(expected, 0);
        }
        self.rgba.copy_from_slice(&src_rgba[..expected]);
        self.frame_seq = self.frame_seq.wrapping_add(1);
        let rect = DirtyRect {
            x: 0,
            y: 0,
            width,
            height,
        };
        self.pending_dirty = Some(match self.pending_dirty {
            Some(prev) => prev.union(rect),
            None => rect,
        });
    }

    pub fn update_region_rgba(
        &mut self,
        full_width: u16,
        full_height: u16,
        full_rgba: &[u8],
        dirty: DirtyRect,
    ) {
        let expected = usize::from(full_width) * usize::from(full_height) * 4;
        if full_rgba.len() < expected {
            return;
        }
        if self.width != full_width || self.height != full_height || self.rgba.len() != expected {
            self.update_full_rgba(full_width, full_height, full_rgba);
            return;
        }

        let x_start = dirty.x.min(full_width);
        let y_start = dirty.y.min(full_height);
        let x_end = dirty.x.saturating_add(dirty.width).min(full_width);
        let y_end = dirty.y.saturating_add(dirty.height).min(full_height);
        if x_end <= x_start || y_end <= y_start {
            return;
        }

        let stride = usize::from(full_width) * 4;
        let row_bytes = usize::from(x_end - x_start) * 4;
        let x_offset = usize::from(x_start) * 4;

        for row in usize::from(y_start)..usize::from(y_end) {
            let start = row * stride + x_offset;
            let end = start + row_bytes;
            self.rgba[start..end].copy_from_slice(&full_rgba[start..end]);
        }

        self.frame_seq = self.frame_seq.wrapping_add(1);
        let clamped_dirty = DirtyRect {
            x: x_start,
            y: y_start,
            width: x_end - x_start,
            height: y_end - y_start,
        };
        self.pending_dirty = Some(match self.pending_dirty {
            Some(prev) => prev.union(clamped_dirty),
            None => clamped_dirty,
        });
    }

    /// Renders a Windows 11-inspired desktop frame for interactive demo sessions and unit tests.
    pub fn render_demo_desktop(
        &mut self,
        width: u16,
        height: u16,
        active_window_pos: (u16, u16),
        click_ripple: Option<(u16, u16)>,
    ) {
        let w = width.max(320);
        let h = height.max(240);
        let total = usize::from(w) * usize::from(h) * 4;
        if self.width != w || self.height != h || self.rgba.len() != total {
            self.width = w;
            self.height = h;
            self.rgba.resize(total, 0);
        }

        let taskbar_h = 44u16.min(h / 6);
        let desktop_h = h.saturating_sub(taskbar_h);
        let win_w = (w * 3 / 5).clamp(240, w.saturating_sub(32));
        let win_h = (desktop_h * 3 / 5).clamp(160, desktop_h.saturating_sub(32));
        let win_x = active_window_pos.0.min(w.saturating_sub(win_w));
        let win_y = active_window_pos.1.min(desktop_h.saturating_sub(win_h));

        for y in 0..h {
            for x in 0..w {
                let idx = (usize::from(y) * usize::from(w) + usize::from(x)) * 4;
                let (mut r, mut g, mut b) = if y >= desktop_h {
                    // Windows 11 Acrylic dark taskbar
                    (20u8, 26u8, 36u8)
                } else {
                    // Fluent Bloom blue gradient wallpaper
                    let nx = u32::from(x) * 255 / u32::from(w.max(1));
                    let ny = u32::from(y) * 255 / u32::from(h.max(1));
                    let r_val = (14 + (nx * 18 / 255)) as u8;
                    let g_val = (58 + (ny * 64 / 255)) as u8;
                    let b_val = (118 + ((255 - ny) * 90 / 255)) as u8;
                    (r_val, g_val, b_val)
                };

                // Centered taskbar icons
                if y >= desktop_h + 10 && y + 10 < h {
                    let center_x = w / 2;
                    if x >= center_x.saturating_sub(56) && x <= center_x + 56 {
                        let rel = x - center_x.saturating_sub(56);
                        if rel % 28 < 20 {
                            r = 0;
                            g = 120;
                            b = 212;
                        }
                    }
                }

                // Simulated active desktop window
                if x >= win_x && x < win_x + win_w && y >= win_y && y < win_y + win_h {
                    let local_y = y - win_y;
                    let local_x = x - win_x;
                    if local_y < 34 {
                        // Window titlebar (Windows App Fluent Dark)
                        r = 32;
                        g = 38;
                        b = 48;
                        if local_x > win_w.saturating_sub(46) {
                            r = 196;
                            g = 43;
                            b = 28;
                        }
                    } else if local_x == 0
                        || local_x + 1 == win_w
                        || local_y + 1 == win_h
                    {
                        r = 0;
                        g = 120;
                        b = 212;
                    } else {
                        // Window client area
                        r = 245;
                        g = 247;
                        b = 250;
                        if local_y > 54 && local_y < 86 && local_x > 20 && local_x < win_w - 20 {
                            r = 225;
                            g = 238;
                            b = 252;
                        }
                    }
                }

                // Optional click highlight ring
                if let Some((cx, cy)) = click_ripple {
                    let dx = i32::from(x) - i32::from(cx);
                    let dy = i32::from(y) - i32::from(cy);
                    let dist2 = dx * dx + dy * dy;
                    if (120..=260).contains(&dist2) {
                        r = 41;
                        g = 182;
                        b = 246;
                    }
                }

                self.rgba[idx] = r;
                self.rgba[idx + 1] = g;
                self.rgba[idx + 2] = b;
                self.rgba[idx + 3] = 255;
            }
        }

        self.frame_seq = self.frame_seq.wrapping_add(1);
        self.pending_dirty = Some(DirtyRect {
            x: 0,
            y: 0,
            width: w,
            height: h,
        });
    }

    /// Saves a downscaled RGBA thumbnail as a standard PNG file for the Windows App PC card grid.
    pub fn save_thumbnail_png(
        &self,
        output_path: &Path,
        target_w: u16,
        target_h: u16,
    ) -> Result<(), String> {
        if self.width == 0 || self.height == 0 || self.rgba.is_empty() {
            return Err("Framebuffer is empty".to_string());
        }
        let tw = target_w.max(32);
        let th = target_h.max(18);
        let mut scaled = Vec::with_capacity(usize::from(tw) * usize::from(th) * 4);

        for ty in 0..th {
            let sy = (u32::from(ty) * u32::from(self.height) / u32::from(th)) as usize;
            for tx in 0..tw {
                let sx = (u32::from(tx) * u32::from(self.width) / u32::from(tw)) as usize;
                let idx = (sy * usize::from(self.width) + sx) * 4;
                scaled.extend_from_slice(&self.rgba[idx..idx + 4]);
            }
        }

        let png_bytes = encode_rgba_png(u32::from(tw), u32::from(th), &scaled)?;
        if let Some(parent) = output_path.parent() {
            fs::create_dir_all(parent)
                .map_err(|e| format!("Failed to create thumbnail dir: {e}"))?;
        }
        fs::write(output_path, png_bytes)
            .map_err(|e| format!("Failed to write thumbnail PNG: {e}"))
    }
}

/// Pure-Rust minimal PNG encoder for RGBA8 buffers using `flate2` and `crc32fast`.
pub fn encode_rgba_png(width: u32, height: u32, rgba: &[u8]) -> Result<Vec<u8>, String> {
    let expected = (width as usize) * (height as usize) * 4;
    if rgba.len() < expected {
        return Err("RGBA buffer smaller than width*height*4".to_string());
    }

    let mut raw_scanlines = Vec::with_capacity((width as usize * 4 + 1) * height as usize);
    let stride = width as usize * 4;
    for y in 0..(height as usize) {
        raw_scanlines.push(0u8); // Filter type 0 (None)
        let row_start = y * stride;
        raw_scanlines.extend_from_slice(&rgba[row_start..row_start + stride]);
    }

    let mut encoder = ZlibEncoder::new(Vec::new(), Compression::fast());
    encoder
        .write_all(&raw_scanlines)
        .map_err(|e| format!("Zlib compress error: {e}"))?;
    let idat_data = encoder
        .finish()
        .map_err(|e| format!("Zlib finish error: {e}"))?;

    let mut png = Vec::with_capacity(idat_data.len() + 64);
    // PNG signature
    png.extend_from_slice(&[137, 80, 78, 71, 13, 10, 26, 10]);

    let write_chunk = |out: &mut Vec<u8>, chunk_type: &[u8; 4], data: &[u8]| {
        out.extend_from_slice(&(data.len() as u32).to_be_bytes());
        out.extend_from_slice(chunk_type);
        out.extend_from_slice(data);
        let mut hasher = crc32fast::Hasher::new();
        hasher.update(chunk_type);
        hasher.update(data);
        out.extend_from_slice(&hasher.finalize().to_be_bytes());
    };

    // IHDR chunk (width, height, bit_depth=8, color_type=6 RGBA, compression=0, filter=0, interlace=0)
    let mut ihdr = [0u8; 13];
    ihdr[0..4].copy_from_slice(&width.to_be_bytes());
    ihdr[4..8].copy_from_slice(&height.to_be_bytes());
    ihdr[8] = 8;
    ihdr[9] = 6;
    write_chunk(&mut png, b"IHDR", &ihdr);
    write_chunk(&mut png, b"IDAT", &idat_data);
    write_chunk(&mut png, b"IEND", &[]);

    Ok(png)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn resizing_clears_pixels_with_the_old_row_stride() {
        let mut fb = SharedFrameBuffer::new(800, 600);
        fb.update_full_rgba(800, 600, &vec![255; 800 * 600 * 4]);
        let sequence = fb.frame_seq();
        fb.resize_clear(450, 680);
        assert_eq!((fb.width(), fb.height()), (450, 680));
        assert!(fb.rgba_bytes().iter().all(|byte| *byte == 0));
        assert!(fb.frame_seq() > sequence);
        assert_eq!(fb.take_dirty(), Some(DirtyRect { x: 0, y: 0, width: 450, height: 680 }));
    }

    #[test]
    fn test_demo_desktop_and_png_thumbnail() {
        let mut fb = SharedFrameBuffer::new(640, 360);
        fb.render_demo_desktop(640, 360, (80, 50), Some((200, 150)));
        assert_eq!(fb.width(), 640);
        assert_eq!(fb.height(), 360);
        assert!(fb.take_dirty().is_some());

        let dir = tempdir().unwrap();
        let thumb_path = dir.path().join("test.png");
        fb.save_thumbnail_png(&thumb_path, 320, 180).unwrap();
        let bytes = std::fs::read(&thumb_path).unwrap();
        assert_eq!(&bytes[0..8], &[137, 80, 78, 71, 13, 10, 26, 10]);
    }
}
