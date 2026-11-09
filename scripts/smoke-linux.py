#!/usr/bin/env python3
"""Render the offline demo using isolated XDG data (no real server or reports)."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--executable", default="open-rdp-client")
parser.add_argument("--platform", choices=("linux", "ubuntu-touch"), default="linux")
parser.add_argument("--theme", choices=("light", "dark"), default="dark")
parser.add_argument("--layout", choices=("grid", "list"), default="grid")
parser.add_argument("--size", default="1100x760")
parser.add_argument("--font-scale", type=float, default=1.0)
parser.add_argument("--snapshot-prefix", type=Path)
parser.add_argument("--library-fixture", action="store_true")
args = parser.parse_args()
with tempfile.TemporaryDirectory(prefix="open-rdp-smoke-") as directory:
    root = Path(directory)
    env = dict(os.environ)
    for name in ("CONFIG", "DATA", "CACHE"):
        path = root / name.lower()
        path.mkdir()
        env[f"XDG_{name}_HOME"] = str(path)
    # Preserve an existing compositor's runtime directory on Wayland.
    if not env.get("XDG_RUNTIME_DIR"):
        runtime = root / "runtime"
        runtime.mkdir(mode=0o700)
        env["XDG_RUNTIME_DIR"] = str(runtime)
    width, height = (int(value) for value in args.size.split("x"))
    if width < 320 or height < 240:
        parser.error("--size must be at least 320x240")
    env["OPEN_RDP_SMOKE_WIDTH"] = str(width)
    env["OPEN_RDP_SMOKE_HEIGHT"] = str(height)
    if not 0.5 <= args.font_scale <= 3:
        parser.error("--font-scale must be between 0.5 and 3")
    env["OPEN_RDP_SMOKE_FONT_SCALE"] = str(args.font_scale)
    if args.snapshot_prefix:
        args.snapshot_prefix.parent.mkdir(parents=True, exist_ok=True)
        env["OPEN_RDP_SMOKE_SNAPSHOT"] = str(args.snapshot_prefix.resolve())
    app_id = "open-rdp-client" if args.platform == "linux" else "rdp-client-ut.zzvvmm"
    config = root / "config" / app_id
    config.mkdir()
    (config / "settings.json").write_text(json.dumps({
        "theme_mode": args.theme, "library_layout": args.layout, "library_sort": "name", "default_scale_factor": 100,
        "default_audio_mode": "play_on_device", "default_clipboard_enabled": True,
        "trackpad_speed_percent": 100, "show_stats_overlay": False,
        "strict_cert_check": False, "report_errors": False, "auto_check_updates": False,
    }))
    if args.library_fixture:
        profiles = []
        for index, (host, title, group) in enumerate([
            ("demo.local", "Windows 11 Demo PC", "Quick Try"),
            ("workstation.example.test", "Design workstation", "Office"),
            ("192.0.2.10", "Home lab", "Personal"),
            ("server.example.test", "Development server with a longer descriptive name", "Office"),
        ]):
            profiles.append({
                "id": f"sample-{index}", "hostname": host, "port": 3389,
                "friendly_name": title, "group_name": group, "account_id": None,
                "resolution_mode": {"mode": "native"}, "scale_factor": 100,
                "clipboard_redirection": True, "audio_mode": "play_on_device",
                "default_touch_mode": "direct_touch", "enable_nla": True, "enable_tls": True,
                "last_connected_epoch": 1760000000 if index else None,
                "thumbnail_path": None, "favorite": index < 2,
            })
        (config / "profiles.json").write_text(json.dumps(profiles))
    result = subprocess.run([args.executable, "--smoke-test"], env=env,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
    print(result.stdout, end="")
    failures = ("panicked at", "Binding loop detected", "ReferenceError:", "TypeError:", "SyntaxError:", "failed to load component", "is not installed", "is not a type", "Unsupported image format", "Cannot open:", "Error decoding:", "Unable to assign", "QML module not found")
    if result.returncode or any(marker in result.stdout for marker in failures):
        raise SystemExit(result.returncode or 1)
    if args.snapshot_prefix:
        for screen in ("dashboard", "session"):
            screenshot = Path(str(args.snapshot_prefix.resolve()) + f"-{screen}.png")
            if not screenshot.is_file() or screenshot.stat().st_size == 0:
                raise SystemExit(f"Missing {screen} screenshot: {screenshot}")
    print("Offline demo rendered successfully with isolated application storage.")
