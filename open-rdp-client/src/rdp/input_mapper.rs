use ironrdp_pdu::input::fast_path::{FastPathInputEvent, KeyboardFlags};
use ironrdp_pdu::input::mouse::PointerFlags;
use ironrdp_pdu::input::MousePdu;
use serde::{Deserialize, Serialize};
use smallvec::{smallvec, SmallVec};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StickyState {
    Off,
    Latched,
    Locked,
}

impl Default for StickyState {
    fn default() -> Self {
        Self::Off
    }
}

impl StickyState {
    pub fn cycle_tap(self) -> Self {
        match self {
            Self::Off => Self::Latched,
            Self::Latched => Self::Locked,
            Self::Locked => Self::Off,
        }
    }

    pub fn is_active(self) -> bool {
        !matches!(self, Self::Off)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MouseButtonKind {
    Left,
    Right,
    Middle,
}

impl MouseButtonKind {
    pub fn from_qt_button(btn: i32) -> Self {
        match btn {
            2 => Self::Right,
            4 => Self::Middle,
            _ => Self::Left,
        }
    }

    pub fn to_pointer_flag(self) -> PointerFlags {
        match self {
            Self::Left => PointerFlags::LEFT_BUTTON,
            Self::Right => PointerFlags::RIGHT_BUTTON,
            Self::Middle => PointerFlags::MIDDLE_BUTTON_OR_WHEEL,
        }
    }
}

#[derive(Debug, Clone)]
pub struct InputMapper {
    desktop_width: u16,
    desktop_height: u16,
    cursor_x: u16,
    cursor_y: u16,
    rem_dx: f32,
    rem_dy: f32,
    pub ctrl: StickyState,
    pub alt: StickyState,
    pub shift: StickyState,
    pub win: StickyState,
}

impl Default for InputMapper {
    fn default() -> Self {
        Self::new(1280, 720)
    }
}

impl InputMapper {
    pub fn new(desktop_width: u16, desktop_height: u16) -> Self {
        let w = desktop_width.max(64);
        let h = desktop_height.max(64);
        Self {
            desktop_width: w,
            desktop_height: h,
            cursor_x: w / 2,
            cursor_y: h / 2,
            rem_dx: 0.0,
            rem_dy: 0.0,
            ctrl: StickyState::Off,
            alt: StickyState::Off,
            shift: StickyState::Off,
            win: StickyState::Off,
        }
    }

    pub fn set_desktop_size(&mut self, width: u16, height: u16) {
        self.desktop_width = width.max(64);
        self.desktop_height = height.max(64);
        self.cursor_x = self.cursor_x.min(self.desktop_width - 1);
        self.cursor_y = self.cursor_y.min(self.desktop_height - 1);
    }

    pub fn cursor_position(&self) -> (u16, u16) {
        (self.cursor_x, self.cursor_y)
    }

    pub fn toggle_sticky_modifier(&mut self, modifier_name: &str) -> StickyState {
        let target = match modifier_name.to_ascii_lowercase().as_str() {
            "ctrl" | "control" => &mut self.ctrl,
            "alt" => &mut self.alt,
            "shift" => &mut self.shift,
            "win" | "meta" | "super" => &mut self.win,
            _ => return StickyState::Off,
        };
        *target = target.cycle_tap();
        *target
    }

    pub fn clear_all_modifiers(&mut self) {
        self.ctrl = StickyState::Off;
        self.alt = StickyState::Off;
        self.shift = StickyState::Off;
        self.win = StickyState::Off;
    }

    /// Relative trackpad movement (Windows App Mouse Pointer Mode).
    pub fn move_relative(
        &mut self,
        dx: f32,
        dy: f32,
        speed_percent: u32,
    ) -> SmallVec<[FastPathInputEvent; 2]> {
        let scale = (speed_percent.clamp(25, 300) as f32) / 100.0;
        let scaled_dx = dx * scale + self.rem_dx;
        let scaled_dy = dy * scale + self.rem_dy;

        let step_x = scaled_dx.trunc() as i32;
        let step_y = scaled_dy.trunc() as i32;
        self.rem_dx = scaled_dx - (step_x as f32);
        self.rem_dy = scaled_dy - (step_y as f32);

        let next_x = (i32::from(self.cursor_x) + step_x)
            .clamp(0, i32::from(self.desktop_width.saturating_sub(1))) as u16;
        let next_y = (i32::from(self.cursor_y) + step_y)
            .clamp(0, i32::from(self.desktop_height.saturating_sub(1))) as u16;

        self.cursor_x = next_x;
        self.cursor_y = next_y;

        smallvec![FastPathInputEvent::MouseEvent(MousePdu {
            flags: PointerFlags::MOVE,
            number_of_wheel_rotation_units: 0,
            x_position: self.cursor_x,
            y_position: self.cursor_y,
        })]
    }

    /// Direct Touch / Hardware mouse absolute coordinate movement.
    pub fn move_absolute(&mut self, x: u16, y: u16) -> SmallVec<[FastPathInputEvent; 2]> {
        self.cursor_x = x.min(self.desktop_width.saturating_sub(1));
        self.cursor_y = y.min(self.desktop_height.saturating_sub(1));
        smallvec![FastPathInputEvent::MouseEvent(MousePdu {
            flags: PointerFlags::MOVE,
            number_of_wheel_rotation_units: 0,
            x_position: self.cursor_x,
            y_position: self.cursor_y,
        })]
    }

    pub fn mouse_button(
        &self,
        button: MouseButtonKind,
        pressed: bool,
    ) -> SmallVec<[FastPathInputEvent; 2]> {
        let mut flags = button.to_pointer_flag();
        if pressed {
            flags |= PointerFlags::DOWN;
        }
        smallvec![FastPathInputEvent::MouseEvent(MousePdu {
            flags,
            number_of_wheel_rotation_units: 0,
            x_position: self.cursor_x,
            y_position: self.cursor_y,
        })]
    }

    pub fn mouse_click(
        &self,
        button: MouseButtonKind,
        double_click: bool,
    ) -> SmallVec<[FastPathInputEvent; 4]> {
        let down = FastPathInputEvent::MouseEvent(MousePdu {
            flags: button.to_pointer_flag() | PointerFlags::DOWN,
            number_of_wheel_rotation_units: 0,
            x_position: self.cursor_x,
            y_position: self.cursor_y,
        });
        let up = FastPathInputEvent::MouseEvent(MousePdu {
            flags: button.to_pointer_flag(),
            number_of_wheel_rotation_units: 0,
            x_position: self.cursor_x,
            y_position: self.cursor_y,
        });
        if double_click {
            smallvec![down, up, down, up]
        } else {
            smallvec![down, up]
        }
    }

    pub fn mouse_scroll(
        &self,
        vertical_units: i16,
        horizontal_units: i16,
    ) -> SmallVec<[FastPathInputEvent; 2]> {
        let mut events = SmallVec::new();
        if vertical_units != 0 {
            let clamped = vertical_units.clamp(-240, 240);
            events.push(FastPathInputEvent::MouseEvent(MousePdu {
                flags: PointerFlags::VERTICAL_WHEEL,
                number_of_wheel_rotation_units: clamped,
                x_position: self.cursor_x,
                y_position: self.cursor_y,
            }));
        }
        if horizontal_units != 0 {
            let clamped = horizontal_units.clamp(-240, 240);
            events.push(FastPathInputEvent::MouseEvent(MousePdu {
                flags: PointerFlags::HORIZONTAL_WHEEL,
                number_of_wheel_rotation_units: clamped,
                x_position: self.cursor_x,
                y_position: self.cursor_y,
            }));
        }
        events
    }

    /// Maps a virtual key name from `VirtualKeyBar.qml` (`Esc`, `Tab`, `Up`, `F1`, etc.)
    /// wrapped with any active sticky modifiers (`Ctrl`, `Alt`, `Shift`, `Win`).
    pub fn send_virtual_key(&mut self, key_name: &str) -> Vec<FastPathInputEvent> {
        if let Some((scancode, extended)) = virtual_key_to_scancode(key_name) {
            self.wrap_with_active_modifiers(scancode, extended)
        } else if key_name.chars().count() == 1 {
            let ch = key_name.chars().next().unwrap();
            self.send_text_char(ch)
        } else {
            Vec::new()
        }
    }

    /// Maps a Qt key event (`Qt::Key_*` and text) into RDP FastPath keyboard events.
    pub fn map_qt_key(
        &mut self,
        qt_key: i32,
        text: &str,
        pressed: bool,
    ) -> Vec<FastPathInputEvent> {
        if let Some((scancode, extended)) = qt_key_to_scancode(qt_key) {
            if pressed && self.has_any_active_modifier() && !is_modifier_qt_key(qt_key) {
                return self.wrap_with_active_modifiers(scancode, extended);
            }
            let mut flags = if extended {
                KeyboardFlags::EXTENDED
            } else {
                KeyboardFlags::empty()
            };
            if !pressed {
                flags |= KeyboardFlags::RELEASE;
            }
            return vec![FastPathInputEvent::KeyboardEvent(flags, scancode)];
        }

        if pressed {
            let mut out = Vec::new();
            for ch in text.chars() {
                if !ch.is_control() {
                    out.extend(self.send_text_char(ch));
                }
            }
            out
        } else {
            Vec::new()
        }
    }

    /// Sends a special chord such as `"ctrl+alt+del"`, `"alt+tab"`, `"win+d"`, `"win+l"`.
    pub fn send_chord(&mut self, chord_name: &str) -> Vec<FastPathInputEvent> {
        let normalized = chord_name.trim().to_ascii_lowercase();
        let canonical = match normalized.as_str() {
            "cad" => "ctrl+alt+del",
            "start" => "win",
            "show_desktop" => "win+d",
            "lock_pc" => "win+l",
            "task_manager" => "ctrl+shift+esc",
            other => other,
        };
        let mut parts: Vec<_> = canonical.split('+').map(str::trim).collect();
        let Some(key_name) = parts.pop() else {
            return Vec::new();
        };
        let primary = virtual_key_to_scancode(key_name).or_else(|| {
            if key_name.chars().count() == 1 {
                ascii_to_scancode(key_name.chars().next()?).map(|(scancode, _)| (scancode, false))
            } else {
                None
            }
        });
        let Some(primary) = primary else {
            return Vec::new();
        };
        let mut keys = Vec::with_capacity(5);
        for modifier in parts {
            let key = match modifier {
                "ctrl" | "control" => (0x1D, false),
                "alt" => (0x38, false),
                "shift" => (0x2A, false),
                "win" | "meta" | "super" => (0x5B, true),
                _ => return Vec::new(),
            };
            if !keys.contains(&key) {
                keys.push(key);
            }
        }
        keys.push(primary);
        self.consume_latched_modifiers();
        chord_events(&keys)
    }

    fn send_text_char(&mut self, ch: char) -> Vec<FastPathInputEvent> {
        if let Some((scancode, needs_shift)) = ascii_to_scancode(ch) {
            if self.has_any_active_modifier() {
                return self.wrap_with_active_modifiers(scancode, false);
            }
            let mut events = Vec::with_capacity(4);
            if needs_shift {
                events.push(FastPathInputEvent::KeyboardEvent(
                    KeyboardFlags::empty(),
                    0x2A,
                ));
            }
            events.push(FastPathInputEvent::KeyboardEvent(
                KeyboardFlags::empty(),
                scancode,
            ));
            events.push(FastPathInputEvent::KeyboardEvent(
                KeyboardFlags::RELEASE,
                scancode,
            ));
            if needs_shift {
                events.push(FastPathInputEvent::KeyboardEvent(
                    KeyboardFlags::RELEASE,
                    0x2A,
                ));
            }
            return events;
        }

        self.consume_latched_modifiers();
        let mut utf16_buf = [0u16; 2];
        let units = ch.encode_utf16(&mut utf16_buf);
        let mut events = Vec::with_capacity(units.len() * 2);
        for &unit in units.iter() {
            events.push(FastPathInputEvent::UnicodeKeyboardEvent(
                KeyboardFlags::empty(),
                unit,
            ));
            events.push(FastPathInputEvent::UnicodeKeyboardEvent(
                KeyboardFlags::RELEASE,
                unit,
            ));
        }
        events
    }

    fn has_any_active_modifier(&self) -> bool {
        self.ctrl.is_active()
            || self.alt.is_active()
            || self.shift.is_active()
            || self.win.is_active()
    }

    fn consume_latched_modifiers(&mut self) {
        if self.ctrl == StickyState::Latched {
            self.ctrl = StickyState::Off;
        }
        if self.alt == StickyState::Latched {
            self.alt = StickyState::Off;
        }
        if self.shift == StickyState::Latched {
            self.shift = StickyState::Off;
        }
        if self.win == StickyState::Latched {
            self.win = StickyState::Off;
        }
    }

    fn wrap_with_active_modifiers(
        &mut self,
        scancode: u8,
        extended: bool,
    ) -> Vec<FastPathInputEvent> {
        let mut active_mods: SmallVec<[(u8, bool); 4]> = SmallVec::new();
        if self.ctrl.is_active() {
            active_mods.push((0x1D, false));
        }
        if self.alt.is_active() {
            active_mods.push((0x38, false));
        }
        if self.shift.is_active() {
            active_mods.push((0x2A, false));
        }
        if self.win.is_active() {
            active_mods.push((0x5B, true));
        }

        self.consume_latched_modifiers();

        let mut events = Vec::with_capacity(active_mods.len() * 2 + 2);
        for &(mod_sc, mod_ext) in &active_mods {
            let flags = if mod_ext {
                KeyboardFlags::EXTENDED
            } else {
                KeyboardFlags::empty()
            };
            events.push(FastPathInputEvent::KeyboardEvent(flags, mod_sc));
        }

        let key_down_flags = if extended {
            KeyboardFlags::EXTENDED
        } else {
            KeyboardFlags::empty()
        };
        events.push(FastPathInputEvent::KeyboardEvent(key_down_flags, scancode));
        events.push(FastPathInputEvent::KeyboardEvent(
            key_down_flags | KeyboardFlags::RELEASE,
            scancode,
        ));

        for &(mod_sc, mod_ext) in active_mods.iter().rev() {
            let flags = if mod_ext {
                KeyboardFlags::EXTENDED | KeyboardFlags::RELEASE
            } else {
                KeyboardFlags::RELEASE
            };
            events.push(FastPathInputEvent::KeyboardEvent(flags, mod_sc));
        }

        events
    }
}

fn chord_events(keys: &[(u8, bool)]) -> Vec<FastPathInputEvent> {
    let mut events = Vec::with_capacity(keys.len() * 2);
    for &(sc, ext) in keys {
        let flags = if ext {
            KeyboardFlags::EXTENDED
        } else {
            KeyboardFlags::empty()
        };
        events.push(FastPathInputEvent::KeyboardEvent(flags, sc));
    }
    for &(sc, ext) in keys.iter().rev() {
        let flags = if ext {
            KeyboardFlags::EXTENDED | KeyboardFlags::RELEASE
        } else {
            KeyboardFlags::RELEASE
        };
        events.push(FastPathInputEvent::KeyboardEvent(flags, sc));
    }
    events
}

fn is_modifier_qt_key(qt_key: i32) -> bool {
    matches!(qt_key, 0x01000020 | 0x01000021 | 0x01000022 | 0x01000023)
}

pub fn virtual_key_to_scancode(name: &str) -> Option<(u8, bool)> {
    match name.trim().to_ascii_lowercase().as_str() {
        "esc" | "escape" => Some((0x01, false)),
        "tab" => Some((0x0F, false)),
        "enter" | "return" => Some((0x1C, false)),
        "bksp" | "backspace" => Some((0x0E, false)),
        "space" => Some((0x39, false)),
        "ins" | "insert" => Some((0x52, true)),
        "del" | "delete" => Some((0x53, true)),
        "home" => Some((0x47, true)),
        "end" => Some((0x4F, true)),
        "pgup" | "pageup" => Some((0x49, true)),
        "pgdn" | "pagedown" => Some((0x51, true)),
        "up" | "↑" => Some((0x48, true)),
        "down" | "↓" => Some((0x50, true)),
        "left" | "←" => Some((0x4B, true)),
        "right" | "→" => Some((0x4D, true)),
        "win" | "super" | "meta" => Some((0x5B, true)),
        "f1" => Some((0x3B, false)),
        "f2" => Some((0x3C, false)),
        "f3" => Some((0x3D, false)),
        "f4" => Some((0x3E, false)),
        "f5" => Some((0x3F, false)),
        "f6" => Some((0x40, false)),
        "f7" => Some((0x41, false)),
        "f8" => Some((0x42, false)),
        "f9" => Some((0x43, false)),
        "f10" => Some((0x44, false)),
        "f11" => Some((0x57, false)),
        "f12" => Some((0x58, false)),
        _ => None,
    }
}

pub fn qt_key_to_scancode(qt_key: i32) -> Option<(u8, bool)> {
    match qt_key {
        0x01000000 => Some((0x01, false)), // Qt::Key_Escape
        0x01000001 => Some((0x0F, false)), // Qt::Key_Tab
        0x01000003 => Some((0x0E, false)), // Qt::Key_Backspace
        0x01000004 | 0x01000005 => Some((0x1C, false)), // Return / Enter
        0x01000006 => Some((0x52, true)),  // Insert
        0x01000007 => Some((0x53, true)),  // Delete
        0x01000010 => Some((0x47, true)),  // Home
        0x01000011 => Some((0x4F, true)),  // End
        0x01000012 => Some((0x4B, true)),  // Left
        0x01000013 => Some((0x48, true)),  // Up
        0x01000014 => Some((0x4D, true)),  // Right
        0x01000015 => Some((0x50, true)),  // Down
        0x01000016 => Some((0x49, true)),  // PageUp
        0x01000017 => Some((0x51, true)),  // PageDown
        0x01000020 => Some((0x2A, false)), // Shift
        0x01000021 => Some((0x1D, false)), // Control
        0x01000022 => Some((0x5B, true)),  // Meta / Super
        0x01000023 => Some((0x38, false)), // Alt
        0x01000030..=0x01000039 => Some((0x3B + ((qt_key - 0x01000030) as u8), false)), // F1..F10
        0x0100003a => Some((0x57, false)), // F11
        0x0100003b => Some((0x58, false)), // F12
        0x20 => Some((0x39, false)),       // Space
        _ => None,
    }
}

fn ascii_to_scancode(ch: char) -> Option<(u8, bool)> {
    let lower = ch.to_ascii_lowercase();
    let shifted = ch.is_ascii_uppercase();
    let sc = match lower {
        'a' => 0x1E,
        'b' => 0x30,
        'c' => 0x2E,
        'd' => 0x20,
        'e' => 0x12,
        'f' => 0x21,
        'g' => 0x22,
        'h' => 0x23,
        'i' => 0x17,
        'j' => 0x24,
        'k' => 0x25,
        'l' => 0x26,
        'm' => 0x32,
        'n' => 0x31,
        'o' => 0x18,
        'p' => 0x19,
        'q' => 0x10,
        'r' => 0x13,
        's' => 0x1F,
        't' => 0x14,
        'u' => 0x16,
        'v' => 0x2F,
        'w' => 0x11,
        'x' => 0x2D,
        'y' => 0x15,
        'z' => 0x2C,
        '1' => 0x02,
        '2' => 0x03,
        '3' => 0x04,
        '4' => 0x05,
        '5' => 0x06,
        '6' => 0x07,
        '7' => 0x08,
        '8' => 0x09,
        '9' => 0x0A,
        '0' => 0x0B,
        '-' => 0x0C,
        '=' => 0x0D,
        '[' => 0x1A,
        ']' => 0x1B,
        ';' => 0x27,
        '\'' => 0x28,
        '`' => 0x29,
        '\\' => 0x2B,
        ',' => 0x33,
        '.' => 0x34,
        '/' => 0x35,
        _ => return None,
    };
    Some((sc, shifted))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_sticky_modifier_latch_and_lock() {
        let mut mapper = InputMapper::new(1920, 1080);
        assert_eq!(mapper.toggle_sticky_modifier("ctrl"), StickyState::Latched);
        let events = mapper.send_virtual_key("c");
        // Ctrl down, C down, C up, Ctrl up = 4 events, and Latched resets to Off
        assert_eq!(events.len(), 4);
        assert_eq!(mapper.ctrl, StickyState::Off);

        // Double tap -> Locked -> stays active across multiple keys
        assert_eq!(mapper.toggle_sticky_modifier("alt"), StickyState::Latched);
        assert_eq!(mapper.toggle_sticky_modifier("alt"), StickyState::Locked);
        let _ = mapper.send_virtual_key("tab");
        assert_eq!(mapper.alt, StickyState::Locked);
    }

    #[test]
    fn test_trackpad_relative_and_direct_touch() {
        let mut mapper = InputMapper::new(1280, 720);
        assert_eq!(mapper.cursor_position(), (640, 360));
        let _ = mapper.move_relative(50.0, -30.0, 100);
        assert_eq!(mapper.cursor_position(), (690, 330));

        let _ = mapper.move_absolute(9999, 9999);
        assert_eq!(mapper.cursor_position(), (1279, 719));
    }

    #[test]
    fn test_ctrl_alt_del_chord() {
        let mut mapper = InputMapper::new(1280, 720);
        let cad = mapper.send_chord("ctrl+alt+del");
        assert_eq!(cad.len(), 6);
    }

    #[test]
    fn test_linux_and_editing_shortcuts_release_every_key() {
        let mut mapper = InputMapper::new(1280, 720);
        for (chord, scancodes) in [
            ("ctrl+c", vec![0x1D, 0x2E]),
            ("ctrl+v", vec![0x1D, 0x2F]),
            ("ctrl+a", vec![0x1D, 0x1E]),
            ("ctrl+alt+t", vec![0x1D, 0x38, 0x14]),
            ("alt+f2", vec![0x38, 0x3C]),
            ("alt+f4", vec![0x38, 0x3E]),
            ("ctrl+shift+c", vec![0x1D, 0x2A, 0x2E]),
            ("ctrl+shift+v", vec![0x1D, 0x2A, 0x2F]),
            ("ctrl+alt+d", vec![0x1D, 0x38, 0x20]),
        ] {
            let events = mapper.send_chord(chord);
            assert_eq!(events.len(), scancodes.len() * 2, "{chord}");
            for (event, expected) in events.iter().take(scancodes.len()).zip(&scancodes) {
                assert!(matches!(event, FastPathInputEvent::KeyboardEvent(flags, key)
                    if *flags == KeyboardFlags::empty() && key == expected), "{chord}");
            }
            for (event, expected) in events.iter().skip(scancodes.len()).zip(scancodes.iter().rev()) {
                assert!(matches!(event, FastPathInputEvent::KeyboardEvent(flags, key)
                    if *flags == KeyboardFlags::RELEASE && key == expected), "{chord}");
            }
        }
    }

    #[test]
    fn test_shortcut_validation_preserves_latched_modifiers() {
        let mut mapper = InputMapper::default();
        mapper.toggle_sticky_modifier("ctrl");
        for invalid in ["", "ctrl+", "bogus+c", "ctrl+unknown", "ctrl++c"] {
            assert!(mapper.send_chord(invalid).is_empty());
            assert_eq!(mapper.ctrl, StickyState::Latched);
        }
        assert_eq!(mapper.send_chord(" CTRL + ctrl + C ").len(), 4);
        assert_eq!(mapper.ctrl, StickyState::Off);
    }

    #[test]
    fn test_navigation_keys_have_balanced_extended_events() {
        let mut mapper = InputMapper::default();
        for key_name in ["Left", "Right", "Up", "Down", "Home", "End", "PgUp", "PgDn", "Del"] {
            let events = mapper.send_virtual_key(key_name);
            assert_eq!(events.len(), 2);
            assert!(matches!(events[0], FastPathInputEvent::KeyboardEvent(flags, _)
                if flags == KeyboardFlags::EXTENDED));
            assert!(matches!(events[1], FastPathInputEvent::KeyboardEvent(flags, _)
                if flags == KeyboardFlags::EXTENDED | KeyboardFlags::RELEASE));
        }
    }
}
