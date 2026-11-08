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
    config = root / "config" / "open-rdp-client"
    config.mkdir()
    (config / "settings.json").write_text(json.dumps({
        "theme_mode": "dark", "default_scale_factor": 100,
        "default_audio_mode": "play_on_device", "default_clipboard_enabled": True,
        "trackpad_speed_percent": 100, "show_stats_overlay": False,
        "strict_cert_check": False, "report_errors": False,
    }))
    result = subprocess.run([args.executable, "--smoke-test"], env=env,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
    print(result.stdout, end="")
    failures = ("panicked at", "Binding loop detected", "ReferenceError:", "TypeError:", "SyntaxError:", "failed to load component", "is not installed", "is not a type", "Unsupported image format", "Cannot open:", "Error decoding:")
    if result.returncode or any(marker in result.stdout for marker in failures):
        raise SystemExit(result.returncode or 1)
    print("Offline demo rendered successfully with isolated desktop storage.")
